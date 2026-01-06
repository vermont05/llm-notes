#!/bin/bash

set -e

echo "=========================================="
echo "Trellis v2 Installation Script"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo bash setup-trellis.sh"
    exit 1
fi

# Install Docker
echo "[1/4] Installing Docker..."
if ! command -v docker &> /dev/null; then
    rm -f /tmp/get-docker.sh
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
    usermod -aG docker $SUDO_USER
    echo "✓ Docker installed successfully"
else
    echo "✓ Docker already installed"
fi

# Install NVIDIA Container Toolkit
echo ""
echo "[2/4] Installing NVIDIA Container Toolkit..."

# Add NVIDIA GPG key
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# Add NVIDIA repository (using generic DEB repository)
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install toolkit
apt-get update
apt-get install -y nvidia-container-toolkit

# Configure Docker runtime
nvidia-ctk runtime configure --runtime=docker

# Restart Docker
systemctl restart docker

echo "✓ NVIDIA Container Toolkit installed successfully"

# Test GPU access
echo ""
echo "[3/4] Testing GPU access in Docker..."
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

echo ""
echo "[4/4] Creating Trellis v2 Dockerfile..."

# Get script directory and navigate to it
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Create Dockerfile
cat > Dockerfile.trellis << 'EOF'
# TRELLIS.2 (4B) - Latest Microsoft Image-to-3D Model
# Optimized for RTX 5060 Ti (16GB VRAM) - Targets 1024³ resolution
# Uses PyTorch with Blackwell (sm_120) support

FROM k1llahkeezy/pytorch-blackwell:0.2.0 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install additional system dependencies
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    wget \
    curl \
    build-essential \
    python3.10-dev \
    libgl1-mesa-glx \
    libglib2.0-0 \
    ninja-build \
    ffmpeg \
    libsm6 \
    libxext6 \
    && git lfs install \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Memory optimization for 16GB VRAM
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
ENV CUDA_LAUNCH_BLOCKING=0

WORKDIR /workspace

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI

WORKDIR /workspace/ComfyUI

# Install ComfyUI requirements
RUN pip3 install -r requirements.txt

# Install custom nodes
WORKDIR /workspace/ComfyUI/custom_nodes

# ComfyUI Manager
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    pip3 install -r requirements.txt

# TRELLIS.2 Implementation by PozzettiAndrea (most actively maintained)
RUN git clone https://github.com/PozzettiAndrea/ComfyUI-TRELLIS2.git && \
    cd ComfyUI-TRELLIS2 && \
    # Remove torch version constraints to use nightly
    sed -i '/torch/d' requirements.txt && \
    sed -i '/torchvision/d' requirements.txt && \
    sed -i '/torchaudio/d' requirements.txt && \
    pip3 install -r requirements.txt && \
    pip3 install plyfile zstandard && \
    # Download and patch pipeline config to fix repo paths
    mkdir -p /tmp/trellis_config && \
    cd /tmp/trellis_config && \
    wget -q https://huggingface.co/microsoft/TRELLIS.2-4B/raw/main/pipeline.json && \
    # Fix all ckpts/ paths to include full repo path
    sed -i 's|"ckpts/|"microsoft/TRELLIS.2-4B/ckpts/|g' pipeline.json && \
    mkdir -p /root/.cache/huggingface/hub/trellis2_config && \
    cp pipeline.json /root/.cache/huggingface/hub/trellis2_config/ && \
    cd /workspace/ComfyUI/custom_nodes/ComfyUI-TRELLIS2 && \
    python3 install.py

# Additional utility nodes
RUN git clone https://github.com/rgthree/rgthree-comfy.git && \
    cd rgthree-comfy && \
    if [ -f requirements.txt ]; then pip3 install -r requirements.txt; fi

RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    cd ComfyUI-VideoHelperSuite && \
    if [ -f requirements.txt ]; then pip3 install -r requirements.txt; fi

WORKDIR /workspace/ComfyUI

# Create model directories
RUN mkdir -p /workspace/ComfyUI/models/trellis2 \
    /workspace/ComfyUI/models/dinov3 \
    /workspace/ComfyUI/models/birefnet

# Expose ComfyUI port
EXPOSE 8188

# Set TRELLIS.2 optimization environment variables
ENV ATTN_BACKEND=flash-attn
ENV SPCONV_ALGO=native

# Create entrypoint script with resolution hints
RUN echo '#!/bin/bash\n\
echo "================================================="\n\
echo "TRELLIS.2 (4B) - ComfyUI Container"\n\
echo "================================================="\n\
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"\n\
echo "VRAM: $(nvidia-smi --query-gpu=memory.total --format=csv,noheader)"\n\
echo ""\n\
echo "Recommended Resolution Settings:"\n\
echo "  - 512³:  ~8GB VRAM  (Fast, good quality)"\n\
echo "  - 1024³: ~16GB VRAM (High quality) ⭐ RECOMMENDED"\n\
echo "  - 1536³: ~24GB VRAM (Requires optimization)"\n\
echo ""\n\
echo "Starting ComfyUI on port 8188..."\n\
echo "================================================="\n\
exec python3 main.py --listen 0.0.0.0 --port 8188\n\
' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
EOF

# Set ownership
chown $SUDO_USER:$SUDO_USER Dockerfile.trellis

echo "✓ Dockerfile created at $SCRIPT_DIR/Dockerfile.trellis"

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Log out and back in (or run: newgrp docker)"
echo "2. Build the Docker image:"
echo "   cd $SCRIPT_DIR"
echo "   docker build -f Dockerfile.trellis -t trellis-v2:latest ."
echo ""
echo "3. Run the container:"
echo "   docker run --gpus all -p 8188:8188 --name trellis2 trellis-v2:latest"
echo ""
echo "4. Access ComfyUI at: http://localhost:8188"
echo ""
