#!/bin/bash
# Download JanusVLN_Extra weight files with resume support
# Usage: bash scripts/download_weights.sh
# Supports resume (-c flag) if download is interrupted

set -e
cd "$(dirname "$0")/.."

MODEL_DIR="models/JanusVLN_Extra"
BASE_URL="https://modelscope.cn/models/misstl/JanusVLN_Extra/resolve/master"

FILES=(
    "model-00001-of-00004.safetensors"
    "model-00002-of-00004.safetensors"
    "model-00003-of-00004.safetensors"
    "model-00004-of-00004.safetensors"
)

mkdir -p "$MODEL_DIR"

for f in "${FILES[@]}"; do
    TARGET="$MODEL_DIR/$f"
    if [ -f "$TARGET" ]; then
        echo "[SKIP] $f already exists ($(du -h "$TARGET" | cut -f1))"
        continue
    fi
    echo "[DOWN] Downloading $f ..."
    wget -c --progress=bar:force:noscroll -O "$TARGET" "${BASE_URL}/${f}"
    echo "[DONE] $f"
done

echo ""
echo "=== Weight files ==="
ls -lh "$MODEL_DIR"/model-*.safetensors 2>/dev/null || echo "No weight files found!"
echo ""
echo "Total: $(du -sh "$MODEL_DIR" | cut -f1)"
