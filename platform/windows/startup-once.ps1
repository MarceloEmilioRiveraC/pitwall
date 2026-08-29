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

# Quote a path for a command string that is about to be handed to herdr and
# TYPED into a pane's PowerShell.
#
# Single quotes, and this was measured rather than chosen for taste. A command
# string containing double quotes does not survive Windows PowerShell 5.1's
# native-argument passing, which is the host pane-init.ps1 launches this under:
#
#   intended (one argument):  claude --settings "C:\my bundle\...\hooks.json"
#   what the exe received:    ['claude --settings C:\my',
#                              'bundle\...\hooks.json']
#
# Two arguments, no quotes. herdr accepts the stray second one without a usage
# error, so the pane silently gets a truncated path and the agent exits. PS 7
# passes the same string intact, which is why this never showed up in testing:
# the bundle lives at C:\dev\pitwall and has no space in it.
#
# Single quotes survive as one argument, and PowerShell in the pane treats them
# as a literal path, which is what a path wants. Doubling handles the rare path
# that contains a quote of its own.
function Quote([string]$path) { "'" + $path.Replace("'", "''") + "'" }

$herdr = Join-Path $BundleRoot 'bin\herdr.exe'
if (-not (Test-Path $herdr)) { Note "ABORT: no herdr.exe at $herdr"; return }

if (-not $env:HERDR_CONFIG_PATH) {
    $env:HERDR_CONFIG_PATH = Join-Path $BundleRoot 'bin\herdr-config.toml'
}

$sessionArgs = @()
if ($Session) { $sessionArgs = @('--session', $Session) }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

# Desktop toasts when the agent is blocked or done, without touching the user's
# own ~/.claude. Claude Code's --settings takes ADDITIONAL settings from a path,
# so the bundle carries its hooks in bin\ and the personal profile is untouched
# in both default and -Clean mode. Returns the flag to append, or '' when there
# is nothing to add, so the caller stays one line.
#
# Claude-Code-shaped on purpose: hook names and the settings schema are its own.
# A different agent gets an empty string and the same bare command as before,
# which keeps $Agent swappable the way the parameter promises.
function Get-AgentSettingsArgs {
    param([string]$BundleRoot, [string]$Agent)

    if ($Agent -notmatch '(^|[\\/])claude(\.exe|\.cmd)?$') { return '' }

    $run = { param($leaf, $extra)
        $s = Join-Path $BundleRoot "platform\windows\$leaf"
        if (Test-Path $s) { 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $s, $extra } else { $null }
    }

    $settings = @{}

    # Notification and Stop both raise the same toast: the agent wants you.
    $notify = & $run 'notify.ps1' (' -BundleRoot "{0}"' -f $BundleRoot)
    if ($notify) {
        $entry = @(@{ hooks = @(@{ type = 'command'; command = $notify }) })
        $settings.hooks = @{ Notification = $entry; Stop = $entry }
    }

    # Cost, context and how close the plan is to its limit. Nothing else on
    # screen knows any of it.
    $status = & $run 'statusline.ps1' ''
    if ($status) { $settings.statusLine = @{ type = 'command'; command = $status; padding = 0 } }

    if ($settings.Count -eq 0) { return '' }

    $path = Join-Path $BundleRoot 'bin\claude-hooks.json'
    try {
        # bin\ is generated, not committed, so it is not guaranteed to be here.
        # Without this the write throws and the hooks are skipped in silence,
        # which is how the check that guards this branch first failed.
        $dir = Split-Path -Parent $path
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

        # WriteAllText, not Set-Content: under PowerShell 5.1 `-Encoding UTF8`
        # writes a BOM, and a BOM in a config file has already cost this repo a
        # day once. See PLAN.md section 8.
        [System.IO.File]::WriteAllText($path, ($settings | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        Note "settings: could not write $path, starting the agent without them"
        return ''
    }

    Note "settings: $($settings.Keys -join ', ') at $path"
    return " --settings $(Quote $path)"
}

# An agent that outlived a change to its own command line is stale, and the only
# honest signal is its actual command line. herdr reports the foreground process
# of a pane, so ask it rather than inferring from timestamps.
#
# Says nothing when everything is fine, and nothing when it cannot tell. A false
# "restart your agent" is worse than silence, because it trains you to ignore it.
function Test-AgentIsCurrent {
    param([string]$Herdr, [string[]]$SessionArgs, [string]$BundleRoot)

    $hooks = Join-Path $BundleRoot 'bin\claude-hooks.json'
    if (-not (Test-Path $hooks)) { return }

    try {
        $agents = (& $Herdr @SessionArgs agent list 2>$null | ConvertFrom-Json).result.agents
        foreach ($agent in $agents) {

            # ONLY claude. Get-AgentSettingsArgs deliberately withholds
            # --settings from every other agent kind, so a codex, gemini or
            # opencode pane can never carry the marker and would trip this
            # warning on every single launch, forever, about a pane where
            # notifications were never intended. A warning that cannot be
            # satisfied is worse than no warning: it teaches you to ignore the
            # one that matters.
            if ($agent.agent -ne 'claude') { continue }

            $info = & $Herdr @SessionArgs pane process-info --pane $agent.pane_id 2>$null | ConvertFrom-Json
            $cmdlines = @($info.result.process_info.foreground_processes | ForEach-Object { $_.cmdline })
            if (-not $cmdlines) { continue }

            # Match on the file name, not the full path: the bundle can be moved
            # and the running agent would still be carrying the old absolute one.
            if ($cmdlines -match 'claude-hooks\.json') { continue }

            Note "agent: $($agent.pane_id) predates the notification hooks, telling the user"
            $reply = & $Herdr @SessionArgs notification show 'Notifications are off in the running agent' `
                --body 'It started before they were set up. Quit it and relaunch to turn them on.' `
                --sound request 2>&1 | Out-String

            # herdr answers `shown` plus a reason, and there are four ways this
            # quietly does nothing: disabled, rate_limited, no_foreground_client,
            # busy. Discarding the reply logged "telling the user" for a message
            # nobody saw.
            if ($reply -notmatch '"shown"\s*:\s*true') {
                $why = if ($reply -match '"reason"\s*:\s*"([^"]+)"') { $Matches[1] } else { 'no verdict' }
                Note "agent: the warning was NOT shown, herdr said '$why'"
            }
            return
        }
    }
    catch {
        Note "agent: stale-agent check failed, $($_.Exception.Message)"
    }
}

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

        # Leaving it alone is right: it may be mid-task, and typing into a pane
        # that already has an agent is how you lose someone's work. But herdr's
        # session outlives the launcher, so an agent started before a change to
        # its command line keeps running WITHOUT that change, indefinitely, and
        # nothing anywhere says so. That cost a launch that looked broken and
        # was not: the notification hooks were generated correctly and the agent
        # predating them never saw them.
        #
        # So say it, once, where it will actually be read.
        Test-AgentIsCurrent -Herdr $herdr -SessionArgs $sessionArgs -BundleRoot $BundleRoot
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
                $command = $Agent + (Get-AgentSettingsArgs -BundleRoot $BundleRoot -Agent $Agent)
                & $herdr @sessionArgs pane send-text $shell.pane_id $command 2>&1 | Out-Null
                & $herdr @sessionArgs pane send-keys $shell.pane_id 'Enter' 2>&1 | Out-Null
                Note "agent: typed '$command' into $($shell.pane_id)"
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

        # Single-quoted, see the Quote helper above. The double-quoted form that
        # was here does not survive PowerShell 5.1's native-argument passing and
        # broke on any bundle path containing a space.
        $run = if ($cfgDir) {
            "`$env:HERDR_PLUGIN_CONFIG_DIR=$(Quote $cfgDir); & $(Quote $viewerExe)"
        } else {
            "& $(Quote $viewerExe)"
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
