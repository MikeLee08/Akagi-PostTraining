param(
    [Parameter(Mandatory = $true)]
    [string]$Model
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$trainDir = Join-Path $repoRoot "native_bot\train"
$venvPython = Join-Path $trainDir ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $venvPython)) {
    throw "Training environment not found. Run native_bot\train\windows\setup.ps1 first."
}
if (-not (Test-Path -LiteralPath $Model -PathType Leaf)) {
    throw "Candidate model not found: $Model"
}
$modelPath = (Resolve-Path -LiteralPath $Model).Path

$outputDir = Join-Path $repoRoot "native_bot\out\candidate-validation"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$parityPath = Join-Path $outputDir "parity_3p_candidate.json"
if (Test-Path -LiteralPath $parityPath) {
    Remove-Item -LiteralPath $parityPath
}

$parityScript = Join-Path $trainDir "parity_check.py"
& $venvPython $parityScript $modelPath 37 27 $parityPath
if ($LASTEXITCODE -ne 0) {
    throw "Could not create the candidate parity fixture."
}

$previousWeights = $env:AKAGI_3P_CANDIDATE_WEIGHTS
$previousParity = $env:AKAGI_3P_CANDIDATE_PARITY
$env:AKAGI_3P_CANDIDATE_WEIGHTS = $modelPath
$env:AKAGI_3P_CANDIDATE_PARITY = $parityPath
try {
    & cargo test --manifest-path (Join-Path $repoRoot "native_bot\Cargo.toml") --test parity candidate_3p_from_env -- --exact
    if ($LASTEXITCODE -ne 0) {
        throw "Rust/Candle candidate parity check failed."
    }
} finally {
    if ($null -eq $previousWeights) {
        Remove-Item Env:\AKAGI_3P_CANDIDATE_WEIGHTS -ErrorAction SilentlyContinue
    } else {
        $env:AKAGI_3P_CANDIDATE_WEIGHTS = $previousWeights
    }
    if ($null -eq $previousParity) {
        Remove-Item Env:\AKAGI_3P_CANDIDATE_PARITY -ErrorAction SilentlyContinue
    } else {
        $env:AKAGI_3P_CANDIDATE_PARITY = $previousParity
    }
}

Write-Host "Candidate passed the Rust/Candle 3p parity check: $modelPath"
