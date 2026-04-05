# JanusVLN Docker Image for Evaluation
# Base: NVIDIA CUDA 12.4 + Ubuntu 22.04
FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# System dependencies
RUN apt-get update && apt-get install -y \
    git wget curl build-essential cmake \
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

# Create conda environment with Python 3.9
RUN conda create -n janusvln python=3.9 -y

# Use conda run for all subsequent commands
SHELL ["conda", "run", "--no-capture-output", "-n", "janusvln", "/bin/bash", "-c"]

# Habitat-sim 0.2.4 headless (no display needed)
RUN conda install habitat-sim=0.2.4 withbullet headless -c conda-forge -c aihabitat -y

# PyTorch 2.5.1 + CUDA 12.4
RUN pip install torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cu124

# Project Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

# Additional dependencies for evaluation
RUN pip install \
    numpy-quaternion \
    opencv-python-headless \
    omegaconf \
    hydra-core \
    bitsandbytes

# Install habitat-lab and habitat-baselines v0.2.4
RUN pip install \
    git+https://github.com/facebookresearch/habitat-lab.git@v0.2.4#subdirectory=habitat-lab \
    git+https://github.com/facebookresearch/habitat-lab.git@v0.2.4#subdirectory=habitat-baselines

# Copy project source code
COPY . /workspace/JanusVLN
WORKDIR /workspace/JanusVLN
RUN pip install -e .

# Suppress Habitat verbose logging
ENV MAGNUM_LOG=quiet
ENV GLOG_minloglevel=2
ENV HABITAT_SIM_LOG=quiet

# Default entrypoint: activate conda env
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "janusvln"]
CMD ["bash"]
