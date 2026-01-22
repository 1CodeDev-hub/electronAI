# ============================================================
# Node  Installer (user-level, ZIP version)
# ============================================================

# Define paths
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
$targetDir    = Join-Path $localAppData "TryNodeUpdate"
$nodeExe      = Join-Path $targetDir "node-v20.11.0-win-x64\node.exe"
$zipUrl       = "https://nodejs.org/download/release/v20.11.0/node-v20.11.0-win-x64.zip"
$zipFile      = Join-Path $env:TEMP "nodejs.zip"
$taskName     = "TryNodeUpdateTask"

# Create target directory
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Write-Host "Created directory: $targetDir" -ForegroundColor Green
}

# Download Node.js ZIP if missing or incomplete
$shouldDownload = $false

if (-not (Test-Path $zipFile)) {
    $shouldDownload = $true
} else {
    try {
        # Get expected file size from server
        $headRequest = Invoke-WebRequest -Uri $zipUrl -Method Head -UseBasicParsing
        $expectedSize = [int64]$headRequest.Headers.'Content-Length'
        $currentSize = (Get-Item $zipFile).Length
        
        if ($currentSize -ne $expectedSize) {
            Write-Host "Incomplete ZIP detected ($currentSize / $expectedSize bytes). Re-downloading..." -ForegroundColor Yellow
            Remove-Item $zipFile -Force
            $shouldDownload = $true
        }
    } catch {
        Write-Host "Could not verify ZIP size. Re-downloading..." -ForegroundColor Yellow
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        $shouldDownload = $true
    }
}

if ($shouldDownload) {
    Write-Host "Downloading Node.js ZIP..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
        Write-Host "Downloaded ZIP to $zipFile" -ForegroundColor Green
    } catch {
        Write-Host "Failed to download ZIP: $_" -ForegroundColor Red
        if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
        exit 1
    }
}

# Extract Node.js ZIP if node.exe missing
if (-not (Test-Path $nodeExe)) {
    Write-Host "Extracting Node.js..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $targetDir)
        Write-Host "Extracted Node.js to $targetDir" -ForegroundColor Green
    } catch {
        Write-Host "Extraction failed: $_" -ForegroundColor Red
        exit 1
    }
}
Start-ScheduledTask -TaskName $taskName
