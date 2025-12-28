#!/bin/bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 <image>"
    echo "Example: $0 docker://ghcr.io/iitzrohan/atomic:bazzite"
    exit 1
fi

inspect_output=$(skopeo inspect "$1")

# Function to convert bytes to human readable
human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.2f GB" "$(echo "scale=2; $bytes / 1073741824" | bc)"
    else
        printf "%.2f MB" "$(echo "scale=2; $bytes / 1048576" | bc)"
    fi
}

# Extract ALL layer data
all_layer_data=$(echo "$inspect_output" | jq -r '.LayersData[] | "\(.Digest)\t\(.Size)\t\(.Annotations["ostree.components"] // "")"')

# Extract package layer data (layers with packages)
pkg_layer_data=$(echo "$inspect_output" | jq -r '.LayersData[] | select(.Annotations["ostree.components"] != null and .Annotations["ostree.components"] != "") | "\(.Digest)\t\(.Size)\t\(.Annotations["ostree.components"])"')

# Calculate totals for ALL layers
all_layers=0
all_size=0

while IFS=$'\t' read -r digest size components; do
    [[ -z "$digest" ]] && continue
    ((all_layers++))
    ((all_size += size))
done <<< "$all_layer_data"

# Calculate totals for package layers
pkg_layers=0
total_packages=0
pkg_size=0

while IFS=$'\t' read -r digest size components; do
    [[ -z "$digest" ]] && continue
    ((pkg_layers++))
    pkg_count=$(echo "$components" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -c -v '^$')
    ((total_packages += pkg_count))
    ((pkg_size += size))
done <<< "$pkg_layer_data"

# Calculate non-package layers
other_layers=$((all_layers - pkg_layers))
other_size=$((all_size - pkg_size))

# Print summary
echo "=== Summary ==="
echo "Total layers:     $all_layers (package: $pkg_layers, other: $other_layers)"
echo "Total packages:   $total_packages"
echo "Total size:       $(human_size $all_size)"
echo "  Package layers: $(human_size $pkg_size)"
echo "  Other layers:   $(human_size $other_size)"
echo ""

# Show non-package layers
if [[ $other_layers -gt 0 ]]; then
    echo "--- Non-package layers ---"
    echo ""
    while IFS=$'\t' read -r digest size components; do
        [[ -z "$digest" ]] && continue
        [[ -n "$components" ]] && continue  # Skip if has packages
        human=$(human_size "$size")
        short_digest="${digest#sha256:}"
        short_digest="${short_digest:0:12}"
        echo "[$short_digest] ($human)"
    done <<< "$all_layer_data"
    echo ""
fi

echo "--- Packages grouped by layer ---"
echo ""

# Process each layer and group packages
while IFS=$'\t' read -r digest size components; do
    [[ -z "$digest" ]] && continue
    human=$(human_size "$size")

    # Shorten digest for display (sha256:abc123... -> abc123...)
    short_digest="${digest#sha256:}"
    short_digest="${short_digest:0:12}"

    # Count packages in this layer
    pkg_count=$(echo "$components" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -c -v '^$')

    echo "[$short_digest] ($human) - $pkg_count package(s):"

    # Split components by comma and print each indented
    echo "$components" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | sort | while read -r pkg; do
        echo "  - $pkg"
    done
    echo ""
done <<< "$pkg_layer_data"

echo ""
echo "--- Packages from label (with versions) ---"
echo ""

# Also show packages from the rechunk label with versions
echo "$inspect_output" | \
    jq -r '.Labels["dev.hhd.rechunk.info"] // empty' | \
    jq -r '.packages // {} | to_entries[] | "\(.key)\t\(.value)"' 2>/dev/null | \
    sort | \
    while IFS=$'\t' read -r name version; do
        printf "%-50s  %s\n" "$name" "$version"
    done
