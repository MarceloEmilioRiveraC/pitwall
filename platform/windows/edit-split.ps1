<#
.SYNOPSIS
  Opens the editor in a pane BESIDE the file viewer instead of on top of it.

.DESCRIPTION
  PROTOTYPE. The stock behaviour is platform\windows\edit.cmd: the viewer
  suspends itself, micro takes over the same pane, and the file tree is gone
  until you quit. That is fine for one quick edit and wrong for the thing you
  actually do, which is read a diff, change something, and look at the next
  file. To switch back, point `editor` in the file viewer's config.toml at
  edit.cmd again.

  How it works. herdr's `pane run` TYPES its command into the target pane's
  shell rather than exec'ing it, which is the whole reason this can work:

    1. Split the focused pane (the viewer's, since `e` was pressed there)
       downward, so the tree keeps its full width and only loses height.
    2. Type a call to edit.cmd into the new pane, followed by `exit`, so the
       pane CLOSES when micro quits and the viewer grows back on its own. A
       pane left sitting at a prompt would be exactly the kind of dead end
       this bundle is trying to remove.
    3. Return immediately. The viewer un-suspends and redraws the tree while
       micro is still opening beside it.

  It reuses edit.cmd rather than calling micro.exe directly so MICRO_CONFIG_HOME
  and COLORTERM stay in one place.

  If ANY of that fails it falls through to running edit.cmd in this pane, which
  is the stock behaviour. `e` never becoming a dead key matters more than the
  split.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BundleRoot,

    # The file path, appended by the viewer. Taken as remaining arguments so an
    # unquoted path containing spaces is rejoined rather than truncated.
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Path
)

$ErrorActionPreference = 'SilentlyContinue'

$file    = ($Path -join ' ').Trim('"')
$herdr   = Join-Path $BundleRoot 'bin\herdr.exe'
$editCmd = Join-Path $BundleRoot 'platform\windows\edit.cmd'

function Invoke-InThisPane {
    & $editCmd $file
    exit $LASTEXITCODE
}

if (-not (Test-Path $herdr) -or -not (Test-Path $editCmd) -or -not $file) {
    Invoke-InThisPane
}

# Split the pane the viewer is in. No pane id: herdr splits the FOCUSED pane,
# which is the viewer's, because `e` was just pressed in it.
#
# down, not right: the terminal is 171 columns and the work pane and viewer
# already share them. Another vertical split would put the viewer under the 80
# columns it needs to show a tree and content side by side, which is the whole
# problem this layout was fixed to avoid. Height is the cheap axis here.
$cwd = Split-Path $file -Parent
if (-not $cwd -or -not (Test-Path $cwd)) { $cwd = $BundleRoot }

$out = & $herdr pane split --direction down --ratio 0.55 --cwd $cwd --focus 2>&1 | Out-String
if ($out -notmatch '"pane_id"\s*:\s*"([^"]+)"') { Invoke-InThisPane }
$pane = $Matches[1]

# `& "<path>"` with the quotes escaped so they survive Windows PowerShell 5.1's
# native-argument quote stripping and reach herdr intact. A bare path breaks on
# any bundle installed under a directory with a space in it. Same trick the file
# viewer's own launcher uses, and for the same reason.
& $herdr pane run $pane "& `"$editCmd`" `"$file`"; exit" | Out-Null
& $herdr pane rename $pane 'edit' 2>&1 | Out-Null
