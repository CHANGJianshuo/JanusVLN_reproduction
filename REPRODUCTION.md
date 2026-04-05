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

### Stage 4: Download Data & Models -- TODO
**Inference-only minimal download (~17GB total, vs ~300GB+ for training):**
- [ ] Download pretrained weights: `misstl/JanusVLN_Extra` from ModelScope (~15GB)
- [ ] Download R2R VLN-CE episodes from Google Drive (val_unseen split only needed)
- [ ] Extract val_unseen scene list (script auto-parses episodes file)
- [ ] Download only 11 MP3D scenes used in val_unseen (~2GB, not all 90 scenes)

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

### Stage 6: Rent Cloud GPU & Run Evaluation -- TODO
- [ ] Rent AutoDL A100 40GB instance
- [ ] Push Docker image or rebuild on cloud
- [ ] Transfer data (model weights + MP3D scenes + R2R episodes)
- [ ] Run R2R val_unseen evaluation (no quantization needed on A100)
- [ ] Compare metrics (SR, SPL, NDTW) with paper results

---

## Key Files Modified/Created

| File | Status | Description |
|------|--------|-------------|
| `Dockerfile` | NEW | Full environment build |
| `.dockerignore` | NEW | Exclude large dirs from build |
| `docker-compose.yml` | NEW | Container orchestration |
| `scripts/docker_run.sh` | NEW | Manual container launch |
| `scripts/eval_single_gpu.sh` | NEW | Single-GPU eval with --quantize |
| `scripts/download_data.sh` | NEW | Automated data/model download |
| `src/evaluation.py` | MODIFIED | Added 4-bit quantization support |
| `REPRODUCTION.md` | NEW | This file |

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
