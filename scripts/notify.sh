#!/usr/bin/env bash
# CyreneClang — Telegram Notification Script
# Sends build status notifications via Telegram Bot API.
# Requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID env vars.
set -euo pipefail

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
MESSAGE_TYPE="${1:-}"
RUN_NUMBER="${2:-$GITHUB_RUN_NUMBER}"
RUN_ID="${3:-$GITHUB_RUN_ID}"
REPO="${GITHUB_REPOSITORY:-cyrene-clang}"

[[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]] || exit 0

send_msg() {
  local text="$1"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$text" \
    -d parse_mode="Markdown" \
    -d disable_web_page_preview=true > /dev/null 2>&1 || true
}

RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"

case "$MESSAGE_TYPE" in
  started)
    send_msg "\xF0\x9F\x9B\xA0 *CyreneClang Build #$RUN_NUMBER Started*
Branch: \`${LLVM_BRANCH:-main}\`
PGO: ${ENABLE_PGO:-true}
View: [Run #$RUN_NUMBER]($RUN_URL)"
    ;;
  success)
    send_msg "\xE2\x9C\x85 *CyreneClang Build #$RUN_NUMBER Succeeded*
Toolchain: \`${CLANG_VERSION:-unknown}\`
Release: \`${RELEASE_TAG:-}\`
View: [Run #$RUN_NUMBER]($RUN_URL)"
    ;;
  failure)
    send_msg "\xE2\x9D\x8C *CyreneClang Build #$RUN_NUMBER Failed*
View: [Run #$RUN_NUMBER]($RUN_URL)"
    ;;
  release)
    local tag="$RELEASE_TAG"
    local url="https://github.com/$REPO/releases/tag/$tag"
    send_msg "\xF0\x9F\x93\xA6 *CyreneClang $tag Released*
Download: $url"
    ;;
esac
