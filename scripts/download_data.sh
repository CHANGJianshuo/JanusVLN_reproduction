#!/bin/bash
# Download datasets and pretrained model for JanusVLN evaluation
# Usage: bash scripts/download_data.sh [--model-only | --data-only | --all]
#
# Prerequisites:
#   - pip install gdown modelscope
#   - MP3D scene data must be downloaded manually (requires signed agreement)
#     See: https://niessner.github.io/Matterport/

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

MODE="${1:---all}"

download_model() {
    echo "============================================"
    echo "  Downloading JanusVLN_Extra pretrained model"
    echo "============================================"

    if [ -d "models/JanusVLN_Extra" ] && [ "$(ls -A models/JanusVLN_Extra 2>/dev/null)" ]; then
        echo "[SKIP] models/JanusVLN_Extra already exists"
        return
    fi

    pip install -q modelscope 2>/dev/null || true
    echo "[INFO] Downloading from ModelScope: misstl/JanusVLN_Extra"
    python -c "
from modelscope import snapshot_download
snapshot_download('misstl/JanusVLN_Extra', local_dir='models/JanusVLN_Extra')
print('[DONE] Model downloaded to models/JanusVLN_Extra')
"
}

download_r2r_episodes() {
    echo "============================================"
    echo "  Downloading R2R VLN-CE episodes"
    echo "============================================"

    if [ -d "data/datasets/r2r" ] && [ "$(ls -A data/datasets/r2r 2>/dev/null)" ]; then
        echo "[SKIP] data/datasets/r2r already has content"
        return
    fi

    pip install -q gdown 2>/dev/null || true
    echo "[INFO] Downloading R2R episodes from Google Drive..."
    # Google Drive file ID from README: 1fo8F4NKgZDH-bPSdVU3cONAkt5EW-tyr
    gdown --id 1fo8F4NKgZDH-bPSdVU3cONAkt5EW-tyr -O /tmp/r2r_episodes.zip
    echo "[INFO] Extracting to data/datasets/r2r/..."
    unzip -q /tmp/r2r_episodes.zip -d data/datasets/r2r/
    rm -f /tmp/r2r_episodes.zip
    echo "[DONE] R2R episodes ready"
}

check_mp3d() {
    echo "============================================"
    echo "  Checking MP3D scene data"
    echo "============================================"

    if [ -d "data/scene_datasets/mp3d" ] && [ "$(ls data/scene_datasets/mp3d/ 2>/dev/null | head -1)" ]; then
        echo "[OK] MP3D data found at data/scene_datasets/mp3d/"
        echo "     Contents:"
        ls data/scene_datasets/mp3d/ | head -10
    else
        echo "[MISSING] MP3D scene data not found!"
        echo ""
        echo "  MP3D requires a signed academic agreement. Please:"
        echo "  1. Visit https://niessner.github.io/Matterport/"
        echo "  2. Sign the Terms of Use"
        echo "  3. Download the scene meshes"
        echo "  4. Place them in: data/scene_datasets/mp3d/"
        echo ""
        echo "  Expected structure:"
        echo "    data/scene_datasets/mp3d/"
        echo "      1LXtFkjw3qL/"
        echo "        1LXtFkjw3qL.glb"
        echo "        1LXtFkjw3qL.navmesh"
        echo "      ..."
        echo ""
        echo "  Alternatively, use the official download script:"
        echo "    python -m habitat_sim.utils.datasets_download --uids mp3d_example_scene"
        return 1
    fi
}

case "$MODE" in
    --model-only)
        download_model
        ;;
    --data-only)
        download_r2r_episodes
        check_mp3d
        ;;
    --all)
        download_model
        download_r2r_episodes
        check_mp3d
        ;;
    *)
        echo "Usage: bash scripts/download_data.sh [--model-only | --data-only | --all]"
        exit 1
        ;;
esac

echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
echo "  Model:      $([ -d models/JanusVLN_Extra ] && echo 'Ready' || echo 'Not downloaded')"
echo "  R2R data:   $([ -f data/datasets/r2r/val_unseen/val_unseen.json.gz ] && echo 'Ready' || echo 'Check data/datasets/r2r/')"
echo "  MP3D scene: $([ -d data/scene_datasets/mp3d ] && [ "$(ls data/scene_datasets/mp3d/ 2>/dev/null | head -1)" ] && echo 'Ready' || echo 'MISSING - manual download required')"
echo "============================================"
