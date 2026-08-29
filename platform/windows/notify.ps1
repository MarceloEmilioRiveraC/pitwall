<#
.SYNOPSIS
    Claude Code hook body: raise a toast when the agent wants you.

.DESCRIPTION
    Fed by the Notification and Stop hooks in bin\claude-hooks.json, which
    startup-once.ps1 generates and passes to the agent with --settings.

    There is deliberately no toast code here. herdr already ships
    `notification show`, and [ui.toast] delivery in config.toml decides whether
    that lands in-app or as a Windows toast. Writing our own would mean either
    BurntToast (an install, which the bundle does not do) or the WinRT
    projection, which PowerShell 7 dropped.

    Claude Code passes the hook payload as JSON on stdin. The fields used here
    are documented: hook_event_name and cwd.

    A hook must never break the agent it is attached to, so every failure path
    exits 0 without printing. Exiting quietly is not the same as vanishing,
    though: this is the most invisible script in the bundle, run by the agent
    rather than by a launcher, so every path also leaves one line in
    bin\startup-once.log. Without it there are five ways to produce silence
    (empty stdin, an unhandled event, no herdr.exe, a swallowed exception, and
    a toast herdr declined to show) and no way to tell them apart.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleRoot
)

# Shares startup-once.ps1's log on purpose: one file to ask for when a launch
# looks wrong, rather than two that each hold half the story.
function Note([string]$msg) {
    try {
        "$((Get-Date).ToString('HH:mm:ss'))  notify: $msg" |
            Add-Content -Path (Join-Path $BundleRoot 'bin\startup-once.log') -Encoding ascii
    } catch { }
}

# The sidebar identifies work by WORKSPACE, so that is the name worth putting in
# a toast: it is what you are already looking at when you glance left.
#
# Neither of the two obvious alternatives works. herdr leaves the agent pane
# unlabelled (only the viewer pane carries a label), and the file viewer renames
# the whole TAB to whatever it is previewing, so a tab label reads
# "README.md - preview" rather than naming the project. See PLAN.md section 12.
#
# HERDR_PANE_ID is set by herdr in every pane it spawns and is inherited here.
# `herdr pane current` is NOT a substitute: from outside a pane it answers with
# whichever pane has FOCUS, so it would confidently name the wrong session.
function Get-WorkspaceLabel([string]$HerdrExe) {
    if (-not $env:HERDR_PANE_ID) { return '' }
    try {
        $pane = & $HerdrExe pane get $env:HERDR_PANE_ID 2>$null | ConvertFrom-Json
        $workspaceId = $pane.result.pane.workspace_id
        if (-not $workspaceId) { return '' }

        $all = & $HerdrExe workspace list 2>$null | ConvertFrom-Json
        $match = $all.result.workspaces | Where-Object { $_.workspace_id -eq $workspaceId }
        return [string]$match.label
    }
    catch { return '' }
}

try {
    $payload = [Console]::In.ReadToEnd()
    if (-not $payload) { Note 'empty stdin, nothing to do'; exit 0 }
    $hookEvent = $payload | ConvertFrom-Json

    # Only two events are worth interrupting somebody for: the agent is blocked
    # waiting on a decision, or it has stopped and there is something to read.
    # Everything else in the 31-event surface is noise for this purpose, and a
    # toast you learn to ignore is worse than no toast.
    $known = @{
        'Notification' = @{ Title = 'Claude needs you';   Sound = 'request' }
        'Stop'         = @{ Title = 'Claude is finished'; Sound = 'done'    }
    }
    $match = $known[[string]$hookEvent.hook_event_name]
    if (-not $match) { Note "ignoring event '$($hookEvent.hook_event_name)'"; exit 0 }

    $herdr = Join-Path $BundleRoot 'bin\herdr.exe'
    if (-not (Test-Path $herdr)) { Note "no herdr.exe at $herdr"; exit 0 }

    # With six sessions open, WHICH one is the only thing the toast has to
    # answer. Two names are available and neither is reliably the better one:
    # the workspace is what the sidebar shows, the folder is where the work
    # actually happened, and under a git worktree they differ. So show the
    # workspace, and add the folder only when it says something new. When herdr
    # cannot be asked, the folder alone is still a true answer.
    $folder = if ($hookEvent.cwd) { Split-Path -Leaf $hookEvent.cwd } else { '' }
    $workspace = Get-WorkspaceLabel $herdr

    $body =
        if (-not $workspace)            { $folder }
        elseif (-not $folder)           { $workspace }
        elseif ($workspace -eq $folder) { $workspace }
        else                            { "$workspace ($folder)" }

    # herdr answers `shown` plus a reason, and it can be false four ways:
    # disabled, rate_limited, no_foreground_client, busy. Discarding the reply
    # made a toast nobody saw indistinguishable from one that worked.
    $reply = & $herdr notification show $match.Title --body $body --sound $match.Sound 2>&1 | Out-String
    # Three outcomes, not two. Treating "did not say false" as success would
    # log a delivered toast when herdr answered with an error and never said
    # `shown` at all, which is the same defect this logging exists to remove.
    if ($reply -match '"shown"\s*:\s*true') {
        Note "'$($match.Title)' shown for '$body'"
    }
    elseif ($reply -match '"shown"\s*:\s*false') {
        $why = if ($reply -match '"reason"\s*:\s*"([^"]+)"') { $Matches[1] } else { 'unknown' }
        Note "'$($match.Title)' was NOT shown, herdr said '$why'"
    }
    else {
        Note "'$($match.Title)' got no verdict from herdr: $(($reply -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1))"
    }
}
catch {
    Note "failed: $($_.Exception.Message)"
}

exit 0
