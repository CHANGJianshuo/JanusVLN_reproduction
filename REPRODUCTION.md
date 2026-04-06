# JanusVLN Reproduction Plan

Reproducing the ICLR 2026 paper: **Decoupling Semantics and Spatiality with Dual Implicit Memory for Vision-Language Navigation**

Original repo: https://github.com/MIV-XJTU/JanusVLN

## Hardware Environment

| Resource | Available | Required by Paper |
|----------|-----------|-------------------|
| GPU | RTX 5060 Laptop **8GB** VRAM | 8x GPU, 40GB+ each |
| RAM | 16GB | 128GB+ |
| Disk | 945GB free | ~400GB+ |
| CUDA Driver | 12.9 | 12.4 (compatible) |

**Critical Compatibility Issue:**
RTX 5060 (Blackwell, sm_120) is NOT compatible with PyTorch 2.5.1 (max sm_90).
PyTorch nightly with sm_120 support requires Python 3.12+, but habitat-sim 0.2.4 only supports Python 3.9.
**Local GPU cannot run this project.** Must rent cloud GPU (A100/A6000, sm_80/sm_86).

**Strategy:** Build Docker image locally, rent cloud GPU (e.g. AutoDL A100 40GB) for actual evaluation.

---

## Reproduction Stages

### Stage 1: Environment Setup (Docker) -- DONE
- [x] Clone original repo
- [x] Create `Dockerfile` (CUDA 12.4 + conda + habitat-sim 0.2.4 headless + PyTorch 2.5.1 + all deps)
- [x] Create `.dockerignore` (exclude data/models from build context)
- [x] Create `docker-compose.yml` (runtime=nvidia, shm_size=8g, volume mounts)
- [x] Create `scripts/docker_run.sh` (manual docker run alternative)

### Stage 2: Evaluation Code Adaptation -- DONE
- [x] Modify `src/evaluation.py`: add `--quantize_4bit` argument
- [x] Modify `JanusVLN_Inference.__init__`: support BitsAndBytes 4-bit NF4 quantization
- [x] Create `scripts/eval_single_gpu.sh` (single GPU + quantization support)

### Stage 3: Data & Model Download Scripts -- DONE
- [x] Create `scripts/download_data.sh` (ModelScope model download + Google Drive R2R episodes + MP3D check)

### Stage 4: Download Data & Models -- DONE
**Inference-only minimal download (~19GB total, vs ~300GB+ for training):**
- [x] Download pretrained weights: `misstl/JanusVLN_Extra` from ModelScope (~18GB)
- [x] Download R2R VLN-CE episodes (all splits, 251MB)
- [x] Extract val_unseen scene list (11 scenes)
- [x] Download only 11 MP3D scenes used in val_unseen (663MB)

**NOT needed for inference:**
- ~~Trajectory data (~50GB+)~~ -- training only
- ~~ScaleVLN / HM3D scenes (~100GB+)~~ -- training only
- ~~R2R/RxR training episodes~~ -- training only
- ~~DAgger data~~ -- training only

### Stage 5: Build & Test Docker Image -- DONE
- [x] `docker build -t janusvln:latest .` (37.5GB image, all deps installed)
- [x] Verify habitat-sim loads correctly inside container
- [x] Verify GPU passthrough works (nvidia-smi inside container)
- [x] **Found:** RTX 5060 (sm_120) incompatible with PyTorch 2.5.1 — must use cloud A100/A6000

### Stage 6: Cloud GPU Evaluation Attempts -- IN PROGRESS

#### 6a: RTX 3090 24GB (non-AutoDL) -- FAILED
- [x] Rent RTX 3090 24GB instance
- [x] Install full environment (conda, habitat-sim, PyTorch, flash-attn, etc.)
- [x] Transfer all data (model weights, MP3D scenes, R2R episodes)
- [x] Attempt bf16 evaluation — **OOM** (peak ~23GB > 24GB)
- [x] Attempt 4-bit/8-bit quantization — **bitsandbytes incompatible with VGGT's DINOv2 ViT**
- [x] **Conclusion: 3090 24GB insufficient. Minimum 40GB required.**
- See `docs/cloud_gpu_log.md` for full details.

#### 6b: A100 PCIe 40GB (AutoDL) -- TODO
- [ ] Rent AutoDL A100 PCIe 40GB instance
- [ ] Install environment (reuse validated install steps from 3090)
- [ ] Transfer data from local machine
- [ ] Run R2R val_unseen evaluation (bf16, no quantization needed)
- [ ] Compare metrics (SR, SPL, NDTW) with paper results

---

## Key Files Modified/Created

| File | Status | Description |
|------|--------|-------------|
| `Dockerfile` | NEW | Full environment build (A100/cloud) |
| `Dockerfile.rtx5060` | NEW | RTX 5060 (Blackwell sm_120) build |
| `Dockerfile.patch` | NEW | Lightweight patch on existing image |
| `.dockerignore` | NEW | Exclude large dirs from build |
| `docker-compose.yml` | NEW | Container orchestration |
| `scripts/docker_run.sh` | NEW | Manual container launch |
| `scripts/eval_single_gpu.sh` | NEW | Single-GPU eval with --quantize |
| `scripts/download_data.sh` | NEW | Automated data/model download |
| `scripts/download_weights.sh` | NEW | Model weights download with resume |
| `scripts/patch_habitat_py312.py` | NEW | Auto-patch habitat for Python 3.12 |
| `patches/evaluation_quantize.patch` | NEW | 4-bit quantization for evaluation.py |
| `data/val_unseen_scenes.txt` | NEW | 11 scene IDs for val_unseen split |
| `docs/cloud_gpu_log.md` | NEW | Cloud GPU work log (3090 attempts, A100 plan) |
| `REPRODUCTION.md` | NEW | This file |

**Note:** This repo contains only our reproduction infrastructure. The original JanusVLN source code is cloned from https://github.com/MIV-XJTU/JanusVLN inside the Docker build.

## Quick Start

```bash
# 1. Download data & model
bash scripts/download_data.sh --all

# 2. Build Docker image
docker build -t janusvln:latest .

# 3. Launch container
bash scripts/docker_run.sh

# 4. Inside container: run evaluation
bash scripts/eval_single_gpu.sh --quantize    # 8GB GPU
bash scripts/eval_single_gpu.sh               # 40GB+ GPU
```
