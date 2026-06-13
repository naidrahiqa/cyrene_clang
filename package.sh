#!/usr/bin/env bash
# CyreneClang — Package + Manifest Generator
# Compresses the toolchain and generates clang-version.txt manifest.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/toolchains/cyrene}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"
REPO="${GITHUB_REPOSITORY:-owner/cyrene-clang}"
TAG="${RELEASE_TAG:-$(date +%Y%m%d)}"
ENABLE_PGO="${ENABLE_PGO:-true}"

log() { echo -e "\033[1;35m[Package]\033[0m $*"; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

[[ -d "$INSTALL_DIR" ]] || die "Toolchain not found at $INSTALL_DIR"

mkdir -p "$OUTPUT_DIR"

TARBALL="$OUTPUT_DIR/cyrene-clang-$TAG.tar.zst"

# ─── Get build metadata ───────────────────────────────────────────────────────
CLANG_BIN="$INSTALL_DIR/bin/clang"
[[ -x "$CLANG_BIN" ]] || die "clang binary not found at $CLANG_BIN"

CLANG_VERSION=$("$CLANG_BIN" --version | head -1 | grep -oP '\d+\.\d+\.\d+\S*' | head -1)
LLVM_COMMIT=$(git -C "${LLVM_DIR:-$(pwd)/llvm-project}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +%Y-%m-%d)
LTO_MODE="Thin"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/cyrene-clang-$TAG.tar.zst"

# ─── Compress toolchain ───────────────────────────────────────────────────────
log "Compressing toolchain → $(basename "$TARBALL") ..."
tar \
  --use-compress-program="zstd -19 -T0" \
  -cf "$TARBALL" \
  -C "$(dirname "$INSTALL_DIR")" \
  "$(basename "$INSTALL_DIR")"

TARBALL_SIZE=$(du -sh "$TARBALL" | cut -f1)
log "Compressed size: $TARBALL_SIZE"

# ─── Generate clang-version.txt ───────────────────────────────────────────────
MANIFEST="$OUTPUT_DIR/clang-version.txt"
cat > "$MANIFEST" << EOF
CLANG_VERSION=$CLANG_VERSION
LLVM_COMMIT=$LLVM_COMMIT
BUILD_DATE=$BUILD_DATE
BUILD_HOST=GitHub Actions
PGO=$ENABLE_PGO
LTO=$LTO_MODE
TARGETS=AArch64;ARM;X86
TARBALL_SIZE=$TARBALL_SIZE
DOWNLOAD_URL=$DOWNLOAD_URL
EOF

log "Manifest written to $MANIFEST"
cat "$MANIFEST"

# Copy manifest to repo root (committed for easy wget access)
cp "$MANIFEST" "$(dirname "$(dirname "$0")")/clang-version.txt"

log "Packaging complete."
echo "TARBALL=$TARBALL" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "RELEASE_TAG=$TAG" >> "${GITHUB_OUTPUT:-/dev/null}"