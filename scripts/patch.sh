#!/usr/bin/env bash
# CyreneClang — Patch Application Script
# Applies all patches from patches/ directory to the LLVM source tree.
set -euo pipefail

LLVM_DIR="${1:-$(pwd)/llvm-project}"
PATCHES_DIR="$(cd "$(dirname "$(dirname "$0")")" && pwd)/patches"

log() { echo -e "\033[1;33m[Patches]\033[0m $*"; }

if [[ ! -d "$PATCHES_DIR" ]]; then
  log "No patches/ directory found, skipping."
  exit 0
fi

patch_files=("$PATCHES_DIR"/*.patch)
if [[ ! -e "${patch_files[0]}" ]]; then
  log "No .patch files found in patches/, skipping."
  exit 0
fi

log "Applying patches to $LLVM_DIR ..."
for patch in "$PATCHES_DIR"/*.patch; do
  log "  → $(basename "$patch")"
  git -C "$LLVM_DIR" apply --check "$patch" \
    || { echo "Patch check failed: $patch" >&2; exit 1; }
  git -C "$LLVM_DIR" apply "$patch"
done

log "All patches applied successfully."