#!/bin/bash
# Helper script to find SL-Micro images in common locations

echo "Searching for SL-Micro images..."
echo ""

# Search locations
SEARCH_PATHS=(
    "$HOME/Downloads"
    "$HOME/Desktop"
    "$HOME/Documents"
    "$(pwd)/images"
    "$(pwd)/../images"
)

FOUND_IMAGES=()

for path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$path" ]; then
        # Find .raw.xz files
        while IFS= read -r -d '' file; do
            FOUND_IMAGES+=("$file")
        done < <(find "$path" -name "SL-Micro*.raw.xz" -type f -print0 2>/dev/null)
        
        # Find .raw files
        while IFS= read -r -d '' file; do
            FOUND_IMAGES+=("$file")
        done < <(find "$path" -name "SL-Micro*.raw" -type f -print0 2>/dev/null)
        
        # Find .iso files
        while IFS= read -r -d '' file; do
            FOUND_IMAGES+=("$file")
        done < <(find "$path" -name "SL-Micro*.iso" -type f -print0 2>/dev/null)
    fi
done

if [ ${#FOUND_IMAGES[@]} -eq 0 ]; then
    echo "No SL-Micro images found in common locations."
    echo ""
    echo "Searched in:"
    for path in "${SEARCH_PATHS[@]}"; do
        echo "  - $path"
    done
    echo ""
    echo "Please download SL-Micro images from:"
    echo "  - SUSE Customer Center: https://scc.suse.com"
    echo "  - SUSE Download page: https://download.suse.com"
    exit 1
fi

echo "Found ${#FOUND_IMAGES[@]} image(s):"
echo ""
for i in "${!FOUND_IMAGES[@]}"; do
    file="${FOUND_IMAGES[$i]}"
    size=$(ls -lh "$file" | awk '{print $5}')
    echo "  [$((i+1))] $file ($size)"
done

echo ""
echo "For VM usage: Use .raw or .raw.xz files"
echo "For EIB: Use .iso files (Base ISO image)"


