#!/usr/bin/env bash
# Source pinning for Docker builds and the secure rebuild of released DocSpace images.
#
# Usage:
#   secure-rebuild.sh resolve-sources BRANCH [BUILDTOOLS_BRANCH] [SERVER_BRANCH] [CLIENT_BRANCH]
#       Prints the sources JSON of one build: the repository, branch and commit of each source repository.
#       Branches are picked as the Dockerfile picks them: an explicit branch must exist, an implicit one is
#       BRANCH when the repository has it and develop otherwise; plugins and campaigns build from master.
#   secure-rebuild.sh bake-args SOURCES_JSON
#       Prints one docker buildx bake --set option per line: the *_REPO, *_BRANCH and *_COMMIT build arguments
#       and the com.onlyoffice.docspace.<source>.* image labels that record them.
#   secure-rebuild.sh record-release RELEASE_VERSION BAKE_PRINT
#       Records in CONFIG a release: BAKE_PRINT is docker buildx bake --print of the released targets with the
#       4testing source tag (DOCKER_TAG). One record per release tag holds its services (bake targets), the source
#       build, its commits (read from the image labels) and the services whose latest tag points to it. The released
#       services leave the older records of their line, so a service is rebuilt for every line it is published in,
#       from the release its N.N.N tag points to.
#
# Environment: GITHUB_REPOSITORY (buildtools), SOURCE_OWNER (Server and Client, default: the buildtools owner),
# CONFIG (default .github/secure-rebuild.json), FALLBACK_BRANCH (default develop).

set -euo pipefail

CONFIG="${CONFIG:-.github/secure-rebuild.json}"
FALLBACK_BRANCH="${FALLBACK_BRANCH:-develop}"
LABEL_PREFIX="com.onlyoffice.docspace"
SOURCES=(buildtools server client plugins campaigns)

die() { echo "::error::$*" >&2; exit 1; }

branch_exists() {
  git ls-remote --exit-code --heads "$1" "refs/heads/$2" >/dev/null 2>&1
}

# Prints the commit of a branch, failing when the branch does not exist
branch_commit() {
  local COMMIT
  COMMIT=$(git ls-remote --exit-code --heads "$1" "refs/heads/$2" | awk 'NR == 1 {print $1}') || die "Branch $2 does not exist in $1"
  [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "Cannot read the commit of $2 in $1"
  echo "$COMMIT"
}

resolve_sources() {
  local BRANCH="${1:?branch}" BUILDTOOLS_BRANCH="${2:-}" SERVER_BRANCH="${3:-}" CLIENT_BRANCH="${4:-}"
  local REPOSITORY="${GITHUB_REPOSITORY:?}"
  local OWNER="${SOURCE_OWNER:-${REPOSITORY%%/*}}"
  local -A REPO=(
    [buildtools]="https://github.com/${REPOSITORY}.git"
    [server]="https://github.com/${OWNER}/DocSpace-server.git"
    [client]="https://github.com/${OWNER}/DocSpace-client.git"
    [plugins]="https://github.com/ONLYOFFICE/docspace-plugins.git"
    [campaigns]="https://github.com/ONLYOFFICE/ASC.Web.Campaigns.git"
  )
  local -A REF=(
    [buildtools]="${BUILDTOOLS_BRANCH:-$BRANCH}" [server]="$SERVER_BRANCH" [client]="$CLIENT_BRANCH"
    [plugins]=master [campaigns]=master
  )
  local NAME RESULT='{}'
  for NAME in "${SOURCES[@]}"; do
    if [ -z "${REF[$NAME]}" ]; then
      branch_exists "${REPO[$NAME]}" "$BRANCH" && REF[$NAME]="$BRANCH" || REF[$NAME]="$FALLBACK_BRANCH"
    fi
    RESULT=$(jq -c --arg name "$NAME" --arg repo "${REPO[$NAME]}" --arg branch "${REF[$NAME]}" \
      --arg commit "$(branch_commit "${REPO[$NAME]}" "${REF[$NAME]}")" \
      '.[$name] = {repo: $repo, branch: $branch, commit: $commit}' <<< "$RESULT")
  done
  echo "$RESULT"
}

validate_sources() {
  jq -e --argjson names "$(printf '%s\n' "${SOURCES[@]}" | jq -R . | jq -sc .)" '
    (keys | sort) == ($names | sort)
    and all(.[]; (.repo | test("^https://github\\.com/[A-Za-z0-9-]+/[A-Za-z0-9._-]+\\.git$"))
                 and (.branch | test("^[A-Za-z0-9._/-]+$"))
                 and (.commit | test("^[0-9a-f]{40}$")))
  ' >/dev/null <<< "$1" || die "Invalid sources: $1"
}

bake_args() {
  local SOURCES_JSON="${1:?sources JSON}"
  validate_sources "$SOURCES_JSON"
  jq -r --arg prefix "$LABEL_PREFIX" '
    to_entries[] | .key as $name | .value | to_entries[]
    | "--set=*.args.\($name | ascii_upcase)_\(.key | ascii_upcase)=\(.value)",
      "--set=*.labels.\($prefix).\($name).\(.key)=\(.value)"
  ' <<< "$SOURCES_JSON"
}

record_release() {
  local RELEASE_VERSION="${1:?release version}" BAKE_PRINT="${2:?bake --print output}"
  [[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Release version must be N.N.N.N: $RELEASE_VERSION"
  local LINE="${RELEASE_VERSION%.*}" SERVICES IMAGE
  SERVICES=$(jq -c '.target | keys' <<< "$BAKE_PRINT")
  [ "$SERVICES" != "[]" ] || die "No released services"
  # Any released image tells the sources: all of them come from one build
  IMAGE=$(jq -r '(.target["onlyoffice-api"] // (.target | to_entries[0].value)).tags[0]' <<< "$BAKE_PRINT")
  local SOURCE_TAG="${IMAGE##*:}"
  [[ "$SOURCE_TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Source tag must be N.N.N.N (product version and build number): $SOURCE_TAG"
  [ "${SOURCE_TAG%.*}" = "$LINE" ] || die "Source $SOURCE_TAG is not of the ${LINE} release line"

  [ -f "$CONFIG" ] || echo '{"releases": {}}' > "$CONFIG"
  # The sources of every platform are the same build, so one platform is enough
  local LABELS SOURCES_JSON
  LABELS=$(docker buildx imagetools inspect --format '{{json .Image}}' "$IMAGE" | jq -c '.["linux/amd64"].config.Labels // {}')
  SOURCES_JSON=$(jq -c --arg prefix "$LABEL_PREFIX." '
    with_entries(select(.key | startswith($prefix)))
    | reduce to_entries[] as $e ({}; ($e.key | ltrimstr($prefix) | split(".")) as $k | .[$k[0]][$k[1]] = $e.value)
  ' <<< "$LABELS")
  [ "$SOURCES_JSON" != "{}" ] || die "$IMAGE has no ${LABEL_PREFIX}.* labels: it was built before the sources were recorded"
  validate_sources "$SOURCES_JSON"

  # latest is recorded only when the release moved it (see release-docker.sh is_newest_release_line)
  local RELEASE_IMAGE="${IMAGE%:*}" LATEST=false
  RELEASE_IMAGE="${RELEASE_IMAGE/\/4testing-//}"
  [ "$(docker buildx imagetools inspect --format '{{json .Manifest.Digest}}' "${RELEASE_IMAGE}:latest" 2>/dev/null)" = \
    "$(docker buildx imagetools inspect --format '{{json .Manifest.Digest}}' "${RELEASE_IMAGE}:${RELEASE_VERSION}")" ] && LATEST=true

  # The released services leave the older records of their line (their N.N.N tag now points to this release) and,
  # when the release moved latest, the latest list of every other record. Other lines keep their services: their
  # N.N.N.N and N.N.N tags stay published. A record without services left is dropped.
  local TMP; TMP=$(mktemp)
  jq --arg line "$LINE" --arg release "$RELEASE_VERSION" --arg source "$SOURCE_TAG" --argjson latest "$LATEST" \
     --argjson services "$SERVICES" --argjson sources "$SOURCES_JSON" '
    .releases |= (
      map_values(if .line == $line then .services -= $services | .latest -= $services else . end)
      | (if $latest then map_values(.latest -= $services) else . end)
      | with_entries(select(.value.services != [] and .key != $release))
      | .[$release] = {line: $line, source_tag: $source, services: $services,
                       latest: (if $latest then $services else [] end), sources: $sources}
      | to_entries | sort_by(.key | split(".") | map(tonumber)) | reverse | from_entries
    )
  ' "$CONFIG" > "$TMP"
  mv "$TMP" "$CONFIG"
  echo "Recorded ${RELEASE_VERSION} (source ${SOURCE_TAG}, latest: ${LATEST}) in ${CONFIG}:"
  jq --arg release "$RELEASE_VERSION" '.releases[$release]' "$CONFIG"
}

case "${1:-}" in
  resolve-sources) shift; resolve_sources "$@" ;;
  bake-args)       shift; bake_args "$@" ;;
  record-release)  shift; record_release "$@" ;;
  *) sed -n '2,20p' "$0" >&2; exit 2 ;;
esac
