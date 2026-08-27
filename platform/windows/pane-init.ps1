<#
.SYNOPSIS
  What each pitwall pane runs. Configures its own environment, then
  starts herdr.

.DESCRIPTION
  This script deliberately does not assume it was launched by
  Start-Pitwall.ps1. It derives the bundle root from its own location and
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
    # nothing exported by Start-Pitwall.ps1 survives the hop. Verified:
    # CLAUDE_CONFIG_DIR set by the launcher arrived here unset.
    #
    # Each mode therefore gets its own Windows Terminal profile, and the profile
    # carries the flag on its command line.
    [switch]$Clean,

    # Agent to start automatically in the work pane. Empty starts nothing.
    #
    # On the command line for the same reason -Clean is: Windows Terminal hands
    # a profile a fresh environment, so this cannot be inherited. Point a
    # profile at a different value ('gemini', 'codex', 'opencode', ...) to run
    # a different agent in the same console; herdr detects whichever one is
    # running from its terminal title.
    [string]$Agent = 'claude'
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

# Come up ready to work: the right-hand panel open and the agent already
# running, instead of one bare pane you have to split and then type into on
# every single launch. herdr has no startup-layout config, so this is a
# detached helper that waits for the server the line below starts and then does
# both, once. See platform\windows\startup-once.ps1 for why the agent is typed
# rather than started with `herdr agent start`.
# The argument list is built conditionally, and that is not style.
#
# Passing '-Session', '' for the default session silently broke the whole
# thing. PowerShell drops the empty string when it renders the command line, so
# the child saw `-Session -Agent claude`: it bound `-Agent` as the VALUE of
# -Session, found `claude` positional, failed parameter binding, and died
# before its first line ran. The console came up with no agent and no panel,
# and because the process is detached and hidden there was nothing anywhere to
# say so. Only ever append a switch that has something to carry.
$startupArgs = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'startup-once.ps1'),
    '-BundleRoot', $BundleRoot
)
if ($env:CLAUDE_CONFIG_DIR) { $startupArgs += @('-Session', 'clean') }
if ($Agent)                 { $startupArgs += @('-Agent', $Agent) }

try {
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $startupArgs | Out-Null
}
catch { }   # the console must start even if the panel cannot

# Call the exe by full path rather than relying on PATH resolution.
#
# The loop is the no-dead-ends rule, and it is here because of a real failure:
# herdr exiting for ANY reason (ctrl+b q to detach, closing the last pane, a
# crash) used to drop you at a bare PowerShell prompt that looked like a broken
# console and gave no hint that the whole thing was one word away. Someone who
# does not already know the command has no way back from there, which is the
# difference between an application and a terminal that happened to run one.
#
# This cannot spin: Read-Host always waits for a human, so a herdr that dies
# instantly asks once and waits rather than relaunching in a tight loop. The
# exit code stays on screen either way.
while ($true) {
    & $herdrExe @herdrArgs
    $exitCode = $LASTEXITCODE

    Write-Host ''
    Write-Host "  pitwall closed. herdr exit code $exitCode" -ForegroundColor DarkGray
    Write-Host "  diagnostics: $LogFile" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  [Enter] reopen pitwall     [q] stay at a PowerShell prompt' -ForegroundColor Cyan

    if ((Read-Host '  >') -match '^\s*[qQ]') {
        Write-Host ''
        Write-Host '  Run .\Start-Pitwall.ps1 from the bundle root to come back.' -ForegroundColor DarkGray
        break
    }
}
