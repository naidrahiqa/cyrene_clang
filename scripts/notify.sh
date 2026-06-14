#!/usr/bin/env bash
# CyreneClang — Enhanced Telegram Notification Script
# Sends build status notifications via Telegram Bot API with rich formatting,
# build metadata, and changelog support.
# Usage: ./notify.sh <started|success|failure|changelog>
set -euo pipefail

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
MESSAGE_TYPE="${1:-}"

[[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]] || exit 0

send_msg() {
  local text="$1"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$text" \
    -d parse_mode="Markdown" \
    -d disable_web_page_preview=true > /dev/null 2>&1 || true
}

RUN_NUMBER="${GITHUB_RUN_NUMBER:-local}"
RUN_ID="${GITHUB_RUN_ID:-0}"
REPO="${GITHUB_REPOSITORY:-cyrene-clang}"
RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"

CLANG_VERSION="${CLANG_VERSION:-unknown}"
LLVM_BRANCH="${LLVM_BRANCH:-main}"
LLVM_COMMIT="${LLVM_COMMIT:-unknown}"
ENABLE_PGO="${ENABLE_PGO:-true}"
LTO_MODE="${LTO_MODE:-Thin}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%d)}"
RELEASE_TAG="${RELEASE_TAG:-}"
CHANGELOG_FILE="${CHANGELOG_FILE:-}"
BUILD_DURATION="${BUILD_DURATION:-}"
BUILD_STAGE="${BUILD_STAGE:-}"
ERROR_LOG="${ERROR_LOG:-}"
PACKAGE_SIZE="${PACKAGE_SIZE:-}"
PATCH_COUNT="${PATCH_COUNT:-0}"
TARBALL_NAME="${TARBALL_NAME:-}"
TARGETS="${LLVM_TARGETS:-AArch64;ARM;X86}"

fmt_section() {
  echo -e "\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81\xE2\x94\x81"
}

case "$MESSAGE_TYPE" in
  started)
    MSG="\xF0\x9F\x9B\xA0  *CyreneClang Build #$RUN_NUMBER Started*
$(fmt_section)
\xF0\x9F\x93\x8C Branch: \`$LLVM_BRANCH\`
\xF0\x9F\x94\xA7 Commit: \`$LLVM_COMMIT\`
\xE2\x9A\x99\xEF\xB8\x8F PGO: $ENABLE_PGO | LTO: $LTO_MODE
\xF0\x9F\x8E\xAF Targets: $TARGETS
\xF0\x9F\x93\x86 Date: $BUILD_DATE
\xF0\x9F\x93\x9D Patches: $PATCH_COUNT pending

\xF0\x9F\x94\x97 [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg "$MSG"
    ;;

  success)
    CHANGELOG_TEXT=""
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      CHANGELOG_TEXT=$(head -c 1500 "$CHANGELOG_FILE" 2>/dev/null || true)
    fi

    PGO_STR="\xE2\x9C\x85 Enabled"
    [[ "$ENABLE_PGO" == "false" ]] && PGO_STR="\xE2\x9D\x8C Disabled"

    MSG="\xE2\x9C\x85  *CyreneClang Build #$RUN_NUMBER Succeeded*
$(fmt_section)
\xF0\x9F\x94\xA7 Clang: \`$CLANG_VERSION\` (LLVM $LLVM_COMMIT)
\xE2\x9A\x99\xEF\xB8\x8F PGO: $PGO_STR | LTO: $LTO_MODE
\xF0\x9F\x95\x90 Branch: \`$LLVM_BRANCH\`
\xF0\x9F\x93\xA6 Tag: \`${RELEASE_TAG:-none}\`
\xF0\x9F\x93\xA6 Package: \`$TARBALL_NAME\`
\xF0\x9F\x93\xA6 Size: $PACKAGE_SIZE
\xE2\x8F\xB1 Duration: $BUILD_DURATION
\xF0\x9F\x93\x86 Date: $BUILD_DATE"
    send_msg "$MSG"

    if [[ -n "$CHANGELOG_TEXT" ]]; then
      CHANGELOG_MSG="\xF0\x9F\x93\x8B  *Changelog \u2014 Build #$RUN_NUMBER*
$(fmt_section)
$CHANGELOG_TEXT"
      send_msg "$CHANGELOG_MSG"
    fi

    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    if [[ -n "$RELEASE_TAG" ]]; then
      RELEASE_MSG="\xF0\x9F\x93\xA6  *Release $RELEASE_TAG ready*
$(fmt_section)
\xF0\x9F\x94\x97 [Download Release]($RELEASE_URL)
\xE2\x8F\xB1 Build duration: $BUILD_DURATION"
      send_msg "$RELEASE_MSG"
    fi
    ;;

  failure)
    ERROR_SNIPPET=""
    if [[ -n "$ERROR_LOG" ]]; then
      ERROR_SNIPPET=$(echo "$ERROR_LOG" | head -c 1000)
    fi

    MSG="\xE2\x9D\x8C  *CyreneClang Build #$RUN_NUMBER Failed*
$(fmt_section)
\xF0\x9F\x93\x8C Branch: \`$LLVM_BRANCH\`
\xE2\x9A\x99\xEF\xB8\x8F PGO: $ENABLE_PGO | LTO: $LTO_MODE
\xF0\x9F\x93\x86 Date: $BUILD_DATE"

    if [[ -n "$BUILD_STAGE" ]]; then
      MSG="$MSG
\xF0\x9F\x93\x8D Stage: $BUILD_STAGE"
    fi
    if [[ -n "$BUILD_DURATION" ]]; then
      MSG="$MSG
\xE2\x8F\xB1 After: $BUILD_DURATION"
    fi
    if [[ -n "$ERROR_SNIPPET" ]]; then
      MSG="$MSG
$(fmt_section)
\`\`\`
$ERROR_SNIPPET
\`\`\`"
    fi

    MSG="$MSG
$(fmt_section)
\xF0\x9F\x94\x97 [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg "$MSG"
    ;;

  changelog)
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      CONTENT=$(cat "$CHANGELOG_FILE")
      MSG="\xF0\x9F\x93\x8B  *Build #$RUN_NUMBER Changelog*
$(fmt_section)
$CONTENT"
      send_msg "$MSG"
    fi
    ;;
esac
