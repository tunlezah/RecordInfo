#!/bin/bash
# generate-icons.sh
# Generates all required macOS app icon sizes from the source logo PNG.
# Requires: sips (built into macOS)

set -euo pipefail

SOURCE="${1:-Vibrant vinyl ear logo design.png}"
OUTPUT_DIR="RecordInfo/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE" ]; then
    echo "Error: Source image not found: $SOURCE"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Required sizes for macOS app icons
SIZES=(16 32 64 128 256 512 1024)

for size in "${SIZES[@]}"; do
    output="$OUTPUT_DIR/icon_${size}.png"
    echo "Generating ${size}x${size} -> $output"
    sips -z "$size" "$size" "$SOURCE" --out "$output" > /dev/null 2>&1
done

echo "All icon sizes generated successfully."
