#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRODUCT_NAME="adiga"
OUTPUT_DIR="${1:-$REPO_ROOT/dist}"

mkdir -p "$OUTPUT_DIR"

cd "$REPO_ROOT"

echo "Building $PRODUCT_NAME in release mode..."
swift build -c release --product "$PRODUCT_NAME"

BIN_DIR="$(swift build -c release --show-bin-path)"
SOURCE_BINARY="$BIN_DIR/$PRODUCT_NAME"
TARGET_BINARY="$OUTPUT_DIR/$PRODUCT_NAME"

if [[ ! -f "$SOURCE_BINARY" ]]; then
    echo "Expected binary not found at $SOURCE_BINARY" >&2
    exit 1
fi

cp "$SOURCE_BINARY" "$TARGET_BINARY"
chmod +x "$TARGET_BINARY"

echo "Binary created at: $TARGET_BINARY"