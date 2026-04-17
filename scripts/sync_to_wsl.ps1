param(
    [string]$Distro = "Ubuntu",
    [string]$LinuxPath = "/root/aiml-project"
)

$SourcePath = (Resolve-Path ".").Path
$TargetPath = "\\wsl$\" + $Distro + ($LinuxPath -replace "/", "\")

Write-Host "Copying project to $TargetPath"

New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null

$robocopyArgs = @(
    $SourcePath,
    $TargetPath,
    "/E",
    "/R:2",
    "/W:2",
    "/NFL",
    "/NDL",
    "/NP",
    "/NJH",
    "/NJS",
    "/XD", (Join-Path $SourcePath ".venv"),
    "/XD", (Join-Path $SourcePath "__pycache__"),
    "/XD", (Join-Path $SourcePath "model_epochs"),
    "/XD", (Join-Path $SourcePath "uploads"),
    "/XF", "*.pyc"
)

& robocopy @robocopyArgs | Out-Host

if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Next command:"
Write-Host "wsl -d $Distro -- bash -lc 'cd $LinuxPath && bash scripts/setup_wsl_ubuntu.sh'"
