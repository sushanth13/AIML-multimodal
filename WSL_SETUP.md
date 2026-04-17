# WSL2 Setup For This Model

This project can run in WSL2 on your machine because:

- `wsl --status` shows Ubuntu with WSL version 2.
- `nvidia-smi` on Windows shows an NVIDIA GeForce RTX 4050 Laptop GPU.
- `nvidia-smi -L` inside Ubuntu also sees that GPU.

This model still needs Linux, CUDA, and `mamba-ssm` for inference. The Windows virtualenv in this repo is not enough for that checkpoint.

## Recommended Layout

Microsoft recommends keeping Linux-worked project files in the Linux filesystem for better WSL performance, not under `C:\...` or `/mnt/c/...`.

On this machine, Ubuntu currently starts as `root`, so the helper commands below use `/root/aiml-project`.

## 1. Copy The Project Into WSL

From PowerShell in this repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync_to_wsl.ps1
```

That copies the project to:

```text
\\wsl$\Ubuntu\root\aiml-project
```

## 2. Run The Ubuntu Setup Script

From PowerShell:

```powershell
wsl -d Ubuntu -- bash -lc 'cd /root/aiml-project && bash scripts/setup_wsl_ubuntu.sh'
```

The setup script will:

- install Ubuntu build tools, `pip`, and `venv`
- install the NVIDIA CUDA toolkit for Ubuntu
- create `.venv-wsl`
- install CUDA-enabled PyTorch
- install app dependencies
- install `mamba-ssm` with `--no-build-isolation`
- verify CUDA access and load `final_model.pth`

## 3. Start The API In WSL

From PowerShell:

```powershell
wsl -d Ubuntu -- bash -lc 'cd /root/aiml-project && bash scripts/run_api_wsl.sh'
```

The FastAPI app listens on `127.0.0.1:8004`, and WSL2 localhost forwarding should let your Windows browser or `index.html` reach it.

## Optional Hybrid Mode

If you want to run the UI server directly from the Windows `.venv` but still use the Linux model for inference:

Simplest option:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_hybrid.ps1
```

That single command will:

- sync the repo into WSL
- start the WSL inference backend on `127.0.0.1:8005`
- start the Windows UI server on `127.0.0.1:8004`

Manual option:

1. Start the WSL backend on port `8005`:

```powershell
wsl -d Ubuntu -- bash -lc 'cd /root/aiml-project && APP_PORT=8005 bash scripts/run_api_wsl.sh'
```

2. Start the Windows UI server on port `8004`:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app:app --host 127.0.0.1 --port 8004 --reload
```

In that mode, the Windows app serves the UI and automatically forwards `/predict` to `http://127.0.0.1:8005/predict` when the model cannot load natively on Windows.

## 4. Open The Project In A WSL Editor

If you use VS Code, open the WSL copy of the repo instead of the Windows copy:

```powershell
wsl -d Ubuntu -- bash -lc 'cd /root/aiml-project && code .'
```

## Notes

- Do not install a Linux NVIDIA display driver inside WSL. Only the CUDA toolkit is needed there.
- The setup script assumes Ubuntu 24.04 and installs `cuda-toolkit-12-8`.
- If you later create a normal Ubuntu user, you can rerun the same flow with a user-owned Linux path like `/home/<user>/aiml-project`.
