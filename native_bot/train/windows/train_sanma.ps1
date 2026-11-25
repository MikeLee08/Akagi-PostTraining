param(
    [Parameter(Mandatory = $true)]
    [string]$Dataset,
    [string]$ValidationDataset,
    [string]$Output = "native_bot\out\models\akagi3p-candidate.safetensors",
    [int]$Epochs = 10,
    [int]$BatchSize = 2048,
    [double]$LearningRate = 0.0015
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$trainDir = Join-Path $repoRoot "native_bot\train"
$venvPython = Join-Path $trainDir ".venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $venvPython)) {
    throw "Training environment not found. Run native_bot\train\windows\setup.ps1 first."
}
if (-not (Test-Path -LiteralPath $Dataset -PathType Container)) {
    throw "Training dataset directory not found: $Dataset"
}
if ($ValidationDataset -and -not (Test-Path -LiteralPath $ValidationDataset -PathType Container)) {
    throw "Validation dataset directory not found: $ValidationDataset"
}
if ($Epochs -lt 1 -or $BatchSize -lt 1 -or $LearningRate -le 0) {
    throw "Epochs, BatchSize, and LearningRate must be positive."
}

$dataPaths = @($Dataset)
if ($ValidationDataset) {
    $dataPaths += $ValidationDataset
}
foreach ($dataPath in $dataPaths) {
    $metaPath = Join-Path (Resolve-Path -LiteralPath $dataPath).Path "meta.json"
    if (-not (Test-Path -LiteralPath $metaPath)) {
        throw "Dataset metadata not found: $metaPath"
    }
    $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
    if ($meta.num_players -ne 3 -or $meta.channels -ne 37 -or $meta.tile_dim -ne 27 -or $meta.action_space -ne 60) {
        throw "Dataset does not match Akagi's sanma geometry: $dataPath"
    }
}

if ([System.IO.Path]::IsPathRooted($Output)) {
    $outputPath = $Output
} else {
    $outputPath = Join-Path $repoRoot $Output
}
if (Test-Path -LiteralPath $outputPath) {
    throw "Model output already exists; choose a new path to avoid overwriting it: $outputPath"
}
$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$env:PYTHONUNBUFFERED = "1"
& $venvPython -c "import torch; print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'unavailable'); raise SystemExit(0 if torch.cuda.is_available() else 1)"
if ($LASTEXITCODE -ne 0) {
    throw "CUDA is not available. Training is stopped rather than falling back to CPU."
}

$trainer = Join-Path $trainDir "train.py"
$arguments = @(
    $trainer,
    "--data", (Resolve-Path -LiteralPath $Dataset).Path,
    "--out", $outputPath,
    "--epochs", "$Epochs",
    "--batch", "$BatchSize",
    "--lr", "$LearningRate",
    "--device", "cuda"
)
if ($ValidationDataset) {
    $arguments += @("--val-data", (Resolve-Path -LiteralPath $ValidationDataset).Path)
}

Push-Location $trainDir
try {
    & $venvPython @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Training failed."
    }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $outputPath)) {
    throw "Training completed without creating the requested model: $outputPath"
}
Write-Host "Candidate model ready: $outputPath"
