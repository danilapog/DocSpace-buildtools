#!/usr/bin/env bash

set -e

[ -f /opt/tg-bots/actions-notify-bot/.env ] && source /opt/tg-bots/actions-notify-bot/.env

SCRIPT_URL="https://raw.githubusercontent.com/ONLYOFFICE/DocSpace-buildtools/develop/tests/tg-bots/actions-notify-bot/check-actions.sh"
LOCAL_SCRIPT="/opt/tg-bots/actions-notify-bot/check-actions.sh"

curl -s -o "$LOCAL_SCRIPT" "$SCRIPT_URL"
chmod +x "$LOCAL_SCRIPT"

"$LOCAL_SCRIPT"

