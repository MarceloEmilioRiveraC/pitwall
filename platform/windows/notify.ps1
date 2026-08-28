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
    exits 0 without printing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleRoot
)

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
    if (-not $payload) { exit 0 }
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
    if (-not $match) { exit 0 }

    $herdr = Join-Path $BundleRoot 'bin\herdr.exe'
    if (-not (Test-Path $herdr)) { exit 0 }

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

    & $herdr notification show $match.Title --body $body --sound $match.Sound 2>&1 | Out-Null
}
catch { }

exit 0
