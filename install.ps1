$ErrorActionPreference = "Stop"
$Repo = 'pppx-dev/pppx'
$ExeName = 'pppx.exe'
$DllUrl = 'https://github.com/pppx-dev/pppx/releases/download/v1.2.1/pppx_windows_dlls.zip'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\PPPx'

# Locate the repository root (the directory containing this script)
$PppxRoot = $PSScriptRoot
$PppxShSrc = Join-Path $PppxRoot 'scripts\pppx.sh'
$TableDir = Join-Path $PppxRoot 'table'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   PPPx Windows Automated Installer" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Ensure the script is run from inside the cloned repository
if (-not (Test-Path $PppxShSrc) -or -not (Test-Path $TableDir)) {
    Write-Host "Error: install.ps1 must be run from the root of the cloned PPPx repository." -ForegroundColor Red
    Write-Host "Please clone the repository first and run the installer from its root folder:"
    Write-Host "  git clone https://github.com/$Repo.git"
    Write-Host "  cd pppx"
    Write-Host "  .\install.ps1"
    exit 1
}

Write-Host "1. Fetching latest release info from GitHub..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"

try {
    $Release = Invoke-RestMethod -Uri $ApiUrl
} catch {
    Write-Host "Error: Could not reach GitHub API." -ForegroundColor Red
    exit 1
}

$Asset = $Release.assets | Where-Object { $_.name -match 'windows-x86_64\.zip$' }
if (-not $Asset) {
    Write-Host "Error: Could not find the Windows zip asset." -ForegroundColor Red
    exit 1
}

$DownloadUrl = $Asset.browser_download_url
Write-Host "   Found: $($Asset.name)"

# Setup directories
$CurrentDir = Get-Location
$TempZip = Join-Path $CurrentDir $Asset.name
$TempDllZip = Join-Path $CurrentDir "pppx_windows_dlls.zip"
$TempDllExtract = Join-Path $CurrentDir ".temp_dll_extract"

if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }

Write-Host "2. Downloading executables and required DLLs..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempZip
Invoke-WebRequest -Uri $DllUrl -OutFile $TempDllZip

Write-Host "3. Extracting and installing files..."
# Extract Main Executable
Expand-Archive -Path $TempZip -DestinationPath $CurrentDir -Force
$ExtractedExe = Get-ChildItem -Path $CurrentDir -Filter $ExeName -Recurse | Select-Object -First 1
if (-not $ExtractedExe) {
    Write-Host "Error: $ExeName not found after extraction." -ForegroundColor Red
    exit 1
}
$DestPath = Join-Path $InstallDir $ExeName
Copy-Item -Path $ExtractedExe.FullName -Destination $DestPath -Force

# Extract and Move DLLs
New-Item -ItemType Directory -Path $TempDllExtract -Force | Out-Null
Expand-Archive -Path $TempDllZip -DestinationPath $TempDllExtract -Force
$ExtractedDlls = Get-ChildItem -Path $TempDllExtract -Filter *.dll -Recurse
if ($ExtractedDlls) {
    $ExtractedDlls | Copy-Item -Destination $InstallDir -Force
    Write-Host "   Installed $($ExtractedDlls.Count) DLLs."
} else {
    Write-Host "   Warning: No DLLs found in the downloaded zip." -ForegroundColor Yellow
}

Write-Host "4. Installing pppx.sh wrapper (for Git Bash / MSYS2)..."
# Point the wrapper's table directory at the repo's table folder. Use forward
# slashes so the path works both for the native pppx.exe and inside Git Bash.
$RepoRoot = $PppxRoot -replace '\\', '/'
$PppxShContent = (Get-Content -Raw $PppxShSrc).Replace('PACKAGE_ROOT', $RepoRoot)
# WriteAllText emits UTF-8 without BOM, keeping the shebang valid for Git Bash.
[System.IO.File]::WriteAllText((Join-Path $InstallDir 'pppx.sh'), $PppxShContent)
Write-Host "   Configured table directory: $RepoRoot/table"

Write-Host "5. Updating User PATH Environment Variable..."
$UserPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($UserPath -notmatch [regex]::Escape($InstallDir)) {
    $NewPath = $UserPath + ';' + $InstallDir
    [Environment]::SetEnvironmentVariable('PATH', $NewPath, 'User')
    Write-Host "   Successfully added to PATH." -ForegroundColor Green
} else {
    Write-Host "   Directory is already in PATH."
}

Write-Host "6. Cleaning up local downloaded files..."
Remove-Item -Path $TempZip -Force
Remove-Item -Path $ExtractedExe.FullName -Force
Remove-Item -Path $TempDllZip -Force
if (Test-Path $TempDllExtract) { Remove-Item -Path $TempDllExtract -Recurse -Force }

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "Installed 'pppx.exe' and 'pppx.sh' (run from Git Bash)." -ForegroundColor Green
Write-Host "Documentation: https://github.com/$Repo/releases/latest/download/pppx-manual.pdf"
Write-Host "NOTE: If you have cmd.exe or PowerShell open, you must close and restart them to use pppx." -ForegroundColor Yellow
Write-Host ""

# Keeps the window open if they manage to run it via right-click
Read-Host -Prompt "Press Enter to exit"
