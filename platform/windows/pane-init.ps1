<#
.SYNOPSIS
  What each Agent Console pane runs. Configures its own environment, then
  starts herdr.

.DESCRIPTION
  This script deliberately does not assume it was launched by
  Start-AgentConsole.ps1. It derives the bundle root from its own location and
  sets everything itself, so double-clicking bin\WindowsTerminal\WindowsTerminal.exe
  gives you the same working console as the launcher does.

  Environment set here is process-scoped and dies with the pane.

  A diagnostic line is appended to bin\pane-init.log on every launch. That log
  is the first place to look when a pane opens and immediately sits at a bare
  prompt.
#>
[CmdletBinding()]
param(
    # Drop to a shell instead of starting herdr. Used by the escape-hatch profile.
    [switch]$NoHerdr,

    # Isolate Claude Code from the personal configuration.
    #
    # This is a parameter and not an inherited environment variable on purpose.
    # Windows Terminal starts a profile's command line with a fresh environment
    # rather than the one held by whatever launched WindowsTerminal.exe, so
    # nothing exported by Start-AgentConsole.ps1 survives the hop. Verified:
    # CLAUDE_CONFIG_DIR set by the launcher arrived here unset.
    #
    # Each mode therefore gets its own Windows Terminal profile, and the profile
    # carries the flag on its command line.
    [switch]$Clean
)

# platform\windows\pane-init.ps1 -> bundle root is two levels up.
$BundleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Bin        = Join-Path $BundleRoot 'bin'
$LogFile    = Join-Path $Bin 'pane-init.log'

$env:PATH = "$Bin;$env:PATH"

# The committed config carries a __BUNDLE__ token so it is machine-independent.
# Render it now, every launch, so edits to the template apply immediately.
$env:HERDR_CONFIG_PATH = & (Join-Path $PSScriptRoot 'Build-HerdrConfig.ps1') -BundleRoot $BundleRoot

# Clean mode is established here, not by the launcher, because this is the first
# process in the chain that Windows Terminal did not strip the environment from.
if ($Clean) {
    $cleanProfile = Join-Path $BundleRoot 'config\claude'
    if (-not (Test-Path $cleanProfile)) {
        New-Item -ItemType Directory -Force -Path $cleanProfile | Out-Null
    }
    $env:CLAUDE_CONFIG_DIR = $cleanProfile
}

$herdrExe = Join-Path $Bin 'herdr.exe'

$diagnostic = [ordered]@{
    time        = (Get-Date).ToString('s')
    bundleRoot  = $BundleRoot
    herdrExists = Test-Path $herdrExe
    conptyExists= Test-Path (Join-Path $Bin 'conpty\conpty.dll')
    configExists= Test-Path $env:HERDR_CONFIG_PATH
    claudeDir   = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { '(personal ~/.claude)' }
    psVersion   = $PSVersionTable.PSVersion.ToString()
    session     = if ($env:CLAUDE_CONFIG_DIR) { 'clean' } else { 'default' }
    noHerdr     = [bool]$NoHerdr
}
try {
    ($diagnostic.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ' |
        Add-Content -Path $LogFile -Encoding UTF8
}
catch { }   # a read-only bundle must still start

if ($NoHerdr) { return }

if (-not (Test-Path $herdrExe)) {
    Write-Host "herdr.exe not found at $herdrExe" -ForegroundColor Red
    Write-Host 'Run bootstrap.ps1 -Force from the bundle root.' -ForegroundColor Yellow
    return
}

if (-not (Test-Path (Join-Path $Bin 'conpty\conpty.dll'))) {
    Write-Host 'conpty\conpty.dll is missing next to herdr.exe.' -ForegroundColor Red
    Write-Host 'herdr will start and exit instantly without it.' -ForegroundColor Yellow
    Write-Host 'Run bootstrap.ps1 -Force from the bundle root.' -ForegroundColor Yellow
    return
}

# Personal and clean mode must not share a herdr session.
#
# herdr's server is persistent and the panes it spawns inherit the environment
# the SERVER started with, not the one the client has now. Attaching a clean
# client to a server that was started in personal mode therefore produces panes
# with no CLAUDE_CONFIG_DIR: the isolation silently does nothing while appearing
# to work, which is the worst possible failure for a compliance feature.
#
# A named session gets its own directory, socket and server process, so the two
# modes cannot contaminate each other. Verified: `herdr session list` shows one
# row per session, each with its own socket.
$herdrArgs = @()
if ($env:CLAUDE_CONFIG_DIR) { $herdrArgs = @('--session', 'clean') }

# Call the exe by full path rather than relying on PATH resolution.
& $herdrExe @herdrArgs

# herdr has exited. Leave the reason on screen instead of closing the pane,
# because closeOnExit would otherwise hide whatever it printed.
Write-Host ''
Write-Host "herdr exited with code $LASTEXITCODE" -ForegroundColor DarkGray
Write-Host "diagnostics: $LogFile" -ForegroundColor DarkGray
