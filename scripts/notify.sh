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

send_msg_to() {
  local cid="$1" text="$2"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$cid" \
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
ERROR_DUMP_CHAT_ID="${ERROR_DUMP_CHAT_ID:-}"
ERROR_DUMP_FILE="${ERROR_DUMP_FILE:-}"

# Emoji constants using $'...' for proper Unicode byte interpretation
E_TOOLS=$'\xF0\x9F\x9B\xA0'       # 🛠
E_PUSHPIN=$'\xF0\x9F\x93\x8C'     # 📌
E_WRENCH=$'\xF0\x9F\x94\xA7'      # 🔧
E_GEAR=$'\xE2\x9A\x99\xEF\xB8\x8F' # ⚙️
E_DIRECT=$'\xF0\x9F\x8E\xAF'      # 🎯
E_CALENDAR=$'\xF0\x9F\x93\x86'    # 📆
E_MEMO=$'\xF0\x9F\x93\x9D'        # 📝
E_LINK=$'\xF0\x9F\x94\x97'        # 🔗
E_CHECK=$'\xE2\x9C\x85'           # ✅
E_CROSS=$'\xE2\x9D\x8C'           # ❌
E_CLOCK=$'\xF0\x9F\x95\x90'       # 🕐
E_PACKAGE=$'\xF0\x9F\x93\xA6'     # 📦
E_STOPWATCH=$'\xE2\x8F\xB1'       # ⏱
E_CLIPBOARD=$'\xF0\x9F\x93\x8B'   # 📋
E_BULLET=$'\xE2\x80\xA2'          # •
E_LINE=$'\xE2\x94\x81'            # ━

fmt_section() {
  echo "$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE"
}

case "$MESSAGE_TYPE" in
  started)
    MSG="$E_TOOLS  *CyreneClang Build #$RUN_NUMBER Started*
$(fmt_section)
$E_PUSHPIN Branch: \`$LLVM_BRANCH\`
$E_WRENCH Commit: \`$LLVM_COMMIT\`
$E_GEAR PGO: $ENABLE_PGO | LTO: $LTO_MODE
$E_DIRECT Targets: $TARGETS
$E_CALENDAR Date: $BUILD_DATE
$E_MEMO Patches: $PATCH_COUNT pending

$E_LINK [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg "$MSG"
    ;;

  success)
    CHANGELOG_TEXT=""
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      CHANGELOG_TEXT=$(head -c 1500 "$CHANGELOG_FILE" 2>/dev/null || true)
    fi

    PGO_STR="$E_CHECK Enabled"
    [[ "$ENABLE_PGO" == "false" ]] && PGO_STR="$E_CROSS Disabled"

    MSG="$E_CHECK  *CyreneClang Build #$RUN_NUMBER Succeeded*
$(fmt_section)
$E_WRENCH Clang: \`$CLANG_VERSION\` (LLVM $LLVM_COMMIT)
$E_GEAR PGO: $PGO_STR | LTO: $LTO_MODE
$E_CLOCK Branch: \`$LLVM_BRANCH\`
$E_PACKAGE Tag: \`${RELEASE_TAG:-none}\`
$E_PACKAGE Package: \`$TARBALL_NAME\`
$E_PACKAGE Size: $PACKAGE_SIZE
$E_STOPWATCH Duration: $BUILD_DURATION
$E_CALENDAR Date: $BUILD_DATE"
    send_msg "$MSG"

    if [[ -n "$CHANGELOG_TEXT" ]]; then
      E_DASH=$'\xE2\x80\x94'
      CHANGELOG_MSG="$E_CLIPBOARD  *Changelog $E_DASH Build #$RUN_NUMBER*
$(fmt_section)
$CHANGELOG_TEXT"
      send_msg "$CHANGELOG_MSG"
    fi

    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    if [[ -n "$RELEASE_TAG" ]]; then
      RELEASE_MSG="$E_PACKAGE  *Release $RELEASE_TAG ready*
$(fmt_section)
$E_LINK [Download Release]($RELEASE_URL)
$E_STOPWATCH Build duration: $BUILD_DURATION"
      send_msg "$RELEASE_MSG"
    fi
    ;;

  failure)
    ERROR_SNIPPET=""
    if [[ -n "$ERROR_LOG" ]]; then
      ERROR_SNIPPET=$(echo "$ERROR_LOG" | head -c 1000)
    fi

    MSG="$E_CROSS  *CyreneClang Build #$RUN_NUMBER Failed*
$(fmt_section)
$E_PUSHPIN Branch: \`$LLVM_BRANCH\`
$E_GEAR PGO: $ENABLE_PGO | LTO: $LTO_MODE
$E_CALENDAR Date: $BUILD_DATE"

    if [[ -n "$BUILD_STAGE" ]]; then
      MSG="$MSG
$E_MEMO Stage: $BUILD_STAGE"
    fi
    if [[ -n "$BUILD_DURATION" ]]; then
      MSG="$MSG
$E_STOPWATCH After: $BUILD_DURATION"
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
$E_LINK [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg "$MSG"
    ;;

  error_dump)
    [[ -z "$ERROR_DUMP_CHAT_ID" ]] && exit 0
    FULL_LOG=""
    if [[ -n "$ERROR_LOG" ]]; then
      FULL_LOG="$ERROR_LOG"
    fi
    if [[ -z "$FULL_LOG" && -n "$ERROR_DUMP_FILE" && -f "$ERROR_DUMP_FILE" ]]; then
      FULL_LOG=$(tail -c 3000 "$ERROR_DUMP_FILE" 2>/dev/null || true)
    fi

    E_DASH=$'\xE2\x80\x94'
    MSG="$E_CROSS  *CyreneClang Build #$RUN_NUMBER $E_DASH Error Dump*
$(fmt_section)
$E_PUSHPIN Branch: \`$LLVM_BRANCH\`
$E_WRENCH Commit: \`$LLVM_COMMIT\`
$E_GEAR PGO: $ENABLE_PGO | LTO: $LTO_MODE
$E_DIRECT Targets: $TARGETS"

    if [[ -n "$BUILD_STAGE" ]]; then
      MSG="$MSG
$E_MEMO Stage: $BUILD_STAGE"
    fi
    if [[ -n "$BUILD_DURATION" ]]; then
      MSG="$MSG
$E_STOPWATCH After: $BUILD_DURATION"
    fi
    if [[ -n "$FULL_LOG" ]]; then
      MSG="$MSG
$(fmt_section)
\`\`\`
$FULL_LOG
\`\`\`"
    fi

    MSG="$MSG
$(fmt_section)
$E_LINK [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg_to "$ERROR_DUMP_CHAT_ID" "$MSG"
    ;;

  changelog)
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      CONTENT=$(cat "$CHANGELOG_FILE")
      MSG="$E_CLIPBOARD  *Build #$RUN_NUMBER Changelog*
$(fmt_section)
$CONTENT"
      send_msg "$MSG"
    fi
    ;;
esac
