<#
.SYNOPSIS
  Brings the console up ready to work: the right-hand panel open and the agent
  already running.

.DESCRIPTION
  pane-init.ps1 starts this detached, immediately before it hands the pane to
  herdr. Two jobs, both once per launch:

    1. Open the file viewer, so the panel is there instead of something you
       split by hand every single time.
    2. Start the agent in the work pane, so the console opens ON the thing you
       came to do rather than at a shell prompt waiting to be told.

  Three things make this less trivial than it looks.

  A. herdr has no startup-layout config. There is no key that says "open these
     panes and run this". `[session]` only resumes AGENTS across a server
     restart, so both jobs have to be driven through the CLI once the server
     answers.

  B. The viewer's action is a TOGGLE, not an open. Its own launcher documents
     the cycle: no Files pane in the tab opens one, an unfocused Files pane
     gets focused, and a FOCUSED Files pane is CLOSED. herdr's server is
     persistent, so re-attaching to a session where the viewer was already
     open and focused would close the very panel this exists to open. Hence
     the check for an existing Files pane rather than trusting idempotency.

  C. The agent is TYPED into the pane, not started with `herdr agent start`.
     That is deliberate and was measured, not assumed. `herdr agent start`
     refuses this bundle's panes with `agent_pane_busy: not an available
     shell`, because [terminal] default_shell points at agent-shell.cmd and
     herdr does not recognise a cmd wrapper as a shell it can drive. Swapping
     the wrapper for plain pwsh.exe makes `agent start` work and simultaneously
     loses delta, bat, glow and lazygit inside panes, which is the whole reason
     the wrapper exists. Typing the command sidesteps the conflict entirely:
     herdr detects the agent from the terminal title either way. Verified, the
     agent shows up as claude / idle / "✳ Claude Code" with the wrapper intact.

  Failing is not an error. If the server never answers you simply get a plain
  console, and ctrl+b f still opens the panel, so this exits quietly rather
  than printing into a pane the user is about to work in.
#>
[CmdletBinding()]
param(
    # Bundle root, passed explicitly so this does not depend on the caller's cwd.
    [Parameter(Mandatory)][string]$BundleRoot,

    # herdr session name. Clean mode runs its own session, see pane-init.ps1.
    [string]$Session,

    # The agent to start in the work pane. Empty string starts nothing and
    # leaves you at a shell prompt.
    #
    # This is a plain command name on purpose. herdr can drive 22 agent kinds
    # (claude, codex, gemini, cursor, opencode, copilot, qwen and more) and
    # detects whichever one is running from its terminal title, so pointing
    # this at a different agent is the only change needed to swap it. The
    # Windows Terminal profile carries the value, the same way it carries
    # -Clean, because Windows Terminal starts a profile with a fresh
    # environment and nothing exported by the launcher survives the hop.
    [string]$Agent = 'claude',

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

# 2. Wait for the client to have created its pane.
$panes = ''
while ((Get-Date) -lt $deadline) {
    $panes = & $herdr @sessionArgs pane list 2>&1 | Out-String
    if ($panes -match '"pane_id"') { break }
    Start-Sleep -Milliseconds 500
}
if ($panes -notmatch '"pane_id"') { return }

# 3. Start the agent in the work pane, if one is wanted and none is running.
#
# The work pane is the one with no label: herdr and its plugins label the panes
# they create ("Files", "edit"), and picking the first pane in the list instead
# would type the command into whichever panel happened to sort first. That
# exact assumption is what broke the self test once already.
if ($Agent) {
    $running = & $herdr @sessionArgs agent list 2>&1 | Out-String
    if ($running -notmatch '"agent"\s*:') {
        $shell = ($panes | ConvertFrom-Json).result.panes |
                 Where-Object { -not $_.label } | Select-Object -First 1
        if ($shell) {
            # Give the wrapper time to reach an interactive prompt. Typing into
            # a shell that has not drawn one yet loses the command silently.
            Start-Sleep -Seconds 3
            & $herdr @sessionArgs pane send-text $shell.pane_id $Agent 2>&1 | Out-Null
            & $herdr @sessionArgs pane send-keys $shell.pane_id 'Enter' 2>&1 | Out-Null
        }
    }
}

# 4. Open the viewer, unless one is already there. See note B in the header:
#    this is the difference between opening the panel and closing the user's.
if ($panes -match '"label"\s*:\s*"Files"') { return }

& $herdr @sessionArgs plugin action invoke herdr-file-viewer.open-file-viewer-windows 2>&1 | Out-Null
