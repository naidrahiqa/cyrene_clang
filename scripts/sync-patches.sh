#!/usr/bin/env bash
# CyreneClang — Auto Cherry-Pick Patches from LLVM Stable
# Reads patches/stable-picks.txt, fetches each commit from LLVM remote,
# and creates .patch files in patches/ with format: NNNN-<hash>-<subject>.patch
set -euo pipefail

LLVM_DIR="${LLVM_DIR:-$(pwd)/llvm-project}"
PATCHES_DIR="$(cd "$(dirname "$0")/../patches" && pwd)"
CONFIG_FILE="$PATCHES_DIR/stable-picks.txt"
LLVM_REMOTE="https://github.com/llvm/llvm-project.git"

log() { echo -e "\033[1;32m[Sync-Patches]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

[[ -f "$CONFIG_FILE" ]] || die "Config not found: $CONFIG_FILE"

mkdir -p "$PATCHES_DIR"

# ─── Ensure LLVM source is available ──────────────────────────────────────
if [[ ! -d "$LLVM_DIR/.git" ]]; then
  log "Cloning LLVM (--depth=1) for commit lookup..."
  git clone --depth=1 "$LLVM_REMOTE" "$LLVM_DIR"
fi

# ─── Get next patch number ────────────────────────────────────────────────
next_number() {
  local max=0
  for f in "$PATCHES_DIR"/*.patch; do
    [[ -f "$f" ]] || continue
    local n
    n=$(basename "$f" | grep -oP '^\K\d+')
    n="${n:-0}"
    [[ "$n" -gt "$max" ]] && max="$n"
  done
  echo $((max + 1))
}

SKIPPED=0
APPLIED=0
FAILED=0

# ─── Process each commit hash ─────────────────────────────────────────────
while IFS= read -r line; do
  line="${line%%#*}"  # strip comments
  line="${line// /}"   # strip whitespace
  [[ -z "$line" ]] && continue

  commit="$line"
  log "Processing commit: $commit"

  # Skip if patch already exists
  if ls "$PATCHES_DIR"/*-"${commit:0:7}"*.patch &>/dev/null 2>&1; then
    log "  → Skipped (already exists)"
    ((SKIPPED++)) || true
    continue
  fi

  # Fetch the specific commit
  if ! git -C "$LLVM_DIR" fetch origin "$commit" 2>/dev/null; then
    warn "  → Failed to fetch $commit — remote may not support partial fetch"
    ((FAILED++)) || true
    continue
  fi

  # Generate subject line for filename
  local subject
  subject=$(git -C "$LLVM_DIR" log -1 --format=%s "$commit" 2>/dev/null | \
    sed 's/[^a-zA-Z0-9._-]/_/g' | cut -c1-60)

  local num
  num=$(next_number)
  local patch_file="$PATCHES_DIR/$(printf '%04d' "$num")-${commit:0:7}-${subject:0:50}.patch"

  if git -C "$LLVM_DIR" format-patch -1 "$commit" -o "$PATCHES_DIR" 2>/dev/null; then
    # Rename the generated file to our format
    local gen_file
    gen_file=$(ls -t "$PATCHES_DIR"/*.patch 2>/dev/null | head -1)
    if [[ -n "$gen_file" && "$gen_file" != "$patch_file" ]]; then
      mv "$gen_file" "$patch_file"
    fi
    log "  → Created: $(basename "$patch_file")"
    ((APPLIED++)) || true
  else
    warn "  → Failed to create patch for $commit"
    ((FAILED++)) || true
  fi
done < "$CONFIG_FILE"

# ─── Summary ──────────────────────────────────────────────────────────────
echo ""
log "Summary: $APPLIED applied, $SKIPPED skipped, $FAILED failed"

# Output for GitHub Actions
echo "applied=$APPLIED" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "skipped=$SKIPPED" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "failed=$FAILED" >> "${GITHUB_OUTPUT:-/dev/null}"
