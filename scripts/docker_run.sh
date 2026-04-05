#!/bin/bash
# Launch JanusVLN Docker container interactively
# Usage: bash scripts/docker_run.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

docker run -it \
    --runtime=nvidia \
    --shm-size=8g \
    -e NVIDIA_VISIBLE_DEVICES=0 \
    -e MAGNUM_LOG=quiet \
    -e GLOG_minloglevel=2 \
    -e HABITAT_SIM_LOG=quiet \
    -v "${PROJECT_DIR}/data:/workspace/JanusVLN/data" \
    -v "${PROJECT_DIR}/models:/workspace/JanusVLN/models" \
    -v "${PROJECT_DIR}/evaluation:/workspace/JanusVLN/evaluation" \
    -v "${PROJECT_DIR}/src:/workspace/JanusVLN/src" \
    -v "${PROJECT_DIR}/config:/workspace/JanusVLN/config" \
    -v "${PROJECT_DIR}/scripts:/workspace/JanusVLN/scripts" \
    --name janusvln \
    --rm \
    janusvln:latest bash
