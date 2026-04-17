@echo off
setlocal

set "PYTHON_EXE=%~dp0.venv\Scripts\python.exe"

if not exist "%PYTHON_EXE%" (
    echo Windows virtual environment was not found at "%PYTHON_EXE%"
    exit /b 1
)

cd /d "%~dp0"
"%PYTHON_EXE%" -m uvicorn app:app --host 127.0.0.1 --port 8765 --reload
