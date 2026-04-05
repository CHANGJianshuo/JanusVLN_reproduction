#!/bin/bash
# Single-GPU evaluation script for JanusVLN
# Run this INSIDE the Docker container
# Usage: bash scripts/eval_single_gpu.sh [--quantize]

set -e
export MAGNUM_LOG=quiet
export HABITAT_SIM_LOG=quiet

CHECKPOINT="models/JanusVLN_Extra"
OUTPUT_PATH="evaluation"
CONFIG="config/vln_r2r.yaml"
EVAL_SPLIT="val_unseen"
EXTRA_ARGS=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --quantize)
            EXTRA_ARGS="${EXTRA_ARGS} --quantize_4bit"
            echo "[INFO] 4-bit quantization enabled (for 8GB VRAM GPUs)"
            ;;
        --val_seen)
            EVAL_SPLIT="val_seen"
            ;;
        --val_unseen)
            EVAL_SPLIT="val_unseen"
            ;;
        *)
            EXTRA_ARGS="${EXTRA_ARGS} $arg"
            ;;
    esac
done

echo "=== JanusVLN Evaluation ==="
echo "Checkpoint: ${CHECKPOINT}"
echo "Config:     ${CONFIG}"
echo "Split:      ${EVAL_SPLIT}"
echo "Output:     ${OUTPUT_PATH}"
echo "Extra args: ${EXTRA_ARGS}"
echo "==========================="

MASTER_PORT=$((RANDOM % 101 + 20000))

# Single GPU: nproc_per_node=1
torchrun --nproc_per_node=1 --master_port=$MASTER_PORT \
    src/evaluation.py \
    --model_path $CHECKPOINT \
    --habitat_config_path $CONFIG \
    --eval_split $EVAL_SPLIT \
    --save_video \
    --output_path $OUTPUT_PATH \
    $EXTRA_ARGS
