# =============================================================================
# LogOps — Windows helper: create .env and generate random secrets
# Run in PowerShell from the project root:
#   .\scripts\Generate-Secrets.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $RootDir ".env"
$ExampleFile = Join-Path $RootDir ".env.example"

function Write-Log($Message) {
    # Timestamped status line for beginners
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$ts] $Message"
}

function New-RandomPassword([int]$Length = 24) {
    # Generate a simple alphanumeric password
    $bytes = New-Object byte[] $Length
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function Set-EnvValue([string]$Key, [string]$Value) {
    # Upsert KEY=VALUE inside .env
    $lines = Get-Content $EnvFile
    $found = $false
    $newLines = foreach ($line in $lines) {
        if ($line -match "^$([regex]::Escape($Key))=") {
            $found = $true
            "$Key=$Value"
        } else {
            $line
        }
    }
    if (-not $found) {
        $newLines += "$Key=$Value"
    }
    $newLines | Set-Content -Path $EnvFile -Encoding UTF8
}

if (-not (Test-Path $ExampleFile)) {
    throw "Missing $ExampleFile"
}

if (-not (Test-Path $EnvFile)) {
    Copy-Item $ExampleFile $EnvFile
    Write-Log "Created $EnvFile from example"
} else {
    Write-Log "Updating existing $EnvFile"
}

# Try to create a proper Fernet key with Python if available
$fernet = $null
try {
    $fernet = python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" 2>$null
} catch {
    $fernet = $null
}
if (-not $fernet) {
    # Fallback: url-safe base64 of 32 random bytes
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $fernet = [Convert]::ToBase64String($bytes).Replace("+", "-").Replace("/", "_")
}

Set-EnvValue "AIRFLOW_FERNET_KEY" $fernet
Set-EnvValue "AIRFLOW_POSTGRES_PASSWORD" (New-RandomPassword)
Set-EnvValue "AIRFLOW_ADMIN_PASSWORD" (New-RandomPassword)
Set-EnvValue "CLICKHOUSE_PASSWORD" (New-RandomPassword)
Set-EnvValue "MINIO_ROOT_USER" "logopsminio"
Set-EnvValue "MINIO_ROOT_PASSWORD" (New-RandomPassword)
Set-EnvValue "GRAFANA_ADMIN_PASSWORD" (New-RandomPassword)
Set-EnvValue "SUPERSET_SECRET_KEY" ((New-RandomPassword) + (New-RandomPassword))
Set-EnvValue "SUPERSET_ADMIN_PASSWORD" (New-RandomPassword)

Write-Log "Random secrets written."
Write-Log "Still fill manually: AWS, Databricks, SSH key path, email/SMTP, Slack."
Write-Log "Open .env and search for [FILL_IN_YOUR_"
