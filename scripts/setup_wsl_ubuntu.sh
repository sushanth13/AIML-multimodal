#!/usr/bin/env bash
set -euo pipefail

CUDA_MAJOR_MINOR="${CUDA_MAJOR_MINOR:-12-8}"
CUDA_TOOLKIT_VERSION="${CUDA_TOOLKIT_VERSION:-12.8}"
PROJECT_DIR="${1:-$(pwd)}"
REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-$PROJECT_DIR/requirements-wsl.txt}"
VENV_DIR="${VENV_DIR:-$PROJECT_DIR/.venv-wsl}"
PYTORCH_INDEX_URL="${PYTORCH_INDEX_URL:-https://download.pytorch.org/whl/cu128}"
TORCH_VERSION="${TORCH_VERSION:-2.7.0}"
TORCHVISION_VERSION="${TORCHVISION_VERSION:-0.22.0}"
TORCHAUDIO_VERSION="${TORCHAUDIO_VERSION:-2.7.0}"
MAMBA_VERSION="${MAMBA_VERSION:-2.3.1}"

log() {
    printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"
}

fail() {
    printf "ERROR: %s\n" "$*" >&2
    exit 1
}

if ! grep -qi microsoft /proc/version; then
    fail "This script is intended to run inside WSL2."
fi

if [[ ! -f "$PROJECT_DIR/app.py" ]] || [[ ! -f "$PROJECT_DIR/model.py" ]]; then
    fail "Project files were not found in: $PROJECT_DIR"
fi

if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
    fail "Requirements file was not found: $REQUIREMENTS_FILE"
fi

if [[ "$PROJECT_DIR" == /mnt/* ]]; then
    log "Warning: the project is running from the Windows filesystem."
    log "This works, but WSL performs better when the repo lives under the Linux filesystem."
fi

export DEBIAN_FRONTEND=noninteractive

log "Installing Ubuntu prerequisites"
apt-get update
apt-get install -y python3-pip python3-venv build-essential git wget curl ca-certificates

if ! command -v nvcc >/dev/null 2>&1; then
    log "Installing NVIDIA CUDA toolkit ${CUDA_TOOLKIT_VERSION}"

    if ! dpkg -s cuda-keyring >/dev/null 2>&1; then
        wget -q --show-progress \
            https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
            -O /tmp/cuda-keyring_1.1-1_all.deb
        dpkg -i /tmp/cuda-keyring_1.1-1_all.deb
    fi

    apt-get update
    apt-get install -y "cuda-toolkit-${CUDA_MAJOR_MINOR}"
fi

CUDA_HOME="/usr/local/cuda-${CUDA_TOOLKIT_VERSION}"
if [[ ! -x "$CUDA_HOME/bin/nvcc" ]] && command -v nvcc >/dev/null 2>&1; then
    CUDA_HOME="$(dirname "$(dirname "$(command -v nvcc)")")"
fi

if [[ ! -x "$CUDA_HOME/bin/nvcc" ]]; then
    fail "nvcc was not found after the CUDA toolkit installation."
fi

PROFILE_FILE="/etc/profile.d/cuda-${CUDA_MAJOR_MINOR}.sh"
if [[ ! -f "$PROFILE_FILE" ]]; then
    cat >"$PROFILE_FILE" <<EOF
export PATH=${CUDA_HOME}/bin:\$PATH
export LD_LIBRARY_PATH=${CUDA_HOME}/lib64:\${LD_LIBRARY_PATH:-}
EOF
fi

export PATH="${CUDA_HOME}/bin:$PATH"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"

if [[ ! -d "$VENV_DIR" ]]; then
    log "Creating Python virtual environment at $VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

log "Upgrading pip tooling"
python -m pip install --upgrade pip setuptools wheel

log "Installing CUDA-enabled PyTorch"
python -m pip install \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" \
    --index-url "${PYTORCH_INDEX_URL}"

log "Installing project dependencies"
python -m pip install -r "$REQUIREMENTS_FILE"

log "Installing mamba-ssm"
python -m pip install "mamba-ssm==${MAMBA_VERSION}" --no-build-isolation

log "Verifying CUDA, mamba_ssm, and checkpoint loading"
cd "$PROJECT_DIR"
python - <<'PY'
import torch

print("torch", torch.__version__)
print("cuda_available", torch.cuda.is_available())
if not torch.cuda.is_available():
    raise SystemExit("CUDA is not available inside WSL.")

print("device", torch.cuda.get_device_name(0))

from mamba_ssm import Mamba
print("mamba", Mamba.__name__)

from model import load_model
model = load_model("final_model.pth")
print("loaded_device", next(model.parameters()).device)
PY

log "Setup complete"
printf "Run the API with:\n  bash scripts/run_api_wsl.sh\n"
