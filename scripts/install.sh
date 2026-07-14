#!/usr/bin/env bash
# MasterFabric Mac CLI — one-line installer
# Usage: curl -fsSL https://raw.githubusercontent.com/gurkanfikretgunak/masterfabric-mac-cli/main/scripts/install.sh | bash
set -euo pipefail

REPO="https://github.com/gurkanfikretgunak/masterfabric-mac-cli.git"
PREFIX="${MASTERFABRIC_PREFIX:-$HOME/.local}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v swift >/dev/null 2>&1; then
  echo "error: Swift toolchain required (Xcode or Command Line Tools)." >&2
  exit 1
fi

echo "==> Cloning gurkanfikretgunak/masterfabric-mac-cli"
git clone --depth 1 "$REPO" "$TMP/masterfabric-mac-cli"
cd "$TMP/masterfabric-mac-cli"

echo "==> Building release"
make install PREFIX="$PREFIX"

BIN_DIR="$PREFIX/bin"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo ""
    echo "Add to your shell profile:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

echo ""
echo "Done. Try:"
echo "  mf status"
echo "  mf menubar"
echo "  mf mcp"
echo ""
echo "MCP (Cursor ~/.cursor/mcp.json):"
echo "  \"masterfabric\": { \"command\": \"$BIN_DIR/mf\", \"args\": [\"mcp\"] }"
