param(
    [string]$Distro = "Ubuntu",
    [string]$LinuxPath = "/root/aiml-project",
    [int]$UiPort = 8004,
    [int]$BackendPort = 8005,
    [switch]$SkipSync,
    [switch]$NoReload
)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$PythonExe = Join-Path $RepoRoot ".venv\Scripts\python.exe"
$SyncScript = Join-Path $PSScriptRoot "sync_to_wsl.ps1"
$BackendHealthUrl = "http://127.0.0.1:$BackendPort/health"
$BackendPredictUrl = "http://127.0.0.1:$BackendPort/predict"

if (-not (Test-Path $PythonExe)) {
    throw "Windows virtual environment was not found at $PythonExe"
}

if (-not $SkipSync) {
    & $SyncScript -Distro $Distro -LinuxPath $LinuxPath
    if ($LASTEXITCODE -ge 8) {
        throw "WSL sync failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Starting WSL backend on port $BackendPort"

$backendJob = Start-Job -ScriptBlock {
    param($repoRoot, $distro, $linuxPath, $backendPort)

    Set-Location $repoRoot
    wsl -d $distro -- bash -lc "cd $linuxPath && APP_PORT=$backendPort bash scripts/run_api_wsl.sh"
} -ArgumentList $RepoRoot, $Distro, $LinuxPath, $BackendPort

$backendReady = $false

for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 1

    if ($backendJob.State -match "Failed|Stopped|Completed") {
        Receive-Job $backendJob -Keep | Out-Host
        break
    }

    try {
        $response = Invoke-RestMethod -Uri $BackendHealthUrl -TimeoutSec 3
        if ($response.message) {
            $backendReady = $true
            break
        }
    } catch {
    }
}

if (-not $backendReady) {
    Stop-Job $backendJob -ErrorAction SilentlyContinue
    Remove-Job $backendJob -Force -ErrorAction SilentlyContinue
    throw "WSL backend did not become ready at $BackendHealthUrl"
}

Write-Host "WSL backend is ready"
Write-Host "Starting Windows UI server on port $UiPort"

$env:CAPTION_BACKEND_URL = $BackendPredictUrl

$uvicornArgs = @(
    "-m", "uvicorn",
    "app:app",
    "--host", "127.0.0.1",
    "--port", "$UiPort"
)

if (-not $NoReload) {
    $uvicornArgs += "--reload"
}

try {
    Set-Location $RepoRoot
    & $PythonExe @uvicornArgs
} finally {
    Stop-Job $backendJob -ErrorAction SilentlyContinue
    Remove-Job $backendJob -Force -ErrorAction SilentlyContinue
}
