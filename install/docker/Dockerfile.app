ARG SRC_PATH="/app/onlyoffice/src"
ARG BUILD_PATH="/var/www"
ARG DOTNET_SDK="mcr.microsoft.com/dotnet/sdk:8.0"
ARG DOTNET_RUN="mcr.microsoft.com/dotnet/aspnet:8.0"

FROM $DOTNET_SDK AS base
ARG CUSTOM_BUILD_COMMANDS=""
ARG RELEASE_DATE="2016-06-22"
ARG DEBIAN_FRONTEND=noninteractive
ARG PRODUCT_VERSION=0.0.0
ARG BUILD_NUMBER=0
ARG GIT_BRANCH="master"
ARG SRC_PATH
ARG BUILD_PATH
ARG BUILD_ARGS="build"
ARG DEPLOY_ARGS="deploy"
ARG DEBUG_INFO="true"
ARG PUBLISH_CNF="Release"

LABEL onlyoffice.appserver.release-date="${RELEASE_DATE}" \
      maintainer="Ascensio System SIA <support@onlyoffice.com>"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN apt-get -y update && \
    apt-get install -yq \
        sudo \
        locales \
        git \
        python3-pip \
        npm  && \
    locale-gen en_US.UTF-8 && \
    npm install --global yarn && \
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/nodesource.gpg --import && \
    chmod 644 /usr/share/keyrings/nodesource.gpg && \
    apt-get -y update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

ADD https://api.github.com/repos/ONLYOFFICE/DocSpace-buildtools/git/refs/heads/${GIT_BRANCH} version.json
RUN git clone -b ${GIT_BRANCH} https://github.com/ONLYOFFICE/DocSpace-buildtools.git ${SRC_PATH}/buildtools && \
    git clone --recurse-submodules -b ${GIT_BRANCH} https://github.com/ONLYOFFICE/DocSpace-Server.git ${SRC_PATH}/server && \
    git clone -b ${GIT_BRANCH} https://github.com/ONLYOFFICE/DocSpace-Client.git ${SRC_PATH}/client && \
    git clone -b "master" --depth 1 https://github.com/ONLYOFFICE/ASC.Web.Campaigns.git ${SRC_PATH}/campaigns ${CUSTOM_BUILD_COMMANDS}
