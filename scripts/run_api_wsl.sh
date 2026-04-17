#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${VENV_DIR:-$PROJECT_DIR/.venv-wsl}"
CUDA_HOME="${CUDA_HOME:-/usr/local/cuda-12.8}"
APP_HOST="${APP_HOST:-127.0.0.1}"
APP_PORT="${APP_PORT:-8004}"
APP_RELOAD="${APP_RELOAD:-0}"

if [[ ! -d "$VENV_DIR" ]]; then
    printf "Virtual environment not found: %s\n" "$VENV_DIR" >&2
    printf "Run bash scripts/setup_wsl_ubuntu.sh first.\n" >&2
    exit 1
fi

export PATH="${CUDA_HOME}/bin:$PATH"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"

# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

cd "$PROJECT_DIR"

if [[ "$APP_RELOAD" == "1" ]]; then
    exec uvicorn app:app --host "$APP_HOST" --port "$APP_PORT" --reload
fi

exec uvicorn app:app --host "$APP_HOST" --port "$APP_PORT"
