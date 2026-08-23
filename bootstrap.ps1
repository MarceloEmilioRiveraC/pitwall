<#
.SYNOPSIS
  Builds the portable agent console into .\bin. Downloads every binary, sets up
  Windows Terminal in portable mode, and installs the Nerd Font for the current
  user only.

.DESCRIPTION
  The global footprint of this script is exactly one thing: the Nerd Font,
  installed per user (no admin). Everything else lives inside .\bin and
  disappears when you delete this folder. Your system Windows Terminal, your
  %APPDATA%\herdr and your ~/.claude are never read or written.

  Compatible with Windows PowerShell 5.1 and PowerShell 7.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Force
#>
[CmdletBinding()]
param(
    # Re-extract and reinstall everything, reusing the download cache.
    [switch]$Force,

    # Also refetch every archive, ignoring the cache.
    [switch]$Redownload,

    # Leave the Nerd Font alone.
    [switch]$SkipFont
)

if ($Redownload) { $Force = $true }

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # makes Invoke-WebRequest far faster

$Root  = $PSScriptRoot
$Bin   = Join-Path $Root 'bin'
$Cache = Join-Path $Bin  '.cache'

# ---------------------------------------------------------------------------
# Manifest. Bump a version here and re-run with -Force to update.
# Verified against the GitHub releases API on 2026-08-23.
# ---------------------------------------------------------------------------
$Manifest = @(
    @{
        Name = 'WindowsTerminal'; Version = '1.25.1912.0'; Kind = 'wt'
        Url  = 'https://github.com/microsoft/terminal/releases/download/v1.25.1912.0/Microsoft.WindowsTerminalPreview_1.25.1912.0_x64.zip'
    }
    @{
        # 'bundle', not 'exe': the herdr archive ships herdr.exe alongside a
        # conpty\ folder (conpty.dll plus a per-architecture OpenConsole.exe)
        # that herdr loads at runtime and checksums against
        # conpty\herdr-conpty.json. Extracting herdr.exe on its own produces a
        # binary that starts and exits immediately with no log written.
        Name = 'herdr'; Version = '0.8.2'; Kind = 'bundle'; Exe = 'herdr.exe'
        Url  = 'https://github.com/herdrdev/herdr/releases/download/v0.8.2/herdr-windows-x86_64.zip'
    }
    @{
        Name = 'lazygit'; Version = '0.64.1'; Kind = 'exe'; Exe = 'lazygit.exe'
        Url  = 'https://github.com/jesseduffield/lazygit/releases/download/v0.64.1/lazygit_0.64.1_windows_x86_64.zip'
    }
    @{
        Name = 'delta'; Version = '0.19.2'; Kind = 'exe'; Exe = 'delta.exe'
        Url  = 'https://github.com/dandavison/delta/releases/download/0.19.2/delta-0.19.2-x86_64-pc-windows-msvc.zip'
    }
    @{
        Name = 'bat'; Version = '0.26.1'; Kind = 'exe'; Exe = 'bat.exe'
        Url  = 'https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-x86_64-pc-windows-msvc.zip'
    }
    @{
        Name = 'glow'; Version = '3.0.0'; Kind = 'exe'; Exe = 'glow.exe'
        Url  = 'https://github.com/charmbracelet/glow/releases/download/v3.0.0/glow_3.0.0_Windows_x86_64.zip'
    }
    @{
        Name = 'JetBrainsMonoNerdFont'; Version = '3.5.1'; Kind = 'font'
        Url  = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.zip'
    }
)

function Write-Step { param($Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param($Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Note { param($Message) Write-Host "    $Message" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
Write-Step 'Checking preconditions'

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'This bundle pins x64 binaries. Edit the manifest for another architecture.'
}
Write-Ok 'OS is 64-bit'

$pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($pwshCmd) {
    Write-Ok "pwsh found: $($pwshCmd.Source)"
}
else {
    Write-Note 'pwsh (PowerShell 7) not found. Panes will fall back to Windows PowerShell 5.1.'
    Write-Note 'Install it with: winget install Microsoft.PowerShell'
}

$vcRuntime = Join-Path $env:SystemRoot 'System32\VCRUNTIME140.dll'
if (Test-Path $vcRuntime) {
    Write-Ok 'VCRUNTIME140.dll present (herdr 0.8.2 needs it, see herdrdev/herdr#3129)'
}
else {
    Write-Note 'VCRUNTIME140.dll missing. herdr 0.8.2 needs it. Install it with:'
    Write-Note '  winget install Microsoft.VCRedist.2015+.x64'
}

New-Item -ItemType Directory -Force -Path $Bin, $Cache | Out-Null

# TLS 1.2 for Windows PowerShell 5.1, whose default can refuse GitHub.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# 1. Download
# ---------------------------------------------------------------------------
Write-Step 'Downloading components'

foreach ($component in $Manifest) {
    $zipPath = Join-Path $Cache ("{0}-{1}.zip" -f $component.Name, $component.Version)

    # The cache key carries the version, so a present archive is by definition
    # the right one. -Force re-extracts; only -Redownload refetches. Without
    # this split, fixing an extraction bug costs a 160 MB download.
    if ((Test-Path $zipPath) -and -not $Redownload) {
        Write-Ok "$($component.Name) $($component.Version) already cached"
        continue
    }

    Write-Host "    fetching $($component.Name) $($component.Version) ..." -NoNewline
    try {
        Invoke-WebRequest -Uri $component.Url -OutFile $zipPath -UseBasicParsing
        $sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
        Write-Host " ok ($sizeMb MB)" -ForegroundColor Green
    }
    catch {
        Write-Host ' FAILED' -ForegroundColor Red
        throw "Could not download $($component.Name) from $($component.Url): $_"
    }
}

# ---------------------------------------------------------------------------
# 2. Extract the standalone binaries
# ---------------------------------------------------------------------------
Write-Step 'Extracting binaries'

foreach ($component in ($Manifest | Where-Object { $_.Kind -in @('exe', 'bundle') })) {
    $destination = Join-Path $Bin $component.Exe

    if ((Test-Path $destination) -and -not $Force) {
        Write-Ok "$($component.Exe) already present"
        continue
    }

    $zipPath   = Join-Path $Cache ("{0}-{1}.zip" -f $component.Name, $component.Version)
    $extractTo = Join-Path $Cache ("x-" + $component.Name)
    if (Test-Path $extractTo) { Remove-Item $extractTo -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force

    # Archive layouts differ per project, so search rather than assume a path.
    $found = Get-ChildItem $extractTo -Recurse -Filter $component.Exe -File |
             Select-Object -First 1
    if (-not $found) {
        throw "$($component.Exe) was not found inside the $($component.Name) archive"
    }

    if ($component.Kind -eq 'bundle') {
        # Copy the whole tree that sits beside the exe, not just the exe. Some
        # tools ship sidecar runtimes they resolve relative to their own path.
        Copy-Item (Join-Path $found.Directory.FullName '*') $Bin -Recurse -Force
        $extras = Get-ChildItem $found.Directory.FullName -Directory |
                  Select-Object -ExpandProperty Name
        if ($extras) {
            Write-Ok "$($component.Exe) -> bin\  (plus $($extras -join ', '))"
        }
        else {
            Write-Ok "$($component.Exe) -> bin\"
        }
    }
    else {
        Copy-Item $found.FullName $destination -Force
        Write-Ok "$($component.Exe) -> bin\"
    }
}

# ---------------------------------------------------------------------------
# 3. Windows Terminal in portable mode
# ---------------------------------------------------------------------------
Write-Step 'Setting up Windows Terminal in portable mode'

$wtDir = Join-Path $Bin 'WindowsTerminal'
$wtExe = Join-Path $wtDir 'WindowsTerminal.exe'

if ((Test-Path $wtExe) -and -not $Force) {
    Write-Ok 'Windows Terminal already extracted'
}
else {
    $wtComponent = $Manifest | Where-Object { $_.Kind -eq 'wt' }
    $zipPath     = Join-Path $Cache ("{0}-{1}.zip" -f $wtComponent.Name, $wtComponent.Version)
    $extractTo   = Join-Path $Cache 'x-wt'
    if (Test-Path $extractTo) { Remove-Item $extractTo -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force

    $sourceExe = Get-ChildItem $extractTo -Recurse -Filter 'WindowsTerminal.exe' -File |
                 Select-Object -First 1
    if (-not $sourceExe) { throw 'WindowsTerminal.exe was not found inside the archive' }

    New-Item -ItemType Directory -Force -Path $wtDir | Out-Null
    Copy-Item (Join-Path $sourceExe.Directory.FullName '*') $wtDir -Recurse -Force
    Write-Ok 'Windows Terminal -> bin\WindowsTerminal\'
}

# The .portable marker is what redirects settings to a folder next to the exe
# instead of %LOCALAPPDATA%. This is what keeps the bundle from touching the
# Windows Terminal you already have installed.
# Source: learn.microsoft.com/en-us/windows/terminal/distributions
$portableMarker = Join-Path $wtDir '.portable'
if (-not (Test-Path $portableMarker)) {
    New-Item -ItemType File -Path $portableMarker | Out-Null
}
Write-Ok '.portable marker in place (settings stay inside this folder)'

$wtSettingsDir = Join-Path $wtDir 'settings'
New-Item -ItemType Directory -Force -Path $wtSettingsDir | Out-Null

# The versioned settings file carries a __BUNDLE__ token so it stays
# machine-independent. The runtime copy gets absolute paths, which is what lets
# the console work when someone launches WindowsTerminal.exe directly instead of
# going through Start-AgentConsole.ps1.
$settingsTemplate = Get-Content (Join-Path $Root 'platform\windows\wt-settings.json') -Raw
$settingsRendered = $settingsTemplate.Replace('__BUNDLE__', $Root.Replace('\', '\\'))

# Not Set-Content -Encoding UTF8: under Windows PowerShell 5.1 that writes a
# BOM, and a BOM in settings.json is a JSON parse error for strict readers.
$noBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $wtSettingsDir 'settings.json'),
                               $settingsRendered, $noBom)

Write-Ok "settings.json installed, bundle root resolved to $Root"

# ---------------------------------------------------------------------------
# 4. Font, current user only, no admin
# ---------------------------------------------------------------------------
if ($SkipFont) {
    Write-Step 'Skipping font install (-SkipFont)'
}
else {
    Write-Step 'Installing JetBrainsMono Nerd Font for the current user'

    $fontDir    = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $fontRegKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    if (-not (Test-Path $fontRegKey)) { New-Item -Path $fontRegKey -Force | Out-Null }

    $fontComponent = $Manifest | Where-Object { $_.Kind -eq 'font' }
    $zipPath       = Join-Path $Cache ("{0}-{1}.zip" -f $fontComponent.Name, $fontComponent.Version)
    $extractTo     = Join-Path $Cache 'x-font'
    if (Test-Path $extractTo) { Remove-Item $extractTo -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force

    # The archive carries roughly 50 faces. A terminal uses four.
    $wantedFaces = @(
        'JetBrainsMonoNerdFont-Regular.ttf'
        'JetBrainsMonoNerdFont-Bold.ttf'
        'JetBrainsMonoNerdFont-Italic.ttf'
        'JetBrainsMonoNerdFont-BoldItalic.ttf'
    )

    $installedCount = 0
    foreach ($face in $wantedFaces) {
        $file = Get-ChildItem $extractTo -Recurse -Filter $face -File | Select-Object -First 1
        if (-not $file) {
            Write-Note "not present in archive: $face"
            continue
        }
        $target = Join-Path $fontDir $file.Name
        Copy-Item $file.FullName $target -Force
        Set-ItemProperty -Path $fontRegKey -Name "$($file.BaseName) (TrueType)" -Value $target
        $installedCount++
    }

    Write-Ok "$installedCount font faces registered under HKCU (reversible, see Uninstall.ps1)"
    if ($installedCount -eq 0) {
        Write-Note 'No faces installed. The console will render icons as empty boxes.'
    }
}

# ---------------------------------------------------------------------------
# 5. Report
# ---------------------------------------------------------------------------
Write-Step 'Done'
Write-Host ''
Write-Host '  bin\ contents:' -ForegroundColor Cyan
Get-ChildItem $Bin -File | ForEach-Object {
    Write-Host ('    {0,-22} {1,8:N0} KB' -f $_.Name, ($_.Length / 1KB))
}
if (Test-Path $wtDir) {
    $wtSize = (Get-ChildItem $wtDir -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
    Write-Host ('    {0,-22} {1,8:N1} MB' -f 'WindowsTerminal\', $wtSize)
}
Write-Host ''
Write-Host '  Next:' -ForegroundColor Cyan
Write-Host '    .\Start-AgentConsole.ps1           personal profile (your ~/.claude loads)'
Write-Host '    .\Start-AgentConsole.ps1 -Clean    isolated profile (nothing personal loads)'
Write-Host ''
