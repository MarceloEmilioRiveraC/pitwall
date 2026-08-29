<#
.SYNOPSIS
    Claude Code status line: what this session is costing and how close the plan
    is to its limit.

.DESCRIPTION
    Registered through bin\claude-hooks.json, which startup-once.ps1 generates
    and passes with --settings, so nothing is written to the user's ~/.claude.

    Claude Code sends a JSON payload on stdin and prints whatever this writes.
    The fields used here are documented: cost.total_cost_usd,
    context_window.used_percentage, and rate_limits.five_hour / seven_day.

    What is deliberately NOT shown: the git branch and the working directory.
    herdr's sidebar already carries both, and duplicating the sidebar in a
    second place is the mistake that got herdr-sidebar removed (PLAN.md
    section 12). This shows only what nothing else on screen knows.

    `esc` is here because configuring any status line makes Claude Code drop
    most of its footer key hints, including "esc to interrupt". Four characters
    buy that back.

    A status line runs on every render, so this stays cheap and never throws:
    a failure prints one plain line rather than breaking the footer.
#>
[CmdletBinding()]
param()

$ESC = [char]27
function Paint([string]$text, [string]$colour) { "$ESC[${colour}m$text$ESC[0m" }

try {
    $payload = [Console]::In.ReadToEnd()
    if (-not $payload) { return }
    $state = $payload | ConvertFrom-Json

    $parts = @()

    # Which model, because it is settable per session and easy to lose track of.
    $model = $state.model.display_name
    if ($model) { $parts += Paint $model '38;5;110' }

    # Context. The number that decides whether to keep going or start fresh.
    $used = $state.context_window.used_percentage
    if ($null -ne $used) {
        $u = [int][math]::Round([double]$used)
        $colour = if ($u -ge 85) { '38;5;203' } elseif ($u -ge 70) { '38;5;179' } else { '38;5;245' }
        $parts += Paint ("ctx {0}%" -f $u) $colour
    }

    # What this session has cost so far. Client-side estimate at list price.
    $cost = $state.cost.total_cost_usd
    if ($null -ne $cost) { $parts += Paint ('${0:N2}' -f [double]$cost) '38;5;245' }

    # The plan limits. This is the whole reason the status line exists: with
    # several sessions running against one plan, the wall arrives without
    # warning and there is nowhere else on screen that says how close it is.
    foreach ($window in @(
        @{ Key = 'five_hour'; Label = '5h' },
        @{ Key = 'seven_day'; Label = 'wk' }
    )) {
        $limit = $state.rate_limits.($window.Key)
        if ($null -eq $limit -or $null -eq $limit.used_percentage) { continue }
        $p = [int][math]::Round([double]$limit.used_percentage)
        $colour = if ($p -ge 80) { '38;5;203' } elseif ($p -ge 60) { '38;5;179' } else { '38;5;245' }
        $parts += Paint ("{0} {1}%" -f $window.Label, $p) $colour
    }

    $parts += Paint 'esc interrupt' '38;5;240'

    ($parts -join (Paint ' | ' '38;5;238'))
}
catch {
    'pitwall status line unavailable'
}
