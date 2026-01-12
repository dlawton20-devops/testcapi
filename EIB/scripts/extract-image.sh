#!/bin/bash
# Extract SL-Micro raw image from xz archive

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$PROJECT_ROOT/images"
DOWNLOADS_DIR="$HOME/Downloads"

# Create images directory if it doesn't exist
mkdir -p "$IMAGES_DIR"

# Find the image file
IMAGE_XZ=$(find "$DOWNLOADS_DIR" -name "SL-Micro*.raw.xz" -type f 2>/dev/null | head -1)

if [ -z "$IMAGE_XZ" ]; then
    echo "Error: Could not find SL-Micro*.raw.xz in $DOWNLOADS_DIR"
    echo "Please specify the path to your image file:"
    read -r IMAGE_XZ
fi

if [ ! -f "$IMAGE_XZ" ]; then
    echo "Error: File not found: $IMAGE_XZ"
    exit 1
fi

# Extract filename without extension
IMAGE_NAME=$(basename "$IMAGE_XZ" .xz)
OUTPUT_IMAGE="$IMAGES_DIR/$IMAGE_NAME"

echo "Extracting $IMAGE_XZ..."
echo "Output: $OUTPUT_IMAGE"

# Check if already extracted
if [ -f "$OUTPUT_IMAGE" ]; then
    echo "Warning: $OUTPUT_IMAGE already exists."
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping extraction."
        exit 0
    fi
    rm -f "$OUTPUT_IMAGE"
fi

# Extract using xz
xz -dc "$IMAGE_XZ" > "$OUTPUT_IMAGE"

# Check extraction
if [ -f "$OUTPUT_IMAGE" ]; then
    echo "✓ Successfully extracted to $OUTPUT_IMAGE"
    ls -lh "$OUTPUT_IMAGE"
else
    echo "✗ Extraction failed"
    exit 1
fi


