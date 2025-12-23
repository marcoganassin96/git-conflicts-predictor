#!/bin/bash
set -eu

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
TMP_DIR="$RELEASE_DIR/git-conflicts-predictor-win"
VERSION="0.0.0"

usage(){
  echo "Usage: $0 <version>"
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi
VERSION="$1"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Copy necessary files and directories
cp -r "$ROOT_DIR/bin" "$TMP_DIR/"
cp -r "$ROOT_DIR/lib" "$TMP_DIR/"
cp "$ROOT_DIR/conflicts_relevator.cmd" "$TMP_DIR/"
cp "$ROOT_DIR/conflicts_relevator.ps1" "$TMP_DIR/"
cp "$ROOT_DIR/README_windows.md" "$TMP_DIR/"

# Optional: include license and README
if [ -f "$ROOT_DIR/README.md" ]; then
  cp "$ROOT_DIR/README.md" "$TMP_DIR/"
fi
if [ -f "$ROOT_DIR/LICENSE" ]; then
  cp "$ROOT_DIR/LICENSE" "$TMP_DIR/"
fi

# Create zip
mkdir -p "$RELEASE_DIR"
pushd "$RELEASE_DIR" >/dev/null
zip -r "git-conflicts-predictor-${VERSION}-win.zip" "git-conflicts-predictor-win" >/dev/null
popd >/dev/null

# Clean up
rm -rf "$TMP_DIR"

echo "Created $RELEASE_DIR/git-conflicts-predictor-${VERSION}-win.zip"
