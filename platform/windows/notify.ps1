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

    # With six sessions open, WHICH one is the only thing the toast has to
    # answer. The leaf of cwd is the cheapest honest answer.
    $body = if ($hookEvent.cwd) { Split-Path -Leaf $hookEvent.cwd } else { '' }

    $herdr = Join-Path $BundleRoot 'bin\herdr.exe'
    if (-not (Test-Path $herdr)) { exit 0 }

    & $herdr notification show $match.Title --body $body --sound $match.Sound 2>&1 | Out-Null
}
catch { }

exit 0
