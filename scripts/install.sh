#!/usr/bin/env bash
# CyreneClang — One-liner Installer
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/cyrene_clang/main/scripts/install.sh)
set -euo pipefail

DIR="${CYRENE_DIR:-$(pwd)}"
CLANG_DIR="$DIR/cyrene-clang"
REPO="naidrahiqa/cyrene_clang"

echo "========================================"
echo " CyreneClang Installer"
echo "========================================"
echo "Working directory : $DIR"
echo "Install directory : $CLANG_DIR"
echo ""

# Step 1: Fetch latest release info
echo "[1/5] Fetching latest release info ..."
LATEST_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" | \
  grep -oP '"browser_download_url":\s*"\K[^"]+\.tar\.zst' | head -1)

if [[ -z "$LATEST_URL" ]]; then
  echo "✗ Failed to fetch latest release"
  exit 1
fi
echo "✓ Latest: $(basename "$LATEST_URL")"
echo ""

# Step 2: Create directory
echo "[2/5] Creating directory ..."
mkdir -p "$CLANG_DIR"
echo "✓ Directory ready"
echo ""

# Step 3: Download & extract
echo "[3/5] Downloading CyreneClang ..."
if wget -O - "$LATEST_URL" | tar -I zstd -xf - -C "$CLANG_DIR" --strip-components=1; then
  echo "✓ Download & extraction complete"
else
  echo "✗ Download or extraction failed"
  exit 1
fi
echo ""

# Step 4: Fix ld symlink
echo "[4/5] Fixing ld symlink ..."
if [[ -f "$CLANG_DIR/bin/ld.lld" && ! -e "$CLANG_DIR/bin/ld" ]]; then
  ln -sf ld.lld "$CLANG_DIR/bin/ld"
  echo "✓ ld → ld.lld symlink created"
else
  echo "✓ ld symlink already exists or ld.lld not found"
fi
echo ""

# Step 5: Verify installation
echo "[5/5] Verifying installation ..."
if [[ -e "$CLANG_DIR/bin/clang" ]]; then
  echo "✓ Clang found"
  CLANG_VERSION=$("$CLANG_DIR/bin/clang" --version | head -n 1)
  echo "  Version: $CLANG_VERSION"
else
  echo "✗ Error: Clang binary not found!"
  exit 1
fi

echo ""
echo "========================================"
echo " Installation complete!"
echo "========================================"
echo ""
echo "Add to your PATH:"
echo "  export PATH=\"$CLANG_DIR/bin:\$PATH\""
echo ""
echo "Or add to ~/.bashrc / ~/.zshrc for persistence:"
echo "  echo 'export PATH=\"$CLANG_DIR/bin:\$PATH\"' >> ~/.bashrc"
echo "========================================"
