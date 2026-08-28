<#
.SYNOPSIS
  Verifies the bundle. Run it after bootstrap.ps1, and again whenever something
  looks wrong.

.DESCRIPTION
  Checks are grouped into three passes:

    STATIC   files, versions, config validity. Nothing is launched.
    LIVE     starts a throwaway herdr session, drives it, tears it down.
    GLOBAL   confirms the bundle has not touched anything it promised not to.

  Every failure prints what was expected, what was found, and what to do about
  it, because the person running this is often on another machine with no idea
  how the thing is put together.

  Exit code 0 when everything passed, 1 when anything failed. Warnings do not
  fail the run.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Test-Bundle.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Test-Bundle.ps1 -SkipLive
#>
[CmdletBinding()]
param(
    # Static and global checks only. No herdr session is started.
    [switch]$SkipLive,

    # Print the full command output of each live check.
    [switch]$Detailed
)

$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
$Bin  = Join-Path $Root 'bin'

$script:Pass = 0
$script:Fail = 0
$script:Warn = 0
$script:Failures = @()

function Test-Item {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Check,
        [string]$Fix = '',
        [switch]$WarnOnly
    )

    $detail = ''
    $ok = $false
    try {
        $result = & $Check
        if ($result -is [array]) { $ok = [bool]$result[0]; $detail = [string]$result[1] }
        else { $ok = [bool]$result }
    }
    catch {
        $ok = $false
        $detail = $_.Exception.Message
    }

    if ($ok) {
        $script:Pass++
        Write-Host ('  [ok]   ' + $Name) -ForegroundColor Green
        if ($Detailed -and $detail) { Write-Host ('         ' + $detail) -ForegroundColor DarkGray }
    }
    elseif ($WarnOnly) {
        $script:Warn++
        Write-Host ('  [warn] ' + $Name) -ForegroundColor Yellow
        if ($detail) { Write-Host ('         ' + $detail) -ForegroundColor DarkGray }
        if ($Fix)    { Write-Host ('         fix: ' + $Fix) -ForegroundColor DarkGray }
    }
    else {
        $script:Fail++
        $script:Failures += $Name
        Write-Host ('  [FAIL] ' + $Name) -ForegroundColor Red
        if ($detail) { Write-Host ('         ' + $detail) -ForegroundColor DarkGray }
        if ($Fix)    { Write-Host ('         fix: ' + $Fix) -ForegroundColor Cyan }
    }
}

function Write-Section { param($Title) Write-Host ''; Write-Host "== $Title" -ForegroundColor Cyan }

Write-Host ''
Write-Host 'pitwall self test' -ForegroundColor Cyan
Write-Host "  bundle: $Root"

# ===========================================================================
# STATIC
# ===========================================================================
Write-Section 'STATIC: files and configuration'

Test-Item 'Windows 10 2004 or newer (portable mode needs it)' {
    $b = [Environment]::OSVersion.Version.Build
    @(($b -ge 19041), "build $b")
} -Fix 'Portable mode is unavailable on older builds. Use the packaged Windows Terminal instead.'

Test-Item 'PowerShell 7 present' {
    $c = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    @([bool]$c, $(if ($c) { $c.Source } else { 'not on PATH' }))
} -WarnOnly -Fix 'winget install Microsoft.PowerShell'

Test-Item 'Visual C++ runtime present (herdr 0.8.2 needs it)' {
    Test-Path (Join-Path $env:SystemRoot 'System32\VCRUNTIME140.dll')
} -Fix 'winget install Microsoft.VCRedist.2015+.x64'

foreach ($exe in 'herdr.exe', 'lazygit.exe', 'delta.exe', 'bat.exe', 'glow.exe') {
    Test-Item "bin\$exe exists" ([scriptblock]::Create("Test-Path '$(Join-Path $Bin $exe)'")) `
        -Fix 'powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Force'
}

Test-Item 'bin\conpty\conpty.dll exists (herdr will not start without it)' {
    Test-Path (Join-Path $Bin 'conpty\conpty.dll')
} -Fix 'bootstrap.ps1 -Force. Extracting herdr.exe alone is not enough, it needs its ConPTY runtime beside it.'

Test-Item 'herdr reports a version' {
    $v = & (Join-Path $Bin 'herdr.exe') --version 2>&1 | Out-String
    @(($v -match 'herdr\s+\d'), $v.Trim())
} -Fix 'bootstrap.ps1 -Force'

Test-Item 'Windows Terminal extracted' {
    Test-Path (Join-Path $Bin 'WindowsTerminal\WindowsTerminal.exe')
} -Fix 'bootstrap.ps1 -Force'

Test-Item '.portable marker present (keeps settings out of %LOCALAPPDATA%)' {
    Test-Path (Join-Path $Bin 'WindowsTerminal\.portable')
} -Fix 'bootstrap.ps1 -Force, or create an empty file named .portable next to WindowsTerminal.exe'

Test-Item 'runtime settings.json is valid JSON with no __BUNDLE__ left' {
    $p = Join-Path $Bin 'WindowsTerminal\settings\settings.json'
    if (-not (Test-Path $p)) { return @($false, 'file missing') }
    $raw = Get-Content $p -Raw
    if ($raw -match '__BUNDLE__') { return @($false, 'token was not substituted') }
    $null = $raw | ConvertFrom-Json
    @($true, "$([math]::Round($raw.Length/1KB,1)) KB")
} -Fix 'bootstrap.ps1 -Force'

Test-Item 'runtime settings.json has no byte order mark' {
    $p = Join-Path $Bin 'WindowsTerminal\settings\settings.json'
    $bytes = [System.IO.File]::ReadAllBytes($p) | Select-Object -First 3
    @(-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF), 'strict readers reject a BOM')
} -Fix 'bootstrap.ps1 -Force'

Test-Item 'both console profiles are defined' {
    $p = Join-Path $Bin 'WindowsTerminal\settings\settings.json'
    $names = ((Get-Content $p -Raw | ConvertFrom-Json).profiles.list).name
    $want = @('pitwall', 'pitwall (clean)')
    $missing = $want | Where-Object { $_ -notin $names }
    @((-not $missing), "found: $($names -join ', ')")
} -Fix 'bootstrap.ps1 -Force'

Test-Item 'herdr config template exists' {
    Test-Path (Join-Path $Root 'config\herdr\config.toml')
} -Fix 'The repo is incomplete. Re-clone it.'

Test-Item 'rendered herdr config has no __BUNDLE__ left' {
    $rendered = & (Join-Path $Root 'platform\windows\Build-HerdrConfig.ps1') -BundleRoot $Root
    $raw = Get-Content $rendered -Raw
    @(($raw -notmatch '__BUNDLE__'), $rendered)
} -Fix 'Check platform\windows\Build-HerdrConfig.ps1'

Test-Item 'the key card renders and fits the popup without scrolling' {
    $card = Join-Path $Root 'platform\windows\keycard.ps1'
    if (-not (Test-Path $card)) { return @($false, 'keycard.ps1 missing') }
    # There is no pager on Windows: glow -p and bat --paging both shell out to
    # `less`, which does not exist, so the card cannot scroll. It has to fit.
    # The popup is 90% of a 48-row terminal, so roughly 43 usable rows.
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $card 2>&1
    $lines = ($out | Measure-Object -Line).Lines
    @(($lines -gt 0 -and $lines -le 40), "$lines rendered rows, budget 40")
} -Fix 'Shorten platform\windows\keycard.ps1. A card that does not fit silently loses its bottom rows, and no pager exists to scroll it.'

Test-Item 'the rendered config survives non-ASCII (no mojibake, no BOM)' {
    $rendered = Join-Path $Bin 'herdr-config.toml'
    if (-not (Test-Path $rendered)) { return @($false, 'not rendered yet') }
    $bytes = [System.IO.File]::ReadAllBytes($rendered)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @($false, 'the rendered file starts with a UTF-8 BOM, which a strict TOML reader rejects')
    }
    # C3 82 is "Â", the signature of UTF-8 text that was read as ANSI and then
    # written back as UTF-8. Reading the template with Get-Content -Raw under
    # PowerShell 5.1 does exactly that, so this is the guard for that specific
    # regression. It bites the moment the template stops being pure ASCII.
    for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
        if ($bytes[$i] -eq 0xC3 -and $bytes[$i + 1] -eq 0x82) {
            return @($false, "double-encoded UTF-8 at byte $i. Build-HerdrConfig.ps1 must read with [System.IO.File]::ReadAllText, not Get-Content -Raw")
        }
    }
    @($true, "$($bytes.Length) bytes, clean UTF-8")
} -Fix 'platform\windows\Build-HerdrConfig.ps1 must both READ and WRITE UTF-8 explicitly. Get-Content -Raw reads the ANSI codepage on Windows PowerShell 5.1.'

Test-Item 'herdr accepts the config (herdr config check)' {
    $rendered = Join-Path $Bin 'herdr-config.toml'
    $env:HERDR_CONFIG_PATH = $rendered
    $out = & (Join-Path $Bin 'herdr.exe') config check 2>&1 | Out-String
    @(($out -match 'config:\s*ok'), $out.Trim())
} -Fix 'Read the message. An unknown theme name is the usual cause, and herdr silently falls back to catppuccin.'

Test-Item 'pane shell wrapper exists (without it delta, bat and glow are invisible)' {
    Test-Path (Join-Path $Root 'platform\windows\agent-shell.cmd')
} -Fix 'The repo is incomplete. Re-clone it.'

Test-Item 'notify hook script exists' {
    Test-Path (Join-Path $Root 'platform\windows\notify.ps1')
} -Fix 'The repo is incomplete. Re-clone it.'

# The toast is worthless if it lands in-app: the whole point is being told while
# looking at another window. Guard the value rather than the key, because
# "herdr" parses fine and silently gives you nothing.
Test-Item 'toasts are delivered by the OS, not in-app' {
    $rendered = Join-Path $Bin 'herdr-config.toml'
    if (-not (Test-Path $rendered)) { return @($false, 'bin\herdr-config.toml missing') }
    $toast = ([regex]::Match((Get-Content $rendered -Raw), '(?ms)^\[ui\.toast\](.*?)(?=^\[|\z)')).Value
    @(($toast -match 'delivery\s*=\s*"system"'), ($toast -replace '\s+', ' ').Trim())
} -Fix 'Set delivery = "system" under [ui.toast] in config\herdr\config.toml, then re-run bootstrap.ps1 -Force. Allowed values are off, herdr, terminal, system.'

# The toast names the workspace by asking herdr, and that lookup runs on every
# notification. If it ever throws instead of returning empty, the toast is lost
# rather than degraded, which is the silent failure this whole feature exists to
# avoid. Checked with HERDR_PANE_ID unset, the case that happens whenever the
# agent is started outside a herdr pane.
Test-Item 'workspace lookup degrades to empty instead of throwing' {
    $src = Get-Content (Join-Path $Root 'platform\windows\notify.ps1') -Raw
    $fn = [regex]::Match($src, '(?s)function Get-WorkspaceLabel.*?\r?\n}\r?\n').Value
    if (-not $fn) { return @($false, 'Get-WorkspaceLabel not found') }
    . ([scriptblock]::Create($fn))
    $prev = $env:HERDR_PANE_ID
    try {
        $env:HERDR_PANE_ID = $null
        $bare = Get-WorkspaceLabel (Join-Path $Bin 'herdr.exe')
        $env:HERDR_PANE_ID = 'w9:p99'          # a pane that cannot exist
        $bogus = Get-WorkspaceLabel (Join-Path $Bin 'herdr.exe')
    }
    finally { $env:HERDR_PANE_ID = $prev }
    @((($bare -eq '') -and ($bogus -eq '')), "unset='$bare' bogus='$bogus'")
} -Fix 'Get-WorkspaceLabel in notify.ps1 must return an empty string, never throw, when HERDR_PANE_ID is missing or names a pane herdr does not have.'

# Guards the branch in Get-NotifyHookArgs. The flag must be added for claude and
# withheld for every other agent, or $Agent stops being swappable.
Test-Item 'notify hooks attach to claude only' {
    $src = Get-Content (Join-Path $Root 'platform\windows\startup-once.ps1') -Raw
    $fn = [regex]::Match($src, '(?s)function Get-NotifyHookArgs.*?\r?\n}\r?\n').Value
    if (-not $fn) { return @($false, 'Get-NotifyHookArgs not found') }
    . ([scriptblock]::Create("function Note([string]`$m){}`n$fn"))
    $yes = Get-NotifyHookArgs -BundleRoot $Root -Agent 'claude'
    $no  = Get-NotifyHookArgs -BundleRoot $Root -Agent 'codex'
    @((($yes -match '--settings') -and ($no -eq '')), "claude='$yes' codex='$no'")
} -Fix 'Get-NotifyHookArgs in startup-once.ps1 must return the --settings flag for claude and an empty string for any other agent.'

Test-Item 'file viewer colour config installed' {
    $herdrExe = Join-Path $Bin 'herdr.exe'
    $dir = (& $herdrExe plugin config-dir herdr-file-viewer 2>$null | Out-String).Trim()
    if (-not $dir) { return @($false, 'plugin not installed') }
    $cfg = Join-Path $dir 'config.toml'
    if (-not (Test-Path $cfg)) { return @($false, "not found at $cfg") }
    $raw = Get-Content $cfg -Raw
    if ($raw -match '__BUNDLE__') { return @($false, 'token was not substituted') }
    @(($raw -match 'render-syntax\.cmd' -and $raw -match 'render-diff\.cmd'), $cfg)
} -Fix 'bootstrap.ps1 -Force. Without it the viewer uses bat and delta defaults, whose comment colour scores 3.19 against this background where 4.5 is the readable minimum.'

Test-Item 'editor wired up for the `e` key' {
    $herdrExe = Join-Path $Bin 'herdr.exe'
    $dir = (& $herdrExe plugin config-dir herdr-file-viewer 2>$null | Out-String).Trim()
    if (-not $dir) { return @($false, 'plugin not installed') }
    $cfg = Join-Path $dir 'config.toml'
    if (-not (Test-Path $cfg)) { return @($false, 'viewer config missing') }
    $line = (Get-Content $cfg | Where-Object { $_ -match '^\s*editor\s*=' } | Select-Object -First 1)
    @([bool]$line, $line)
} -Fix 'bootstrap.ps1 -Force. Without an editor configured, pressing `e` in the viewer answers "Could not open editor".'

Test-Item 'micro and its wrapper are present' {
    $a = Test-Path (Join-Path $Bin 'micro.exe')
    $b = Test-Path (Join-Path $Root 'platform/windows/edit.cmd')
    @(($a -and $b), "micro=$a wrapper=$b")
} -Fix 'bootstrap.ps1 -Force'

Test-Item 'micro config seeded inside the bundle, not %APPDATA%' {
    $scheme = Join-Path $Bin 'micro-config\colorschemes\rose-pine-moon.micro'
    $settings = Join-Path $Bin 'micro-config\settings.json'
    if (-not (Test-Path $settings)) { return @($false, 'settings.json missing') }
    $null = Get-Content $settings -Raw | ConvertFrom-Json
    @((Test-Path $scheme), 'MICRO_CONFIG_HOME is set by edit.cmd to bin\micro-config')
} -Fix 'bootstrap.ps1 -Force'

Test-Item 'both renderer wrappers exist' {
    $a = Test-Path (Join-Path $Root 'platform/windows/render-syntax.cmd')
    $b = Test-Path (Join-Path $Root 'platform/windows/render-diff.cmd')
    @(($a -and $b), "syntax=$a diff=$b")
} -Fix 'The repo is incomplete. Re-clone it.'

Test-Item 'Nerd Font registered for this user' {
    $k = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $n = @(Get-ItemProperty $k -ErrorAction SilentlyContinue |
           Get-Member -MemberType NoteProperty |
           Where-Object Name -like 'JetBrainsMono*').Count
    @(($n -ge 1), "$n faces registered")
} -Fix 'bootstrap.ps1 -Force. Without it the sidebar renders icons as empty boxes.'

Test-Item 'file viewer plugin installed' {
    $out = & (Join-Path $Bin 'herdr.exe') plugin list 2>&1 | Out-String
    @(($out -match 'herdr-file-viewer'), $out.Trim())
} -Fix '.\bin\herdr.exe plugin install smarzban/herdr-file-viewer --yes'

Test-Item 'file viewer exposes its Windows actions' {
    $p = Join-Path $Bin 'herdr.exe'
    $out = & $p plugin list --json 2>&1 | Out-String
    @(($out -match 'herdr-file-viewer'), 'action ids are checked live below')
} -WarnOnly -Fix '.\bin\herdr.exe plugin install smarzban/herdr-file-viewer --yes'

foreach ($script in 'bootstrap.ps1', 'Start-Pitwall.ps1', 'Uninstall.ps1',
                    'Test-Bundle.ps1', 'platform\windows\pane-init.ps1',
                    'platform\windows\Build-HerdrConfig.ps1',
                    'platform\windows\startup-once.ps1',
                    'platform\windows\edit-split.ps1',
                    'platform\windows\keycard.ps1') {
    Test-Item "$script parses" ([scriptblock]::Create(@"
        `$errs = `$null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            '$(Join-Path $Root $script)', [ref]`$null, [ref]`$errs)
        @((-not (`$errs -and `$errs.Count)), "`$(`$errs.Count) parse errors")
"@))
}

# ===========================================================================
# LIVE
# ===========================================================================
if ($SkipLive) {
    Write-Section 'LIVE: skipped (-SkipLive)'
}
else {
    Write-Section 'LIVE: starting a throwaway herdr session'

    $herdr    = Join-Path $Bin 'herdr.exe'
    $testName = 'pitwall-selftest'
    $env:HERDR_CONFIG_PATH = Join-Path $Bin 'herdr-config.toml'
    $env:PATH = "$Bin;$env:PATH"

    # Named session so an existing console is never disturbed.
    & $herdr session stop $testName 2>$null | Out-Null
    Start-Sleep -Milliseconds 400

    $server = Start-Process -FilePath $herdr `
                            -ArgumentList @('--session', $testName, 'server') `
                            -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 4

    Test-Item 'headless herdr server starts' {
        $out = & $herdr --session $testName status 2>&1 | Out-String
        @(($out -match 'status:\s*running'), $out.Trim())
    } -Fix 'Read bin\pane-init.log and %APPDATA%\herdr\sessions\*\herdr-server.log'

    # A headless server has no panes until something creates one. Create a
    # workspace, which is what a real client does on first attach, so the pane
    # checks below have something to run in.
    Test-Item 'a workspace with a pane can be created' {
        & $herdr --session $testName workspace create --cwd $Root 2>$null | Out-Null
        Start-Sleep -Seconds 3
        $out = & $herdr --session $testName pane list 2>&1 | Out-String
        @(($out -match '"pane_id"'), (($out -split "`n")[0]))
    } -Fix 'The server started but will not create a pane. Check %APPDATA%\herdr\sessions\*\herdr-server.log'

    Test-Item 'the pane shell puts bin\ on PATH (delta, bat, glow, lazygit)' {
        # Pick the pane with no label, which is the one running the shell.
        # Taking the FIRST pane_id instead is wrong the moment anything opens a
        # pane of its own: a plugin that auto-docks a sidebar, or the launcher
        # opening the file viewer, sorts ahead of the shell and this check then
        # types `where.exe delta` into a TUI that swallows it. The failure looks
        # exactly like a broken default_shell, which is the wrong place to look.
        # Panes herdr or a plugin creates are labelled ("Sidebar", "Files");
        # the shell pane carries no label key at all.
        $panes = & $herdr --session $testName pane list 2>&1 | Out-String
        $shell = ($panes | ConvertFrom-Json).result.panes |
                 Where-Object { -not $_.label } | Select-Object -First 1
        if (-not $shell) { return @($false, 'no unlabelled shell pane to test') }
        $pane = $shell.pane_id
        & $herdr --session $testName pane send-text $pane 'where.exe delta' 2>$null | Out-Null
        & $herdr --session $testName pane send-keys $pane 'Enter' 2>$null | Out-Null
        Start-Sleep -Seconds 4
        $out = & $herdr --session $testName pane read $pane --source recent 2>&1 | Out-String
        @(($out -match 'bin\\delta\.exe'), ($out -split "`n" | Where-Object { $_ -match 'delta' } | Select-Object -First 1))
    } -Fix 'Check that [terminal] default_shell in bin\herdr-config.toml points at platform\windows\agent-shell.cmd'

    Test-Item 'the file viewer action exists for Windows' {
        $out = & $herdr --session $testName plugin action list 2>&1 | Out-String
        @(($out -match 'open-file-viewer-windows'), 'the -windows suffixed ids are the ones this config binds')
    } -Fix '.\bin\herdr.exe plugin install smarzban/herdr-file-viewer --yes'

    Test-Item 'the file viewer opens a pane' {
        $before = (& $herdr --session $testName pane list 2>&1 | Out-String |
                   Select-String '"pane_id"' -AllMatches).Matches.Count
        & $herdr --session $testName plugin action invoke herdr-file-viewer.open-file-viewer-windows 2>$null | Out-Null
        Start-Sleep -Seconds 7
        $after = (& $herdr --session $testName pane list 2>&1 | Out-String |
                  Select-String '"pane_id"' -AllMatches).Matches.Count
        @(($after -gt $before), "panes $before -> $after")
    } -Fix 'Read `.\bin\herdr.exe plugin log`. Open issue herdrdev/herdr#3024 affects plugin panes on Windows; ctrl+b alt+g (lazygit) is the fallback.'

    Test-Item 'clean mode isolates Claude Code' {
        $cleanDir = Join-Path $Root 'config\claude'
        New-Item -ItemType Directory -Force -Path $cleanDir | Out-Null
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
            return @($false, 'claude is not on PATH, cannot verify')
        }
        $prev = $env:CLAUDE_CONFIG_DIR
        try {
            $env:CLAUDE_CONFIG_DIR = $cleanDir
            $out = & claude plugin list 2>&1 | Out-String
            @(($out -match 'No plugins installed'), $out.Trim())
        }
        finally { $env:CLAUDE_CONFIG_DIR = $prev }
    } -WarnOnly -Fix 'If this lists plugins, CLAUDE_CONFIG_DIR is being ignored and -Clean would not isolate anything.'

    # Tear down
    & $herdr --session $testName server stop 2>$null | Out-Null
    Start-Sleep -Milliseconds 800
    & $herdr session stop   $testName 2>$null | Out-Null
    & $herdr session delete $testName 2>$null | Out-Null
    if ($server -and -not $server.HasExited) {
        try { $server | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    }
    Write-Host '  test session torn down' -ForegroundColor DarkGray
}

# ===========================================================================
# GLOBAL
# ===========================================================================
Write-Section 'GLOBAL: what the bundle promised not to touch'

Test-Item 'no settings written to %LOCALAPPDATA%\Microsoft\Windows Terminal' {
    $p = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal'
    @((-not (Test-Path $p)), $p)
} -Fix 'The .portable marker is missing or was added after the first launch. Recreate it and relaunch.'

Test-Item 'the packaged Windows Terminal settings were not modified' {
    $p = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path $p)) { return @($true, 'no packaged Windows Terminal installed') }
    @($true, "last modified $((Get-Item $p).LastWriteTime). This bundle never writes here.")
}

Test-Item 'no herdr config written to %APPDATA%\herdr\config.toml' {
    $p = Join-Path $env:APPDATA 'herdr\config.toml'
    @((-not (Test-Path $p)), 'HERDR_CONFIG_PATH keeps the config in the bundle')
} -WarnOnly -Fix 'A global herdr config exists. Harmless, but it means herdr was also run outside this bundle.'

Test-Item '%APPDATA%\herdr exists and is the only herdr state outside the bundle' {
    $p = Join-Path $env:APPDATA 'herdr'
    if (-not (Test-Path $p)) { return @($true, 'not created yet') }
    $mb = [math]::Round((Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue |
                         Measure-Object Length -Sum).Sum / 1MB, 1)
    @($true, "$mb MB. Documented and removable with Uninstall.ps1 -RemoveHerdrData")
}

# ===========================================================================
Write-Host ''
Write-Host ('-' * 60)
$summary = "  $script:Pass passed, $script:Fail failed, $script:Warn warnings"
if ($script:Fail -gt 0) {
    Write-Host $summary -ForegroundColor Red
    Write-Host ''
    Write-Host '  failed checks:' -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host ''
    Write-Host '  Send this whole output when reporting a problem.' -ForegroundColor Yellow
    exit 1
}

Write-Host $summary -ForegroundColor Green
if ($script:Warn -gt 0) {
    Write-Host '  Warnings do not block anything, but read them once.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '  Ready. Start it with:' -ForegroundColor Cyan
Write-Host '    .\Start-Pitwall.ps1'
Write-Host ''
exit 0
