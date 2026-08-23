<#
.SYNOPSIS
  Launches the portable pitwall.

.DESCRIPTION
  Sets three environment variables for this launch only, then starts the
  portable Windows Terminal that lives in .\bin. Nothing is written to the
  registry, to %APPDATA%, or to your system Windows Terminal.

  Personal mode (default)
      Claude Code reads your usual ~/.claude: your plugins, your CLAUDE.md,
      your statusline, your login.

  Clean mode (-Clean)
      Claude Code reads .\config\claude instead. No personal plugins, no
      personal CLAUDE.md, and a separate login. Use it for client work and
      anything you screen-share.

.EXAMPLE
  .\Start-Pitwall.ps1

.EXAMPLE
  .\Start-Pitwall.ps1 -Clean

.EXAMPLE
  .\Start-Pitwall.ps1 -WorkDir C:\dev\Exposoft
#>
[CmdletBinding()]
param(
    # Isolate Claude Code from your personal configuration.
    [switch]$Clean,

    # Directory the console opens in. Defaults to the parent of this bundle.
    [string]$WorkDir
)

$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$Bin  = Join-Path $Root 'bin'
$WtExe = Join-Path $Bin 'WindowsTerminal\WindowsTerminal.exe'
$HerdrTemplate = Join-Path $Root 'config\herdr\config.toml'

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if (-not (Test-Path $WtExe)) {
    Write-Host 'The bundle is not built yet.' -ForegroundColor Yellow
    Write-Host 'Run this first:' -ForegroundColor Yellow
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1' -ForegroundColor Cyan
    exit 1
}

# conpty\conpty.dll is listed deliberately. herdr ships its own ConPTY runtime
# and, without it, starts and exits instantly leaving a bare prompt and no log.
# Catching it here beats letting the pane fail silently.
$missing = @('herdr.exe', 'lazygit.exe', 'conpty\conpty.dll') |
           Where-Object { -not (Test-Path (Join-Path $Bin $_)) }
if ($missing) {
    Write-Host "Missing from bin\: $($missing -join ', ')" -ForegroundColor Yellow
    Write-Host 'Re-run bootstrap.ps1 -Force' -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $HerdrTemplate)) {
    throw "herdr config template not found at $HerdrTemplate"
}

if (-not $WorkDir) { $WorkDir = Split-Path $Root -Parent }
if (-not (Test-Path $WorkDir)) { throw "WorkDir does not exist: $WorkDir" }

# ---------------------------------------------------------------------------
# Session-scoped environment. Nothing here outlives the launched window.
# ---------------------------------------------------------------------------

# Render the herdr config so the token is resolved before anything reads it.
# platform\windows\pane-init.ps1 renders it again inside the pane, which is the
# copy that actually counts. This one is for herdr CLI calls made from here.
$env:PATH = "$Bin;$env:PATH"
$renderedConfig = & (Join-Path $Root 'platform\windows\Build-HerdrConfig.ps1') -BundleRoot $Root
$env:HERDR_CONFIG_PATH = $renderedConfig

# Which mode runs is decided by which Windows Terminal profile is launched, not
# by an environment variable.
#
# Windows Terminal starts a profile's command line with a fresh environment
# rather than inheriting from whatever launched WindowsTerminal.exe. Verified:
# CLAUDE_CONFIG_DIR exported here arrived unset inside the pane, so an
# environment-based switch would have reported "clean" while loading the
# personal profile. For a compliance feature that failure mode is unacceptable,
# so the flag travels on the profile's command line where it cannot be lost.
if ($Clean) {
    $profileName = 'pitwall (clean)'
    $mode        = 'clean (isolated Claude profile, own herdr session, separate login)'
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'config\claude') | Out-Null
}
else {
    $profileName = 'pitwall'
    $mode        = 'personal (your ~/.claude)'
}

# Select the profile by GUID, not by name. Windows Terminal's command line does
# not reliably accept a --profile name containing spaces and parentheses once it
# has been through argument quoting, and it silently opens a default tab instead
# of reporting the problem. Reading the guid out of the rendered settings keeps
# a single source of truth.
$runtimeSettings = Join-Path $Bin 'WindowsTerminal\settings\settings.json'
$profileGuid = $null
if (Test-Path $runtimeSettings) {
    $parsed = Get-Content $runtimeSettings -Raw | ConvertFrom-Json
    $profileGuid = ($parsed.profiles.list | Where-Object { $_.name -eq $profileName }).guid
}
if (-not $profileGuid) {
    throw "Profile '$profileName' not found in $runtimeSettings. Run bootstrap.ps1 -Force."
}

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  pitwall' -ForegroundColor Cyan
Write-Host "    mode      $mode"
Write-Host "    profile   $profileName  $profileGuid"
Write-Host "    workdir   $WorkDir"
Write-Host "    herdr cfg $renderedConfig"
if ($Clean) { Write-Host "    claude    $(Join-Path $Root 'config\claude')" }
Write-Host ''
Write-Host '    ctrl+b f      file viewer (tree left, diff right)' -ForegroundColor DarkGray
Write-Host '    ctrl+b alt+g  lazygit' -ForegroundColor DarkGray
Write-Host '    ctrl+b ?      every keybinding' -ForegroundColor DarkGray
Write-Host ''

Start-Process -FilePath $WtExe `
              -ArgumentList @(
                  'new-tab',
                  '--profile', $profileGuid,
                  '--startingDirectory', $WorkDir
              ) `
              -WorkingDirectory $WorkDir
