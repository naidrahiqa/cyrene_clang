#!/usr/bin/env bash
# CyreneClang — One-liner Installer
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/naidrahiqa/cyrene_clang/main/get_clang.sh)
set -euo pipefail

REPO="naidrahiqa/cyrene_clang"
INSTALL_DIR="${CYRENE_DIR:-$HOME/toolchains/cyrene}"

echo "========================================"
echo " CyreneClang Installer"
echo "========================================"
echo "Install directory: $INSTALL_DIR"
echo ""

# Step 1: Fetch latest release
echo "[1/4] Fetching latest release ..."
LATEST_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" | \
  grep -oP '"browser_download_url":\s*"\K[^"]+\.tar\.zst' | head -1)

if [[ -z "$LATEST_URL" ]]; then
  echo "ERROR: Failed to fetch latest release"
  exit 1
fi
echo "  Latest: $(basename "$LATEST_URL")"

# Step 2: Download & extract
echo "[2/4] Downloading and extracting ..."
mkdir -p "$INSTALL_DIR"
if wget -qO- "$LATEST_URL" | tar -I zstd -xf - -C "$INSTALL_DIR" --strip-components=1; then
  echo "  Done."
else
  echo "ERROR: Download or extraction failed"
  exit 1
fi

# Step 3: Fix ld symlink
echo "[3/4] Fixing ld symlink ..."
if [[ -f "$INSTALL_DIR/bin/ld.lld" && ! -e "$INSTALL_DIR/bin/ld" ]]; then
  ln -sf ld.lld "$INSTALL_DIR/bin/ld"
  echo "  ld -> ld.lld symlink created"
fi

# Step 4: Verify
echo "[4/4] Verifying installation ..."
if [[ -e "$INSTALL_DIR/bin/clang" ]]; then
  VERSION=$("$INSTALL_DIR/bin/clang" --version | head -1)
  echo "  OK: $VERSION"
else
  echo "ERROR: clang not found"
  exit 1
fi

echo ""
echo "========================================"
echo " Installation complete!"
echo "========================================"
echo ""
echo "Add to your shell profile:"
echo "  export PATH=\"$INSTALL_DIR/bin:\$PATH\""
echo ""
echo "Or run directly:"
echo "  $INSTALL_DIR/bin/clang --version"
echo "========================================"
