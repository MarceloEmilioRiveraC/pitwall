<#
.SYNOPSIS
  Opens the file viewer once, after the herdr server is ready.

.DESCRIPTION
  pane-init.ps1 starts this detached, immediately before it hands the pane to
  herdr, so the console comes up with the right-hand panel already there
  instead of one bare pane you have to split by hand every launch.

  Three things make this less trivial than it looks.

  1. herdr has no startup-layout config. There is no key that says "open these
     panes". `[session]` only resumes AGENTS across a server restart, so the
     panel has to be opened by driving the CLI once the server answers.

  2. The viewer's action is a TOGGLE, not an open. Its own launcher documents
     the cycle: no Files pane in the tab opens one, an unfocused Files pane
     gets focused, and a FOCUSED Files pane is CLOSED. herdr's server is
     persistent, so re-attaching to a session where the viewer was already
     open and focused would close the very panel this script exists to open.
     That is why it checks for a Files pane and does nothing when one exists,
     rather than relying on the action being idempotent.

  3. The server is not up when the pane starts. It is started by the herdr
     client that pane-init.ps1 launches a moment later, so this polls instead
     of sleeping a fixed guess.

  Failing is not an error. If the server never answers, the viewer just is not
  open and ctrl+b f still works, so this exits quietly rather than printing
  into a console the user is about to start working in.
#>
[CmdletBinding()]
param(
    # Bundle root, passed explicitly so this does not depend on the caller's cwd.
    [Parameter(Mandatory)][string]$BundleRoot,

    # herdr session name. Clean mode runs its own session, see pane-init.ps1.
    [string]$Session,

    # Give up after this long. The server normally answers in two or three.
    [int]$TimeoutSeconds = 25
)

$ErrorActionPreference = 'SilentlyContinue'

$herdr = Join-Path $BundleRoot 'bin\herdr.exe'
if (-not (Test-Path $herdr)) { return }

if (-not $env:HERDR_CONFIG_PATH) {
    $env:HERDR_CONFIG_PATH = Join-Path $BundleRoot 'bin\herdr-config.toml'
}

$sessionArgs = @()
if ($Session) { $sessionArgs = @('--session', $Session) }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

# 1. Wait for the server to report running.
$up = $false
while ((Get-Date) -lt $deadline) {
    $status = & $herdr @sessionArgs status 2>&1 | Out-String
    if ($status -match 'status:\s*running') { $up = $true; break }
    Start-Sleep -Milliseconds 500
}
if (-not $up) { return }

# 2. Wait for the client to have created its pane. Invoking the action before
#    there is a pane to split gives the plugin nothing to attach to.
$panes = ''
while ((Get-Date) -lt $deadline) {
    $panes = & $herdr @sessionArgs pane list 2>&1 | Out-String
    if ($panes -match '"pane_id"') { break }
    Start-Sleep -Milliseconds 500
}
if ($panes -notmatch '"pane_id"') { return }

# 3. Already open somewhere? Leave it alone. See note 2 in the header: this is
#    the difference between opening the panel and closing the user's.
if ($panes -match '"label"\s*:\s*"Files"') { return }

& $herdr @sessionArgs plugin action invoke herdr-file-viewer.open-file-viewer-windows 2>&1 | Out-Null
