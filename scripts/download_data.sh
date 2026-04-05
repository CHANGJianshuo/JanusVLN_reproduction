#!/bin/bash
# Download datasets and pretrained model for JanusVLN evaluation
# Usage: bash scripts/download_data.sh [--model-only | --data-only | --all]
#
# This script downloads ONLY what's needed for inference/evaluation:
#   - JanusVLN_Extra pretrained weights (~15GB)
#   - R2R VLN-CE val_unseen episodes (~small)
#   - MP3D scenes: only the 11 scenes used in val_unseen (~2GB vs 15GB full)
#
# NOT downloaded (training only):
#   - Trajectory data (~50GB+)
#   - ScaleVLN / HM3D data (~100GB+)
#   - R2R/RxR training episodes
#
# Prerequisites:
#   - pip install gdown modelscope
#   - MP3D scene data requires signed agreement: https://niessner.github.io/Matterport/

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
    echo "[INFO] Downloading from ModelScope: misstl/JanusVLN_Extra (~15GB)"
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

extract_val_unseen_scenes() {
    echo "============================================"
    echo "  Extracting val_unseen scene IDs"
    echo "============================================"

    # Parse the val_unseen.json.gz to find which MP3D scenes are needed
    python3 -c "
import gzip, json, os

# Try multiple possible paths for the episodes file
candidates = [
    'data/datasets/r2r/val_unseen/val_unseen.json.gz',
    'data/datasets/r2r/val_unseen.json.gz',
]

data = None
for path in candidates:
    if os.path.exists(path):
        with gzip.open(path, 'rt') as f:
            data = json.load(f)
        print(f'[INFO] Loaded episodes from {path}')
        break

# Also try finding any .json.gz under data/datasets/r2r/
if data is None:
    import glob
    for path in glob.glob('data/datasets/r2r/**/*val_unseen*.json.gz', recursive=True):
        with gzip.open(path, 'rt') as f:
            data = json.load(f)
        print(f'[INFO] Loaded episodes from {path}')
        break

if data is None:
    print('[ERROR] Cannot find val_unseen episodes file.')
    print('        Please download R2R episodes first: bash scripts/download_data.sh --data-only')
    exit(1)

episodes = data.get('episodes', data) if isinstance(data, dict) else data
scenes = set()
for ep in episodes:
    scene_path = ep.get('scene_id', '')
    # scene_id format: 'data/scene_datasets/mp3d/{SCENE_ID}/{SCENE_ID}.glb'
    parts = scene_path.split('/')
    for i, p in enumerate(parts):
        if p == 'mp3d' and i + 1 < len(parts):
            scenes.add(parts[i + 1])
            break

print(f'[INFO] val_unseen uses {len(scenes)} MP3D scenes:')
for s in sorted(scenes):
    print(f'  - {s}')

# Save scene list for reference
with open('data/val_unseen_scenes.txt', 'w') as f:
    for s in sorted(scenes):
        f.write(s + '\n')
print(f'[DONE] Scene list saved to data/val_unseen_scenes.txt')
"
}

check_mp3d() {
    echo "============================================"
    echo "  Checking MP3D scene data"
    echo "============================================"

    SCENE_LIST="data/val_unseen_scenes.txt"

    if [ ! -f "$SCENE_LIST" ]; then
        echo "[WARN] Scene list not found. Run with --data-only first to extract scene IDs."
        echo "       Falling back to full MP3D check..."

        if [ -d "data/scene_datasets/mp3d" ] && [ "$(ls data/scene_datasets/mp3d/ 2>/dev/null | head -1)" ]; then
            echo "[OK] MP3D data found at data/scene_datasets/mp3d/"
            ls data/scene_datasets/mp3d/ | head -15
        else
            print_mp3d_instructions
        fi
        return
    fi

    echo "[INFO] Checking only val_unseen scenes ($(wc -l < "$SCENE_LIST") scenes needed):"
    MISSING=0
    FOUND=0
    while IFS= read -r scene; do
        GLB="data/scene_datasets/mp3d/${scene}/${scene}.glb"
        NAV="data/scene_datasets/mp3d/${scene}/${scene}.navmesh"
        if [ -f "$GLB" ] && [ -f "$NAV" ]; then
            echo "  [OK]      $scene"
            FOUND=$((FOUND + 1))
        elif [ -f "$GLB" ]; then
            echo "  [PARTIAL] $scene  (missing .navmesh)"
            MISSING=$((MISSING + 1))
        else
            echo "  [MISSING] $scene"
            MISSING=$((MISSING + 1))
        fi
    done < "$SCENE_LIST"

    echo ""
    echo "  Found: $FOUND / $(wc -l < "$SCENE_LIST")"
    if [ "$MISSING" -gt 0 ]; then
        echo ""
        print_mp3d_instructions
    else
        echo "  [OK] All val_unseen scenes are present!"
    fi
}

print_mp3d_instructions() {
    echo "  ================================================"
    echo "  HOW TO DOWNLOAD MP3D SCENES (val_unseen only)"
    echo "  ================================================"
    echo ""
    echo "  MP3D requires a signed academic agreement:"
    echo "    1. Visit https://niessner.github.io/Matterport/"
    echo "    2. Sign the Terms of Use to get download access"
    echo "    3. You will receive a download script (download_mp.py)"
    echo ""
    echo "  To download ONLY val_unseen scenes (~2GB instead of ~15GB):"
    echo "    python2 download_mp.py --task habitat -o data/scene_datasets/mp3d/ \\"
    echo "      -id <scene_id>    # repeat for each scene in data/val_unseen_scenes.txt"
    echo ""
    echo "  Or use this loop:"
    echo "    while read scene; do"
    echo "      python2 download_mp.py --task habitat -o data/scene_datasets/mp3d/ -id \$scene"
    echo "    done < data/val_unseen_scenes.txt"
    echo ""
    echo "  Expected structure per scene:"
    echo "    data/scene_datasets/mp3d/<scene_id>/"
    echo "      <scene_id>.glb"
    echo "      <scene_id>.navmesh"
}

case "$MODE" in
    --model-only)
        download_model
        ;;
    --data-only)
        download_r2r_episodes
        extract_val_unseen_scenes
        check_mp3d
        ;;
    --all)
        download_model
        download_r2r_episodes
        extract_val_unseen_scenes
        check_mp3d
        ;;
    --check)
        extract_val_unseen_scenes
        check_mp3d
        ;;
    *)
        echo "Usage: bash scripts/download_data.sh [--model-only | --data-only | --all | --check]"
        echo ""
        echo "  --model-only   Download pretrained weights only (~15GB)"
        echo "  --data-only    Download R2R episodes + check MP3D scenes"
        echo "  --all          Download everything (default)"
        echo "  --check        Only check if required data is present"
        exit 1
        ;;
esac

echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
echo "  Model:      $([ -d models/JanusVLN_Extra ] && echo 'Ready' || echo 'Not downloaded')"
echo "  R2R data:   $(ls data/datasets/r2r/*/val_unseen.json.gz 2>/dev/null && echo 'Ready' || echo 'Check data/datasets/r2r/')"
echo "  Scene list: $([ -f data/val_unseen_scenes.txt ] && echo "Ready ($(wc -l < data/val_unseen_scenes.txt) scenes)" || echo 'Not extracted yet')"
echo "  MP3D scene: $([ -d data/scene_datasets/mp3d ] && [ "$(ls data/scene_datasets/mp3d/ 2>/dev/null | head -1)" ] && echo 'Has data' || echo 'MISSING')"
echo "============================================"
echo ""
echo "  Total estimated download: ~17GB (vs ~300GB+ for full training)"
echo "    Model weights:     ~15GB"
echo "    R2R episodes:      ~small"
echo "    MP3D (11 scenes):  ~2GB"
