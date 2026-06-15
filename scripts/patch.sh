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

# ─── Fallback fixups for known patches ───────────────────────────────────────
# When git apply fails due to context drift (e.g. shallow clones, upstream
# churn), apply targeted sed fixups so the build never breaks on a patch
# that we know is correct but doesn't apply cleanly.
apply_nsan_gcc14_fallback() {
  local nsan_h="$LLVM_DIR/compiler-rt/lib/nsan/nsan.h"
  if [[ ! -f "$nsan_h" ]]; then
    return 1
  fi
  # Already applied?
  if grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_h"; then
    return 0
  fi
  # Insert the define right before the sanitizer include
  if sed -i '/#include "sanitizer_common\/sanitizer_internal_defs.h"/i#define SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_h"; then
    if grep -q 'SANITIZER_COMMON_REDEFINE_BUILTINS_IN_STD' "$nsan_h"; then
      log "    ✓ nsan GCC-14 fix applied via fallback sed"
      return 0
    fi
  fi
  return 1
}

# ─── Main patch loop ────────────────────────────────────────────────────────
for patch in "$PATCHES_DIR"/*.patch; do
  patch_name="$(basename "$patch")"
  log "  → $patch_name"

  # Attempt 1: clean apply
  if git -C "$LLVM_DIR" apply --check "$patch" 2>/dev/null; then
    git -C "$LLVM_DIR" apply "$patch"
    continue
  fi

  # Attempt 2: fuzzy / 3-way merge
  log "    ⚠ clean apply failed, trying --3way ..."
  if git -C "$LLVM_DIR" apply --3way "$patch" 2>/dev/null; then
    log "    ✓ applied with --3way"
    continue
  fi

  # Attempt 3: known fallback fixups
  log "    ⚠ --3way failed, trying built-in fallback ..."
  if [[ "$patch_name" == *"nsan"*"gcc"* || "$patch_name" == *"nsan"*"compat"* ]]; then
    if apply_nsan_gcc14_fallback; then
      continue
    fi
  fi

  echo "ERROR: Failed to apply patch: $patch" >&2
  exit 1
done

log "All patches applied successfully."