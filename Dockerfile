# JanusVLN Docker Image for Evaluation
# Base: NVIDIA CUDA 12.4 + Ubuntu 22.04
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# System dependencies
RUN apt-get update && apt-get install -y \
    git wget curl build-essential cmake ninja-build \
    libgl1-mesa-glx libgl1-mesa-dri libglib2.0-0 libegl1-mesa \
    libsm6 libxext6 libxrender1 \
    libbullet-dev \
    python3-opencv \
    && rm -rf /var/lib/apt/lists/*

# Miniconda (needed for habitat-sim)
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p /opt/conda \
    && rm /tmp/miniconda.sh
ENV PATH="/opt/conda/bin:$PATH"

# Accept Conda ToS and create environment
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r \
    && conda create -n janusvln python=3.9 -y

# Use conda run for all subsequent commands
SHELL ["conda", "run", "--no-capture-output", "-n", "janusvln", "/bin/bash", "-c"]

# Habitat-sim 0.2.4 headless (no display needed)
RUN conda install habitat-sim=0.2.4 withbullet headless -c conda-forge -c aihabitat -y

# PyTorch 2.5.1 + CUDA 12.4 (MUST be installed before flash-attn)
RUN pip install torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cu124

# flash-attn: compile from source (no prebuilt wheel for Python 3.9)
# Must come AFTER torch. Install build deps first, use ninja for parallel compilation.
RUN pip install psutil ninja packaging \
    && MAX_JOBS=8 pip install flash-attn --no-build-isolation

# Clone original JanusVLN source code (early, to use its requirements.txt)
RUN git clone --depth 1 https://github.com/MIV-XJTU/JanusVLN.git /workspace/JanusVLN

# Project Python dependencies (flash-attn excluded, already installed above)
RUN grep -v '^flash-attn' /workspace/JanusVLN/requirements.txt > /tmp/requirements_no_flash.txt \
    && pip install -r /tmp/requirements_no_flash.txt

# Additional dependencies for evaluation
RUN pip install \
    numpy-quaternion \
    opencv-python-headless \
    omegaconf \
    hydra-core \
    bitsandbytes \
    fastdtw

# Install habitat-lab and habitat-baselines v0.2.4
RUN pip install \
    git+https://github.com/facebookresearch/habitat-lab.git@v0.2.4#subdirectory=habitat-lab \
    git+https://github.com/facebookresearch/habitat-lab.git@v0.2.4#subdirectory=habitat-baselines

# Install JanusVLN project
WORKDIR /workspace/JanusVLN
RUN pip install -e .

# Apply our patches (4-bit quantization support, etc.)
COPY patches/ /tmp/patches/
RUN cd /workspace/JanusVLN && git apply /tmp/patches/evaluation_quantize.patch

# Copy our custom scripts
COPY scripts/ /workspace/JanusVLN/scripts/

# Suppress Habitat verbose logging
ENV MAGNUM_LOG=quiet
ENV GLOG_minloglevel=2
ENV HABITAT_SIM_LOG=quiet

# Default entrypoint: activate conda env
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "janusvln"]
CMD ["bash"]
