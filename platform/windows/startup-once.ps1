<#
.SYNOPSIS
  Brings the console up ready to work: the right-hand panel open and the agent
  already running.

.DESCRIPTION
  pane-init.ps1 starts this detached, immediately before it hands the pane to
  herdr. Two jobs, both once per launch:

    1. Start the agent in the work pane, so the console opens ON the thing you
       came to do rather than at a shell prompt waiting to be told.
    2. Open the file viewer, so the panel is there instead of something you
       split by hand every single time.

  Four things make this less trivial than it looks. Three of them were found by
  the launch coming up wrong, not by reading.

  A. herdr has no startup-layout config. `[session]` only resumes AGENTS across
     a server restart, so both jobs have to be driven through the CLI once the
     server answers.

  B. A RESTORED SESSION LIES ABOUT ITS PANES. herdr persists the layout, so
     tabs, pane ids and pane LABELS all survive a restart while the processes
     inside them do not. A pane still labelled "Files" from yesterday is a
     corpse: the label is there, the viewer is not. Trusting the label meant the
     helper saw "Files" and skipped, so the user got a dead pane with a
     PowerShell prompt in it and no file viewer. The plugin's own
     `--launch-decision` does not help here, it answers CLOSE for the corpse
     because it reasons from the same label. Liveness has to come from
     somewhere the restart cannot fake, so it comes from the process table.

  C. THE FOCUSED TAB IS NOT THE FIRST TAB. A restored session can hold several
     tabs, and picking the first unlabelled pane in the whole list typed the
     agent's name into a pane in a background tab, where nothing was visible.
     Work has to be scoped to the tab the user is actually looking at.

  D. TYPING INTO A SHELL THAT HAS NOT DRAWN A PROMPT LOSES THE TEXT SILENTLY.
     A fixed sleep is a guess that is too short on a cold start and wasted on a
     warm one, so this waits for a prompt to appear and gives up rather than
     firing blind.

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
    # this at a different agent is the only change needed to swap it.
    [string]$Agent = 'claude',

    # Give up after this long. The server normally answers in two or three.
    [int]$TimeoutSeconds = 40
)

$ErrorActionPreference = 'SilentlyContinue'

# Everything here runs detached and hidden, so a silent failure is invisible and
# the only symptom is a console that came up wrong. Making it legible first is
# the whole reason this log exists: two launches failed with no way to tell
# whether the helper had run at all.
$logFile = Join-Path $BundleRoot 'bin\startup-once.log'
function Note([string]$msg) {
    try {
        "$((Get-Date).ToString('HH:mm:ss'))  $msg" | Add-Content -Path $logFile -Encoding UTF8
    } catch { }
}
Note "--- launch: session='$Session' agent='$Agent' ---"

$herdr = Join-Path $BundleRoot 'bin\herdr.exe'
if (-not (Test-Path $herdr)) { Note "ABORT: no herdr.exe at $herdr"; return }

if (-not $env:HERDR_CONFIG_PATH) {
    $env:HERDR_CONFIG_PATH = Join-Path $BundleRoot 'bin\herdr-config.toml'
}

$sessionArgs = @()
if ($Session) { $sessionArgs = @('--session', $Session) }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

function Get-Panes {
    $raw = & $herdr @sessionArgs pane list 2>&1 | Out-String
    if ($raw -notmatch '"pane_id"') { return $null }
    try { return ($raw | ConvertFrom-Json).result.panes } catch { return $null }
}

# 1. Wait for the server to report running.
$up = $false
while ((Get-Date) -lt $deadline) {
    $status = & $herdr @sessionArgs status 2>&1 | Out-String
    if ($status -match 'status:\s*running') { $up = $true; break }
    Start-Sleep -Milliseconds 500
}
if (-not $up) { Note 'ABORT: server never reported running'; return }
Note 'server up'

# 2. Wait for the client to have created its pane.
$panes = $null
while ((Get-Date) -lt $deadline) {
    $panes = Get-Panes
    if ($panes) { break }
    Start-Sleep -Milliseconds 500
}
if (-not $panes) { Note 'ABORT: no panes appeared'; return }

# The tab the user is looking at.
#
# NOT the focused pane. This runs before the client has attached, so at that
# moment focus may not be established anywhere and the fallback picked the
# FIRST tab, which on a restored multi-tab session is a background one. The
# agent then got typed into a pane nobody could see. The server's own
# active_tab_id is set from the restored session and is right immediately.
$tabId = $null
$wsRaw = & $herdr @sessionArgs workspace list 2>&1 | Out-String
try {
    $ws = ($wsRaw | ConvertFrom-Json).result.workspaces
    $active = $ws | Where-Object { $_.focused } | Select-Object -First 1
    if (-not $active) { $active = $ws | Select-Object -First 1 }
    if ($active) { $tabId = $active.active_tab_id }
} catch { }
if (-not $tabId) {
    $focused = $panes | Where-Object { $_.focused } | Select-Object -First 1
    $tabId = if ($focused) { $focused.tab_id } else { ($panes | Select-Object -First 1).tab_id }
}
Note "active tab = $tabId; panes = $(($panes | ForEach-Object { $_.pane_id + '(' + $_.tab_id + ',' + $(if($_.label){$_.label}else{'shell'}) + ')' }) -join ' ')"

# 3. Start the agent, if one is wanted and none is already running.
if ($Agent) {
    $running = & $herdr @sessionArgs agent list 2>&1 | Out-String
    if ($running -match '"agent"\s*:') {
        Note 'agent: one is already running, leaving it alone'
    }
    else {
        # The work pane: unlabelled (herdr and its plugins label what they
        # create) and in the tab the user can actually see.
        $shell = $panes |
                 Where-Object { -not $_.label -and $_.tab_id -eq $tabId } |
                 Select-Object -First 1

        if (-not $shell) {
            Note "agent: NO unlabelled pane in $tabId, nothing to type into"
        }
        else {
            # Note D: wait for a prompt rather than guessing at a sleep.
            $ready = $false
            while ((Get-Date) -lt $deadline) {
                $screen = & $herdr @sessionArgs pane read $shell.pane_id --source visible 2>&1 | Out-String
                if ($screen -match '(?m)^\s*PS\s+.*>' -or $screen -match '(?m)^\s*[A-Za-z]:\\.*>') {
                    $ready = $true; break
                }
                Start-Sleep -Milliseconds 500
            }
            if (-not $ready) {
                Note "agent: pane $($shell.pane_id) never drew a prompt before the deadline"
            }
            else {
                & $herdr @sessionArgs pane send-text $shell.pane_id $Agent 2>&1 | Out-Null
                & $herdr @sessionArgs pane send-keys $shell.pane_id 'Enter' 2>&1 | Out-Null
                Note "agent: typed '$Agent' into $($shell.pane_id)"
            }
        }
    }
}

# 4. The file viewer.
#
# Note B: a "Files" label proves nothing after a restart, so ask what is
# actually running inside the pane. A live viewer pane has herdr-file-viewer as
# its foreground process; a corpse has the shell wrapper, which is exactly what
# the restored pane that started this investigation reported:
#
#   cmd.exe /c ...\agent-shell.cmd     <- corpse, still labelled "Files"
#
# Per pane rather than the global process table, so a viewer running in the
# OTHER session (clean mode has its own) cannot make this one look alive.
#
# NOT `pane process-info`, which was the obvious choice and is wrong.
# It reports only the pane's TOP process, and every pane in this bundle is
# `cmd.exe /c agent-shell.cmd` whatever is running underneath, so a live viewer
# reports exactly the same string as a corpse. It reads as a working check
# because it answers correctly for the corpse, and answers correctly there for
# the wrong reason.
#
# What actually separates them is on screen. A corpse is a pane sitting at a
# shell prompt; a live viewer is a TUI painting a box-drawing frame and never
# leaving a prompt as its last line. Both halves are needed: box-drawing alone
# says "alive" for the agent pane too, because Claude Code draws boxes as well.
#
# Only ever called on panes already labelled Files, which is what keeps this
# narrow enough to be reliable.
function Test-ViewerAlive([string]$paneId) {
    $screen = & $herdr @sessionArgs pane read $paneId --source visible 2>&1 | Out-String
    if ($screen -notmatch '[─-╿]') { return $false }
    $last = ($screen -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
    return -not ($last -match '(?:PS\s+)?[A-Za-z]:\\[^>]*>\s*$')
}

$panes = Get-Panes
if (-not $panes) { Note 'viewer: ABORT, pane list went away'; return }
$filesPanes = @($panes | Where-Object { $_.label -eq 'Files' })

if ($filesPanes | Where-Object { Test-ViewerAlive $_.pane_id }) {
    Note 'viewer: a live one is already open, leaving it alone'
    return   # the action is a toggle, invoking would close it
}

$corpse = $filesPanes | Where-Object { $_.tab_id -eq $tabId } | Select-Object -First 1

if ($corpse) {
    # REUSE the corpse instead of closing it and splitting a new one.
    #
    # Closing and reopening worked, and looked terrible. The restored layout
    # already shows a Files pane, so the user watched two panes appear, the
    # right one vanish, the agent stretch across the whole window, and a new
    # right pane slide back in, several seconds later. Three layout changes to
    # arrive where it started.
    #
    # The pane is fine. Only the process inside it died with the last server.
    # Starting the viewer in the pane that is already there is one layout
    # change instead of three, and it skips the plugin's launcher, which
    # shells out to `herdr plugin list --json` and back before it splits
    # anything.
    #
    # HERDR_PLUGIN_CONFIG_DIR has to be set in the typed command. herdr injects
    # it only into panes IT spawns from the manifest, and the plugin's own
    # launcher passes it with `pane split --env`, which is not available when
    # reusing a pane. Without it the viewer lands on a relative config path,
    # refuses to read it, and silently drops this bundle's renderer and colour
    # settings.
    $viewerExe = $null
    $pluginJson = & $herdr @sessionArgs plugin list --json 2>&1 | Out-String
    try {
        $root = (($pluginJson | ConvertFrom-Json).result.plugins |
                 Where-Object { $_.plugin_id -eq 'herdr-file-viewer' }).plugin_root
        if ($root -and $root.StartsWith('\\?\')) { $root = $root.Substring(4) }
        if ($root) { $viewerExe = Join-Path $root 'target\release\herdr-file-viewer.exe' }
    } catch { }

    if ($viewerExe -and (Test-Path $viewerExe)) {
        $cfgDir = (& $herdr @sessionArgs plugin config-dir herdr-file-viewer 2>&1 | Out-String).Trim()
        if ($cfgDir -and $cfgDir.StartsWith('\\?\')) { $cfgDir = $cfgDir.Substring(4) }

        # Quotes escaped so they survive Windows PowerShell's native-argument
        # stripping and reach herdr intact, same trick the plugin's launcher
        # uses. A bare path breaks on any bundle under a directory with a space.
        $run = if ($cfgDir) {
            "`$env:HERDR_PLUGIN_CONFIG_DIR='$cfgDir'; & `"$viewerExe`""
        } else {
            "& `"$viewerExe`""
        }
        & $herdr @sessionArgs pane run $corpse.pane_id $run 2>&1 | Out-Null
        Note "viewer: reused $($corpse.pane_id) in place, no close and no split"
    }
    else {
        Note 'viewer: could not resolve the viewer exe, falling back to the plugin action'
        & $herdr @sessionArgs pane close $corpse.pane_id 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        & $herdr @sessionArgs plugin action invoke herdr-file-viewer.open-file-viewer-windows 2>&1 | Out-Null
    }
}
else {
    # Nothing to reuse: let the plugin split one the normal way.
    $r = & $herdr @sessionArgs plugin action invoke herdr-file-viewer.open-file-viewer-windows 2>&1 | Out-String
    Note "viewer: no pane to reuse, invoked open action, reply $(if($r -match '\"error\"'){'ERROR: ' + $r.Trim()}else{'ok'})"
}

# Corpses in OTHER tabs would otherwise pile up one per launch.
foreach ($other in ($filesPanes | Where-Object { $_.tab_id -ne $tabId })) {
    Note "viewer: closing stale pane $($other.pane_id) in background tab $($other.tab_id)"
    & $herdr @sessionArgs pane close $other.pane_id 2>&1 | Out-Null
}

Start-Sleep -Seconds 10
$live = @((Get-Panes) | Where-Object { $_.label -eq 'Files' -and (Test-ViewerAlive $_.pane_id) })
Note "viewer: live viewer panes = $($live.Count)"
Note '--- done ---'
