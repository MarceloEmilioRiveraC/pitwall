<#
.SYNOPSIS
  Removes the two things this bundle creates outside its own folder: the
  per-user Nerd Font, and herdr's own data directory.

.DESCRIPTION
  Everything else lives inside .\bin and is removed by deleting this folder.
  This script exists for the two exceptions:

    1. Font registration writes to HKCU and to
       %LOCALAPPDATA%\Microsoft\Windows\Fonts.

    2. herdr keeps its plugins, server socket and logs in %APPDATA%\herdr,
       and offers no environment variable to relocate them. HERDR_CONFIG_PATH
       moves config.toml and nothing else. Verified on herdr 0.8.2 by probing
       HERDR_DATA_DIR, HERDR_DATA_PATH, HERDR_PLUGIN_DIR, HERDR_HOME and
       XDG_DATA_HOME, none of which changed the reported plugin directory.

  Your system Windows Terminal and your ~/.claude are never touched, because
  the bundle never writes to them in the first place.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1 -RemoveHerdrData -RemoveBinaries
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Also delete .\bin (downloaded binaries and cache).
    [switch]$RemoveBinaries,

    # Also delete %APPDATA%\herdr (herdr plugins, logs, session state).
    # Left out by default because you may use herdr outside this bundle too.
    [switch]$RemoveHerdrData
)

$ErrorActionPreference = 'Stop'

$Root       = $PSScriptRoot
$fontDir    = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$fontRegKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

Write-Host '==> Removing per-user JetBrainsMono Nerd Font' -ForegroundColor Cyan

$removed = 0
if (Test-Path $fontRegKey) {
    $entries = Get-Item $fontRegKey
    foreach ($name in $entries.GetValueNames()) {
        if ($name -notlike 'JetBrainsMonoNerdFont*') { continue }

        $path = $entries.GetValue($name)
        if ($PSCmdlet.ShouldProcess($name, 'remove font registration')) {
            Remove-ItemProperty -Path $fontRegKey -Name $name -ErrorAction SilentlyContinue
            if ($path -and (Test-Path $path)) {
                Remove-Item $path -Force -ErrorAction SilentlyContinue
            }
            $removed++
        }
    }
}
Write-Host "    $removed font registrations removed" -ForegroundColor Green
if ($removed -gt 0) {
    Write-Host '    Sign out and back in for Windows to forget the font entirely.' -ForegroundColor Yellow
}

$herdrData = Join-Path $env:APPDATA 'herdr'
if ($RemoveHerdrData) {
    if (Test-Path $herdrData) {
        Write-Host '==> Removing %APPDATA%\herdr' -ForegroundColor Cyan
        Write-Host '    Stopping any running herdr server first' -ForegroundColor DarkGray
        $herdrExe = Join-Path $Root 'bin\herdr.exe'
        if (Test-Path $herdrExe) {
            & $herdrExe server stop 2>$null | Out-Null
        }
        if ($PSCmdlet.ShouldProcess($herdrData, 'delete')) {
            Remove-Item $herdrData -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host '    %APPDATA%\herdr deleted' -ForegroundColor Green
        }
    }
}
elseif (Test-Path $herdrData) {
    Write-Host '==> Left in place: %APPDATA%\herdr' -ForegroundColor Yellow
    Write-Host '    herdr keeps plugins, logs and its socket there and cannot be'
    Write-Host '    pointed elsewhere. Re-run with -RemoveHerdrData to delete it.'
}

if ($RemoveBinaries) {
    $bin = Join-Path $Root 'bin'
    if (Test-Path $bin) {
        Write-Host '==> Removing bin\' -ForegroundColor Cyan
        if ($PSCmdlet.ShouldProcess($bin, 'delete')) {
            Remove-Item $bin -Recurse -Force
            Write-Host '    bin\ deleted' -ForegroundColor Green
        }
    }
}

Write-Host ''
Write-Host 'Done. To finish, delete this folder.' -ForegroundColor Cyan
Write-Host 'Untouched, as always: your system Windows Terminal and your ~/.claude'
