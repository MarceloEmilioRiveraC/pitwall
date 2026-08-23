<#
.SYNOPSIS
  Launches the portable agent console.

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
  .\Start-AgentConsole.ps1

.EXAMPLE
  .\Start-AgentConsole.ps1 -Clean

.EXAMPLE
  .\Start-AgentConsole.ps1 -WorkDir C:\dev\Exposoft
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
$HerdrConfig = Join-Path $Root 'config\herdr\config.toml'

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if (-not (Test-Path $WtExe)) {
    Write-Host 'The bundle is not built yet.' -ForegroundColor Yellow
    Write-Host 'Run this first:' -ForegroundColor Yellow
    Write-Host '  powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1' -ForegroundColor Cyan
    exit 1
}

$missing = @('herdr.exe', 'lazygit.exe') |
           Where-Object { -not (Test-Path (Join-Path $Bin $_)) }
if ($missing) {
    Write-Host "Missing from bin\: $($missing -join ', ')" -ForegroundColor Yellow
    Write-Host 'Re-run bootstrap.ps1 -Force' -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $HerdrConfig)) {
    throw "herdr config not found at $HerdrConfig"
}

if (-not $WorkDir) { $WorkDir = Split-Path $Root -Parent }
if (-not (Test-Path $WorkDir)) { throw "WorkDir does not exist: $WorkDir" }

# ---------------------------------------------------------------------------
# Session-scoped environment. Nothing here outlives the launched window.
# ---------------------------------------------------------------------------

# Bundle binaries win over anything installed system-wide.
$env:PATH = "$Bin;$env:PATH"

# Redirect herdr away from %APPDATA%\herdr onto the bundle config.
$env:HERDR_CONFIG_PATH = $HerdrConfig

$mode = 'personal'
if ($Clean) {
    $cleanProfile = Join-Path $Root 'config\claude'
    New-Item -ItemType Directory -Force -Path $cleanProfile | Out-Null

    # Verified behaviour: with this set, Claude Code stores settings, session
    # history and plugins here, and keeps its own sign-in. Your ~/.claude is
    # neither read nor written.
    $env:CLAUDE_CONFIG_DIR = $cleanProfile
    $mode = 'clean (isolated Claude profile, separate login)'
}

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  agent console' -ForegroundColor Cyan
Write-Host "    mode      $mode"
Write-Host "    workdir   $WorkDir"
Write-Host "    herdr cfg $HerdrConfig"
if ($Clean) { Write-Host "    claude    $env:CLAUDE_CONFIG_DIR" }
Write-Host ''
Write-Host '    ctrl+b f      file viewer (tree left, diff right)' -ForegroundColor DarkGray
Write-Host '    ctrl+b alt+g  lazygit' -ForegroundColor DarkGray
Write-Host '    ctrl+b ?      every keybinding' -ForegroundColor DarkGray
Write-Host ''

Start-Process -FilePath $WtExe `
              -ArgumentList @('--startingDirectory', $WorkDir) `
              -WorkingDirectory $WorkDir
