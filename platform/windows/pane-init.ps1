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
    [switch]$NoHerdr
)

# platform\windows\pane-init.ps1 -> bundle root is two levels up.
$BundleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Bin        = Join-Path $BundleRoot 'bin'
$LogFile    = Join-Path $Bin 'pane-init.log'

$env:PATH              = "$Bin;$env:PATH"
$env:HERDR_CONFIG_PATH = Join-Path $BundleRoot 'config\herdr\config.toml'

# CLAUDE_CONFIG_DIR is intentionally not set here. Start-AgentConsole.ps1 -Clean
# sets it before launching, and this script must not override that choice, nor
# invent it when the user asked for their personal profile.

$herdrExe = Join-Path $Bin 'herdr.exe'

$diagnostic = [ordered]@{
    time        = (Get-Date).ToString('s')
    bundleRoot  = $BundleRoot
    herdrExists = Test-Path $herdrExe
    conptyExists= Test-Path (Join-Path $Bin 'conpty\conpty.dll')
    configExists= Test-Path $env:HERDR_CONFIG_PATH
    claudeDir   = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { '(personal ~/.claude)' }
    psVersion   = $PSVersionTable.PSVersion.ToString()
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

# Call the exe by full path rather than relying on PATH resolution.
& $herdrExe

# herdr has exited. Leave the reason on screen instead of closing the pane,
# because closeOnExit would otherwise hide whatever it printed.
Write-Host ''
Write-Host "herdr exited with code $LASTEXITCODE" -ForegroundColor DarkGray
Write-Host "diagnostics: $LogFile" -ForegroundColor DarkGray
