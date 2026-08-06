# =============================================================================
# LogOps - Download NASA-HTTP July 1995 access logs
# Source: https://ita.ee.lbl.gov/html/contrib/NASA-HTTP.html
# =============================================================================

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$DestDir = Join-Path $Root "data\nasa"
$Gz = Join-Path $DestDir "NASA_access_log_Jul95.gz"
$Url = "https://ita.ee.lbl.gov/traces/NASA_access_log_Jul95.gz"

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

if ((Test-Path $Gz) -and ((Get-Item $Gz).Length -gt 1MB)) {
    Write-Host "Already present: $Gz ($([math]::Round((Get-Item $Gz).Length/1MB,1)) MB)"
} else {
    Write-Host "Downloading NASA-HTTP July 1995 (~20 MB)..."
    Write-Host "  $Url"
    curl.exe -L --fail --connect-timeout 30 --max-time 600 -o $Gz $Url
    if (-not (Test-Path $Gz) -or ((Get-Item $Gz).Length -lt 1MB)) {
        throw "Download failed or file too small: $Gz"
    }
    Write-Host "Saved $Gz ($([math]::Round((Get-Item $Gz).Length/1MB,1)) MB)"
}

Write-Host "Building 100k-line sample..."
python (Join-Path $PSScriptRoot "build_nasa_sample.py") 100000

Write-Host ""
Write-Host "Next:"
Write-Host "  .\scripts\Start-Lite-Nasa.ps1"
Write-Host "Docs: docs\DATASETS.md"
Write-Host "Source: https://ita.ee.lbl.gov/html/contrib/NASA-HTTP.html"
