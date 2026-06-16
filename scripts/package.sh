#!/usr/bin/env bash
# CyreneClang — Package + Manifest Generator
# Compresses the toolchain and generates clang-version.txt + clang_notes.txt.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/toolchains/cyrene}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"
LLVM_DIR="${LLVM_DIR:-$(pwd)/llvm-project}"
REPO="${GITHUB_REPOSITORY:-owner/cyrene-clang}"
TAG="${RELEASE_TAG:-$(date +%Y%m%d)}"
ENABLE_PGO="${ENABLE_PGO:-true}"
ENABLE_BOLT="${ENABLE_BOLT:-true}"

log() { echo -e "\033[1;35m[Package]\033[0m $*"; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

[[ -d "$INSTALL_DIR" ]] || die "Toolchain not found at $INSTALL_DIR"
mkdir -p "$OUTPUT_DIR"

TARBALL="$OUTPUT_DIR/cyrene-clang-$TAG.tar.zst"

# ─── Get build metadata ───────────────────────────────────────────────────────
CLANG_BIN="$INSTALL_DIR/bin/clang"
[[ -x "$CLANG_BIN" ]] || die "clang binary not found at $CLANG_BIN"

CLANG_VERSION=$("$CLANG_BIN" --version | head -1 | grep -oP '\d+\.\d+\.\d+\S*' | head -1)
LLVM_COMMIT=$(git -C "$LLVM_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
LLVM_COMMIT_FULL=$(git -C "$LLVM_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +%Y-%m-%d)
LTO_MODE="Thin"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/cyrene-clang-$TAG.tar.zst"

# ─── Fix ld symlink (common issue with cross-env) ─────────────────────────────
log "Creating ld → ld.lld symlink ..."
if [[ -f "$INSTALL_DIR/bin/ld.lld" && ! -e "$INSTALL_DIR/bin/ld" ]]; then
  ln -sf ld.lld "$INSTALL_DIR/bin/ld"
  log "  ✓ ld → ld.lld symlink created"
fi

# ─── Compress toolchain ───────────────────────────────────────────────────────
log "Compressing toolchain → $(basename "$TARBALL") ..."
tar \
  --use-compress-program="zstd -19 -T0" \
  -cf "$TARBALL" \
  -C "$(dirname "$INSTALL_DIR")" \
  "$(basename "$INSTALL_DIR")"

TARBALL_SIZE=$(du -sh "$TARBALL" | cut -f1)
log "Compressed size: $TARBALL_SIZE"

# ─── SHA256 checksum ─────────────────────────────────────────────────────────
SHA256=$(sha256sum "$TARBALL" | cut -d' ' -f1)
log "SHA256: $SHA256"

# ─── Generate clang-version.txt ───────────────────────────────────────────────
MANIFEST="$OUTPUT_DIR/clang-version.txt"
cat > "$MANIFEST" << EOF
CLANG_VERSION=$CLANG_VERSION
LLVM_COMMIT=$LLVM_COMMIT
BUILD_DATE=$BUILD_DATE
BUILD_HOST=GitHub Actions
PGO=$ENABLE_PGO
BOLT=$ENABLE_BOLT
LTO=$LTO_MODE
TARGETS=AArch64;ARM;X86
TARBALL_SIZE=$TARBALL_SIZE
SHA256=$SHA256
DOWNLOAD_URL=$DOWNLOAD_URL
EOF

log "Manifest written to $MANIFEST"
cat "$MANIFEST"

# ─── Generate clang_notes.txt (structured metadata) ───────────────────────────
NOTES="$OUTPUT_DIR/clang_notes.txt"
cat > "$NOTES" << EOF
[date]
$BUILD_DATE

[clang-ver]
CyreneClang $CLANG_VERSION (https://github.com/llvm/llvm-project $LLVM_COMMIT_FULL)

[lld-ver]
LLD $CLANG_VERSION (https://github.com/llvm/llvm-project $LLVM_COMMIT_FULL) (compatible with GNU linkers)

[llvm-commit]
https://github.com/llvm/llvm-project/commit/$LLVM_COMMIT_FULL

[host-glibc]
$(ldd --version 2>&1 | head -1 | grep -oP '\d+\.\d+' | head -1 || echo "unknown")

[size]
$TARBALL_SIZE

[pgo]
$ENABLE_PGO

[bolt]
$ENABLE_BOLT

[lto]
$LTO_MODE

[link-rel]
$DOWNLOAD_URL

[shasum]
$SHA256
EOF

log "Notes written to $NOTES"

# Copy manifest to repo root (committed for easy wget access)
cp "$MANIFEST" "$(dirname "$(dirname "$0")")/clang-version.txt"

log "Packaging complete."
echo "TARBALL=$TARBALL" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "RELEASE_TAG=$TAG" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "CLANG_VERSION=$CLANG_VERSION" >> "${GITHUB_OUTPUT:-/dev/null}"
