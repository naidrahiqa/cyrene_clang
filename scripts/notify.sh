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
E_TARGET=$'\xF0\x9F\x94\xA5'      # 🔥
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
E_ROCKET=$'\xF0\x9F\x9A\x80'      # 🚀
E_FIRE=$'\xF0\x9F\x94\xA5'        # 🔥
E_HAMMER=$'\xF0\x9F\x94\xA8'      # 🔨
E_LIGHTNING=$'\xE2\x9A\xA1'       # ⚡
E_WARNING=$'\xE2\x9A\xA0\xEF\xB8\x8F' # ⚠️
E_INFO=$'\xE2\x84\xB9'            # ℹ️
E_BUG=$'\xF0\x9F\x90\x9B'         # 🐛
E_MAGNIFY=$'\xF0\x9F\x94\x8D'     # 🔍
E_ARTIFICIAL=$'\xF0\x9F\xA4\x96'  # 🤖
E_WAVE=$'\xF0\x9F\x91\x8B'        # 👋
E_GITHUB=$'\xE2\x9C\x93'          # ✓ (using check as github stand-in)
E_CI=$'\xF0\x9F\x9B\xA0'         # 🛠

fmt_section() {
  echo "$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE$E_LINE"
}

fmt_header() {
  local title="$1"
  echo "$E_ARTIFICIAL  *$title*
$(fmt_section)"
}

fmt_kv() {
  local icon="$1" label="$2" value="$3"
  echo "$icon $label: \`$value\`"
}

fmt_kv_raw() {
  local icon="$1" label="$2" value="$3"
  echo "$icon $label: $value"
}

fmt_commit_link() {
  local commit="$1"
  if [[ -n "$commit" && "$commit" != "unknown" ]]; then
    echo "$E_WRENCH Commit: [\`${commit:0:7}\`](https://github.com/$REPO/commit/$commit)"
  else
    echo "$E_WRENCH Commit: \`unknown\`"
  fi
}

case "$MESSAGE_TYPE" in
  started)
    MSG="$(fmt_header "CyreneClang Build #$RUN_NUMBER Started")"
    MSG="$MSG
$E_CI Build #$RUN_NUMBER triggered"
    MSG="$MSG
$(fmt_kv_raw "$E_PUSHPIN" "Branch" "$LLVM_BRANCH")"
    MSG="$MSG
$(fmt_commit_link "$LLVM_COMMIT")"
    MSG="$MSG
$(fmt_kv_raw "$E_GEAR" "PGO" "$ENABLE_PGO") | $(fmt_kv_raw "$E_DIRECT" "LTO" "$LTO_MODE")"
    MSG="$MSG
$(fmt_kv_raw "$E_TARGET" "Targets" "$TARGETS")"
    MSG="$MSG
$(fmt_kv_raw "$E_CALENDAR" "Date" "$BUILD_DATE")"
    MSG="$MSG
$(fmt_kv_raw "$E_MEMO" "Patches" "$PATCH_COUNT pending")"
    MSG="$MSG
$(fmt_section)
$E_ROCKET Building Clang $LLVM_BRANCH for Android kernels..."
    MSG="$MSG
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

    MSG="$(fmt_header "CyreneClang Build #$RUN_NUMBER SUCCEEDED")"
    MSG="$MSG
$E_CHECK *Build completed successfully!*
$E_STOPWATCH Duration: \`$BUILD_DURATION\`"
    MSG="$MSG
$(fmt_section)
$E_WRENCH *Toolchain Info:*"
    MSG="$MSG
$(fmt_kv_raw "$E_WRENCH" "Clang" "$CLANG_VERSION")"
    MSG="$MSG
$(fmt_kv_raw "$E_GEAR" "LLVM" "$LLVM_COMMIT")"
    MSG="$MSG
$(fmt_kv_raw "$E_GEAR" "PGO" "$PGO_STR") | $(fmt_kv_raw "$E_DIRECT" "LTO" "$LTO_MODE")"
    MSG="$MSG
$(fmt_kv_raw "$E_PUSHPIN" "Branch" "$LLVM_BRANCH")"
    MSG="$MSG
$(fmt_kv_raw "$E_CALENDAR" "Date" "$BUILD_DATE")"

    MSG="$MSG
$(fmt_section)
$E_PACKAGE *Release Package:*"
    MSG="$MSG
$(fmt_kv_raw "$E_PACKAGE" "Tag" "${RELEASE_TAG:-none}")"
    MSG="$MSG
$(fmt_kv_raw "$E_PACKAGE" "File" "$TARBALL_NAME")"
    MSG="$MSG
$(fmt_kv_raw "$E_PACKAGE" "Size" "$PACKAGE_SIZE")"

    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    if [[ -n "$RELEASE_TAG" ]]; then
      MSG="$MSG
$(fmt_section)
$E_ROCKET *Quick Download:*
\`\`\`
wget $RELEASE_URL/download/$RELEASE_TAG/$TARBALL_NAME
\`\`\`"
      MSG="$MSG
$E_LINK [View Release]($RELEASE_URL)"
    fi

    MSG="$MSG
$E_LINK [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg "$MSG"

    if [[ -n "$CHANGELOG_TEXT" ]]; then
      E_DASH=$'\xE2\x80\x94'
      CHANGELOG_MSG="$(fmt_header "Build #$RUN_NUMBER Changelog")"
      CHANGELOG_MSG="$CHANGELOG_MSG
$CHANGELOG_TEXT"
      CHANGELOG_MSG="$CHANGELOG_MSG
$(fmt_section)
$E_LINK [View Full Changelog](https://github.com/$REPO/releases/tag/$RELEASE_TAG)"
      send_msg "$CHANGELOG_MSG"
    fi
    ;;

  failure)
    ERROR_SNIPPET=""
    ERROR_FIRST_LINE=""
    if [[ -n "$ERROR_LOG" ]]; then
      ERROR_SNIPPET=$(echo "$ERROR_LOG" | tail -c 1500)
      ERROR_FIRST_LINE=$(echo "$ERROR_LOG" | grep -i "error\|fatal\|failed" | head -1 | head -c 120)
    elif [[ -n "$ERROR_DUMP_FILE" && -f "$ERROR_DUMP_FILE" ]]; then
      ERROR_SNIPPET=$(tail -c 1500 "$ERROR_DUMP_FILE" 2>/dev/null || true)
      ERROR_FIRST_LINE=$(grep -i "error\|fatal\|failed" "$ERROR_DUMP_FILE" 2>/dev/null | head -1 | head -c 120)
    fi

    MSG="$(fmt_header "CyreneClang Build #$RUN_NUMBER FAILED")"
    MSG="$MSG
$E_PUSHPIN Branch: \`$LLVM_BRANCH\`"
    MSG="$MSG
$(fmt_commit_link "$LLVM_COMMIT")"
    MSG="$MSG
$(fmt_kv_raw "$E_GEAR" "PGO" "$ENABLE_PGO") | $(fmt_kv_raw "$E_DIRECT" "LTO" "$LTO_MODE")"
    MSG="$MSG
$(fmt_kv_raw "$E_CALENDAR" "Date" "$BUILD_DATE")"

    if [[ -n "$BUILD_STAGE" ]]; then
      MSG="$MSG
$E_MEMO Stage: \`$BUILD_STAGE\`"
    fi
    if [[ -n "$BUILD_DURATION" ]]; then
      MSG="$MSG
$E_STOPWATCH Duration: $BUILD_DURATION"
    fi

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
$(fmt_section)
$E_BUG *First Error:*
\`\`\`
$ERROR_FIRST_LINE
\`\`\`"
    fi

    MSG="$MSG
$(fmt_section)
$E_LIGHTNING *Quick Fix Suggestions:*"
    MSG="$MSG
$E_BULLET Check if LLVM branch \`$LLVM_BRANCH\` exists"
    MSG="$MSG
$E_BULLET Verify patch compatibility with upstream"
    MSG="$MSG
$E_BULLET Review build log for missing dependencies"
    MSG="$MSG
$E_BULLET Check disk space and memory"

    if [[ -n "$ERROR_SNIPPET" ]]; then
      MSG="$MSG
$(fmt_section)
$E_MAGNIFY *Last 50 lines of build log:*
\`\`\`
$ERROR_SNIPPET
\`\`\`"
    fi

    MSG="$MSG
$(fmt_section)
$E_LINK [View Full Run #$RUN_NUMBER]($RUN_URL)"
    send_msg "$MSG"
    ;;

  error_dump)
    [[ -z "$ERROR_DUMP_CHAT_ID" ]] && exit 0
    FULL_LOG=""
    ERROR_FIRST_LINE=""
    if [[ -n "$ERROR_LOG" ]]; then
      FULL_LOG="$ERROR_LOG"
      ERROR_FIRST_LINE=$(echo "$ERROR_LOG" | grep -i "error\|fatal\|failed" | head -1 | head -c 150)
    fi
    if [[ -z "$FULL_LOG" && -n "$ERROR_DUMP_FILE" && -f "$ERROR_DUMP_FILE" ]]; then
      FULL_LOG=$(tail -c 4000 "$ERROR_DUMP_FILE" 2>/dev/null || true)
      ERROR_FIRST_LINE=$(grep -i "error\|fatal\|failed" "$ERROR_DUMP_FILE" 2>/dev/null | head -1 | head -c 150)
    fi

    MSG="$(fmt_header "CyreneClang Build #$RUN_NUMBER $E_DASH Error Dump")"
    MSG="$MSG
$E_BUG *Full error log from failed build*"
    MSG="$MSG
$(fmt_section)
$E_PUSHPIN Branch: \`$LLVM_BRANCH\`"
    MSG="$MSG
$(fmt_commit_link "$LLVM_COMMIT")"
    MSG="$MSG
$(fmt_kv_raw "$E_GEAR" "PGO" "$ENABLE_PGO") | $(fmt_kv_raw "$E_DIRECT" "LTO" "$LTO_MODE")"
    MSG="$MSG
$(fmt_kv_raw "$E_DIRECT" "Targets" "$TARGETS")"

    if [[ -n "$BUILD_STAGE" ]]; then
      MSG="$MSG
$E_MEMO Stage: \`$BUILD_STAGE\`"
    fi
    if [[ -n "$BUILD_DURATION" ]]; then
      MSG="$MSG
$E_STOPWATCH Duration: $BUILD_DURATION"
    fi

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
$(fmt_section)
$E_LIGHTNING *First Error:*
\`\`\`
$ERROR_FIRST_LINE
\`\`\`"
    fi

    MSG="$MSG
$(fmt_section)
$E_MAGNIFY *Build Log (last 4000 chars):*
\`\`\`
$FULL_LOG
\`\`\`"

    MSG="$MSG
$(fmt_section)
$E_LINK [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg_to "$ERROR_DUMP_CHAT_ID" "$MSG"
    ;;

  changelog)
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      CONTENT=$(cat "$CHANGELOG_FILE")
      MSG="$(fmt_header "Build #$RUN_NUMBER Changelog")"
      MSG="$MSG
$CONTENT"
      MSG="$MSG
$(fmt_section)
$E_LINK [View Release](https://github.com/$REPO/releases/tag/$RELEASE_TAG)"
      send_msg "$MSG"
    fi
    ;;
esac
