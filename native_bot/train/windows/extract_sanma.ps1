param(
    [Parameter(Mandatory = $true)]
    [string]$Dataset,
    [Parameter(Mandatory = $true)]
    [string]$Output,
    [int]$MaxGames = 40000,
    [int]$MaxSamples = 4000000
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$datasetPath = (Resolve-Path -LiteralPath $Dataset).Path
if (-not (Test-Path -LiteralPath $datasetPath -PathType Container)) {
    throw "Dataset must be a directory: $Dataset"
}
if ($MaxGames -lt 1 -or $MaxSamples -lt 1) {
    throw "MaxGames and MaxSamples must be positive integers."
}

$gzipFiles = Get-ChildItem -LiteralPath $datasetPath -Filter "*.gz" -File -Recurse
if ($gzipFiles.Count -eq 0) {
    throw "No .json.gz game logs were found under $datasetPath"
}

if ([System.IO.Path]::IsPathRooted($Output)) {
    $outputPath = $Output
} else {
    $outputPath = Join-Path (Get-Location).Path $Output
}
if (Test-Path -LiteralPath $outputPath) {
    if ((Get-ChildItem -LiteralPath $outputPath -Force | Measure-Object).Count -gt 0) {
        throw "Output directory is not empty; choose a new path: $outputPath"
    }
} else {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

$manifest = Join-Path $repoRoot "native_bot\Cargo.toml"
& cargo build --manifest-path $manifest --release --no-default-features --features extract --bin extract
if ($LASTEXITCODE -ne 0) {
    throw "Rust extractor build failed."
}

$extractor = Join-Path $repoRoot "native_bot\target\release\extract.exe"
if (-not (Test-Path -LiteralPath $extractor)) {
    throw "Extractor binary was not created: $extractor"
}

& $extractor $datasetPath 3 $outputPath $MaxGames $MaxSamples
if ($LASTEXITCODE -ne 0) {
    throw "Sanma extraction failed."
}

$metaPath = Join-Path $outputPath "meta.json"
if (-not (Test-Path -LiteralPath $metaPath)) {
    throw "Extractor did not produce meta.json."
}
$meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
if ($meta.num_players -ne 3 -or $meta.channels -ne 37 -or $meta.tile_dim -ne 27 -or $meta.action_space -ne 60) {
    throw "Extracted data geometry does not match Akagi's sanma model."
}
if ($meta.total_samples -lt 1) {
    throw "Extractor produced no training samples."
}

Write-Host "Sanma samples ready: $($meta.total_samples) samples at $outputPath"
