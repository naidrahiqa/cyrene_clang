#!/usr/bin/env bash
# Cyrene Clang — Enhanced Telegram Notification Script
# Sends build status notifications via Telegram Bot API with rich formatting,
# build metadata, and changelog support.
# Usage: ./notify.sh <started|success|failure|error_dump|changelog|release>
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

# ─── Build metadata ───────────────────────────────────────────────────────────
RUN_NUMBER="${GITHUB_RUN_NUMBER:-local}"
RUN_ID="${GITHUB_RUN_ID:-0}"
REPO="${GITHUB_REPOSITORY:-naidrahiqa/cyrene_clang}"
RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
CYRENE_COMMIT="${GITHUB_SHA:-unknown}"

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

# ─── Formatting helpers ───────────────────────────────────────────────────────
LINE="━━━━━━━━━━━━━━━━━━━━"

fmt_section() { echo "$LINE"; }
fmt_header() { echo "🤖 *$1*
$LINE"; }
fmt_kv() { echo "$1 $2: \`$3\`"; }
fmt_kv_raw() { echo "$1 $2: $3"; }

fmt_commit_link() {
  local commit="$1"
  if [[ -n "$commit" && "$commit" != "unknown" ]]; then
    echo "🔧 Commit: [\`${commit:0:7}\`](https://github.com/llvm/llvm-project/commit/$commit)"
  else
    echo "🔧 Commit: \`pending\` _(will update after clone)_"
  fi
}

fmt_llvm_link() {
  local commit="$1"
  if [[ -n "$commit" && "$commit" != "unknown" ]]; then
    echo "⚙️ LLVM: [\`${commit:0:7}\`](https://github.com/llvm/llvm-project/commit/$commit)"
  else
    echo "⚙️ LLVM: \`unknown\`"
  fi
}

fmt_cyrene_link() {
  local commit="$1"
  if [[ -n "$commit" && "$commit" != "unknown" ]]; then
    echo "🔧 Cyrene Clang: [\`${commit:0:7}\`](https://github.com/$REPO/commit/$commit)"
  else
    echo "🔧 Cyrene Clang: \`unknown\`"
  fi
}

# ─── Message handlers ─────────────────────────────────────────────────────────
case "$MESSAGE_TYPE" in
  started)
    MSG="$(fmt_header "Cyrene Clang Build #$RUN_NUMBER Started")"
    MSG="$MSG
🛠 *Build #$RUN_NUMBER triggered*"
    MSG="$MSG
$(fmt_cyrene_link "$CYRENE_COMMIT")"
    MSG="$MSG
📌 Branch: \`$LLVM_BRANCH\`"
    MSG="$MSG
$(fmt_llvm_link "$LLVM_COMMIT")"
    MSG="$MSG
⚙️ PGO: $ENABLE_PGO | 🎯 LTO: $LTO_MODE"
    MSG="$MSG
🔥 Targets: $TARGETS"
    MSG="$MSG
📆 Date: $BUILD_DATE"
    MSG="$MSG
📝 Patches: $PATCH_COUNT pending"
    MSG="$MSG
$(fmt_section)
🚀 *Building custom LLVM/Clang for Android kernel development*"
    MSG="$MSG
👋 Queued at $(date -u +%H:%M:%S) UTC"
    MSG="$MSG
🔗 [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg "$MSG"
    ;;

  success)
    CHANGELOG_TEXT=""
    if [[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]]; then
      CHANGELOG_TEXT=$(head -c 1500 "$CHANGELOG_FILE" 2>/dev/null || true)
    fi

    PGO_STR="✅ Enabled"
    [[ "$ENABLE_PGO" == "false" ]] && PGO_STR="❌ Disabled"

    MSG="$(fmt_header "Cyrene Clang Build #$RUN_NUMBER SUCCEEDED")"
    MSG="$MSG
✅ *Build completed successfully!*
⏱ Duration: \`$BUILD_DURATION\`"
    MSG="$MSG
$(fmt_section)
🔧 *Toolchain Info:*"
    MSG="$MSG
🔧 Clang: $CLANG_VERSION"
    MSG="$MSG
$(fmt_cyrene_link "$CYRENE_COMMIT")"
    MSG="$MSG
$(fmt_llvm_link "$LLVM_COMMIT")"
    MSG="$MSG
⚙️ PGO: $PGO_STR | 🎯 LTO: $LTO_MODE"
    MSG="$MSG
📌 Branch: \`$LLVM_BRANCH\`"
    MSG="$MSG
📆 Date: $BUILD_DATE"

    MSG="$MSG
$(fmt_section)
📦 *Release Package:*"
    MSG="$MSG
📦 Tag: ${RELEASE_TAG:-none}"
    MSG="$MSG
📦 File: $TARBALL_NAME"
    MSG="$MSG
📦 Size: $PACKAGE_SIZE"

    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    if [[ -n "$RELEASE_TAG" ]]; then
      MSG="$MSG
$(fmt_section)
🚀 *Quick Download:*
\`\`\`
wget $RELEASE_URL/download/$RELEASE_TAG/$TARBALL_NAME
\`\`\`"
      MSG="$MSG
🔗 [View Release]($RELEASE_URL)"
    fi

    MSG="$MSG
🔗 [View Run #$RUN_NUMBER]($RUN_URL)"
    send_msg "$MSG"

    if [[ -n "$CHANGELOG_TEXT" ]]; then
      CHANGELOG_MSG="$(fmt_header "Build #$RUN_NUMBER Changelog")"
      CHANGELOG_MSG="$CHANGELOG_MSG
$CHANGELOG_TEXT"
      CHANGELOG_MSG="$CHANGELOG_MSG
$(fmt_section)
🔗 [View Full Changelog](https://github.com/$REPO/releases/tag/$RELEASE_TAG)"
      send_msg "$CHANGELOG_MSG"
    fi
    ;;

  failure)
    ERROR_SNIPPET=""
    ERROR_FIRST_LINE=""
    if [[ -n "$ERROR_LOG" ]]; then
      ERROR_SNIPPET=$(echo "$ERROR_LOG" | tail -c 1500)
      ERROR_FIRST_LINE=$(echo "$ERROR_LOG" | grep -i "error\|fatal\|failed" | head -1 | head -c 120)
    elif [[ -n "$ERROR_DUMP_FILE" && -f "$ERROR_DUMP_FILE" && -s "$ERROR_DUMP_FILE" ]]; then
      ERROR_SNIPPET=$(tail -c 1500 "$ERROR_DUMP_FILE" 2>/dev/null || true)
      ERROR_FIRST_LINE=$(grep -i "error\|fatal\|failed" "$ERROR_DUMP_FILE" 2>/dev/null | head -1 | head -c 120)
    fi

    MSG="$(fmt_header "Cyrene Clang Build #$RUN_NUMBER FAILED")"
    MSG="$MSG
$(fmt_cyrene_link "$CYRENE_COMMIT")"
    MSG="$MSG
📌 Branch: \`$LLVM_BRANCH\`"
    MSG="$MSG
$(fmt_llvm_link "$LLVM_COMMIT")"
    MSG="$MSG
⚙️ PGO: $ENABLE_PGO | 🎯 LTO: $LTO_MODE"
    MSG="$MSG
📆 Date: $BUILD_DATE"
    MSG="$MSG
📝 Stage: \`${BUILD_STAGE:-unknown}\`"
    MSG="$MSG
⏱ Duration: \`${BUILD_DURATION:-unknown}\`"

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
$(fmt_section)
🐛 *Error:*
\`\`\`
$ERROR_FIRST_LINE
\`\`\`"
    fi

    MSG="$MSG
$(fmt_section)
⚡ *Quick Fix Suggestions:*"
    MSG="$MSG
• Check if LLVM branch \`$LLVM_BRANCH\` exists"
    MSG="$MSG
• Verify patch compatibility with upstream"
    MSG="$MSG
• Review build log for missing dependencies"
    MSG="$MSG
• Check disk space and memory"

    if [[ -n "$ERROR_SNIPPET" ]]; then
      MSG="$MSG
$(fmt_section)
🔍 *Build Log (last 50 lines):*
\`\`\`
$ERROR_SNIPPET
\`\`\`"
    else
      MSG="$MSG
$(fmt_section)
ℹ️ _No error log available — build may have failed before logging started_"
    fi

    MSG="$MSG
$(fmt_section)
🔗 [View Full Run #$RUN_NUMBER]($RUN_URL)"
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
    if [[ -z "$FULL_LOG" && -n "$ERROR_DUMP_FILE" && -f "$ERROR_DUMP_FILE" && -s "$ERROR_DUMP_FILE" ]]; then
      FULL_LOG=$(tail -c 4000 "$ERROR_DUMP_FILE" 2>/dev/null || true)
      ERROR_FIRST_LINE=$(grep -i "error\|fatal\|failed" "$ERROR_DUMP_FILE" 2>/dev/null | head -1 | head -c 150)
    fi

    MSG="$(fmt_header "Cyrene Clang Build #$RUN_NUMBER — Error Dump")"
    MSG="$MSG
🐛 *Full error log from failed build*"
    MSG="$MSG
$(fmt_section)
$(fmt_cyrene_link "$CYRENE_COMMIT")"
    MSG="$MSG
📌 Branch: \`$LLVM_BRANCH\`"
    MSG="$MSG
$(fmt_llvm_link "$LLVM_COMMIT")"
    MSG="$MSG
⚙️ PGO: $ENABLE_PGO | 🎯 LTO: $LTO_MODE"
    MSG="$MSG
🎯 Targets: $TARGETS"
    MSG="$MSG
📝 Stage: \`${BUILD_STAGE:-unknown}\`"
    MSG="$MSG
⏱ Duration: \`${BUILD_DURATION:-unknown}\`"

    if [[ -n "$ERROR_FIRST_LINE" ]]; then
      MSG="$MSG
$(fmt_section)
⚡ *First Error:*
\`\`\`
$ERROR_FIRST_LINE
\`\`\`"
    fi

    if [[ -n "$FULL_LOG" ]]; then
      MSG="$MSG
$(fmt_section)
🔍 *Build Log (last 4000 chars):*
\`\`\`
$FULL_LOG
\`\`\`"
    else
      MSG="$MSG
$(fmt_section)
ℹ️ _No error log available — build may have failed before logging started_"
    fi

    MSG="$MSG
$(fmt_section)
🔗 [View Run #$RUN_NUMBER]($RUN_URL)"
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
🔗 [View Release](https://github.com/$REPO/releases/tag/$RELEASE_TAG)"
      send_msg "$MSG"
    fi
    ;;

  release)
    RELEASE_URL="https://github.com/$REPO/releases/tag/$RELEASE_TAG"
    MSG="$(fmt_header "Cyrene Clang $RELEASE_TAG Released")"
    MSG="$MSG
✅ *Release published successfully!*"
    MSG="$MSG
$(fmt_section)
📦 *Release Info:*"
    MSG="$MSG
📦 Tag: $RELEASE_TAG"
    MSG="$MSG
📦 File: ${TARBALL_NAME:-unknown}"
    MSG="$MSG
📦 Size: ${PACKAGE_SIZE:-unknown}"
    MSG="$MSG
$(fmt_section)
🚀 *Quick Download:*
\`\`\`
wget $RELEASE_URL/download/$RELEASE_TAG/${TARBALL_NAME:-cyrene-clang.tar.zst}
\`\`\`"
    MSG="$MSG
🔗 [View Release]($RELEASE_URL)"
    send_msg "$MSG"
    ;;
esac
