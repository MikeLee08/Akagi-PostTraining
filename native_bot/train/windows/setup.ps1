$ErrorActionPreference = "Stop"

$trainDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$venvDir = Join-Path $trainDir ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "Python Launcher 'py' was not found. Install 64-bit Python 3.11 or 3.12 first."
}

$pythonVersion = $null
foreach ($candidate in @("3.12", "3.11")) {
    & py "-$candidate" --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $pythonVersion = "-$candidate"
        break
    }
}
if (-not $pythonVersion) {
    throw "Python 3.11 or 3.12 was not found through the 'py' launcher."
}

if (-not (Test-Path $venvPython)) {
    & py $pythonVersion -m venv $venvDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the training virtual environment."
    }
}

& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) {
    throw "Failed to upgrade pip."
}

& $venvPython -m pip install torch --index-url https://download.pytorch.org/whl/cu128
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install CUDA PyTorch. Check the official PyTorch install selector for a supported Windows wheel."
}

& $venvPython -m pip install numpy safetensors
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install NumPy and safetensors."
}

& $venvPython -c "import torch; print('PyTorch:', torch.__version__); print('CUDA:', torch.version.cuda); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'unavailable'); raise SystemExit(0 if torch.cuda.is_available() else 1)"
if ($LASTEXITCODE -ne 0) {
    throw "PyTorch cannot access a CUDA GPU. Training is stopped rather than falling back to CPU."
}

Write-Host "Training environment is ready: $venvPython"
