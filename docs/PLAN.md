# Plan and decision record

Everything behind `pitwall`: what was researched, what was chosen, how
each claim was checked, and what is still unproven.

Research and build date: **2026-08-23**. Anything version-dependent below has a
date because this stack moves fast.

Each factual claim carries one of three labels:

- **[source]** read from primary documentation, a changelog or an issue tracker
- **[ran]** verified by executing it on this machine
- **[reasoned]** inferred and not verified

---

## 1. The goal

Reproduce the useful half of Kun Chen's agentic terminal on Windows:

1. An agent-aware sidebar showing which agents are running, working or idle.
2. A permanent right-hand panel showing the diff of what the agent just wrote,
   and letting you open any file.

Plus one requirement his setup does not have: **it must be separable**. The
stock Windows Terminal has to stay untouched so it can be used for client work
and shared screens, and the whole thing has to be shippable to another
developer as a folder.

## 2. What the reference setup actually is

The screenshot that started this is Kun Chen's macOS environment. **[source]**

| Element | Tool | Windows verdict |
|---|---|---|
| `spaces` / `agents` sidebar | herdr, Rust, Apache 2.0 | Native, no WSL |
| Terminal | WezTerm | Works, not chosen. See section 4 |
| Centre pane | Claude Code CLI | Unchanged |
| `Opus 4.8 \| ctx: 2% used` | a statusline plugin | Already present on this machine |
| Right pane (NeogitStatus) | Neovim + Neogit | Replaced. See section 5 |
| File opening | oil.nvim, snacks.nvim | Replaced |

Note the name: the tool is **herdr**, not "Herder".

## 3. herdr on Windows

The single most important fact, and the one the vendor's own website gets
wrong.

From `CHANGELOG.md`, under `## [0.8.2] - 2026-08-19`: **[source]**

> Windows support is now generally available through stable releases and uses
> the stable update channel by default. Existing preview installs stay on
> preview until explicitly switched.

Windows went GA on **2026-08-19**, four days before this was built. The docs
site at `herdr.dev/docs/windows-beta/` still says beta; it is stale. The 0.8.0
release notes say "preview" because GA landed in 0.8.2, not 0.8.0.

Windows is actively maintained: 48 Windows mentions across the changelog, with
14 entries in 0.8.2 alone. **[source]**

### A correction worth recording

An early draft of this plan claimed the mouse does not reach pane applications
on native Windows, citing [herdr#1528](https://github.com/herdrdev/herdr/issues/1528).
That was wrong and it nearly cost the whole right-hand panel. The issue is
**closed as not planned**, was filed against 0.7.4-preview, and was specific to
OpenCode. The changelog says the opposite: **[source]**

- line 349: "Plain Esc, Shift+Enter, **mouse**, focus, resize, and Unicode paste
  handling are preserved on the Windows client path" (#670)
- line 478: "Pane apps that request any-motion mouse tracking now receive
  hover/move events" (#419)

Lesson, and it is the general one: a closed issue against an old version is not
evidence about the current one.

## 4. Terminal choice

The right-hand panel is **not** a terminal feature. Three independent layers:

| Layer | Component | Responsibility |
|---|---|---|
| 1 | Windows Terminal | Draws glyphs, font, transparency, forwards input |
| 2 | herdr | Splits the screen, tracks agents |
| 3 | herdr-file-viewer | The diffs and the files |

The terminal only matters for one thing here: how faithfully it forwards
keyboard input. Specifically the **Kitty keyboard protocol**, without which
Shift+Enter is indistinguishable from Enter. herdr's docs are explicit:
"if it reports `shift+enter` as plain Enter, Herdr can only forward plain
Enter." **[source]**

| Terminal | Kitty protocol | herdr on Windows | Verdict |
|---|---|---|---|
| Windows Terminal 1.24 stable | No, landed in 1.25 | Fixes for this path (#670) | Shift+Enter degraded |
| **Windows Terminal 1.25 Preview** | **Yes**, since 2026-03-05 | Same fixes | **Chosen** |
| Alacritty 0.17 | Yes | Explicit fix (#792) | Good alternative |
| WezTerm | Yes | #2786 open; Windows build dated Feb 2024 | Rejected |

Verified with `winget show`: stable is 1.24.11911.0, preview is 1.25.1912.0.
Kitty has not reached the stable channel. **[ran]**

There is **no settings key** to enable the protocol. The Windows Terminal
settings schema on `main` contains no `kitty`, no `keyboard`, and no `protocol`
key. The protocol is negotiated by the application via escape sequence; the
terminal only has to support it. **[ran]**

## 5. Neovim was dropped

Kun Chen's right pane is Neovim with Neogit. It was replaced by
`herdr-file-viewer` for three reasons:

1. The requirement is **reading** diffs and opening files, not editing in that
   pane. The file viewer is read-only by design and cannot damage the agent's
   work.
2. Neovim on Windows needs a C compiler for treesitter. This machine has none:
   no `cc`, `gcc`, `clang`, `cl` or `zig`. **[ran]** That is a large
   prerequisite for a bundle meant to be handed to someone else.
3. The file viewer is one plugin install with zero configuration.

The viewer covers the requirement directly: "Tree on the left. On the right, the
view that file deserves: a diff if it changed, rendered markdown, or highlighted
code." **[source]**

Neovim remains a reasonable later addition. It is not needed for the goal.

## 6. Isolation, the part that shaped the design

Three levers, all verified.

| Layer | Lever | Evidence |
|---|---|---|
| Terminal | `.portable` marker file next to `WindowsTerminal.exe` | Microsoft Learn: "This self-contained installation doesn't interfere with other installed distributions of Windows Terminal." **[source]** Confirmed: WT wrote `state.json` into the bundle and created nothing under `%LOCALAPPDATA%\Microsoft\Windows Terminal`. **[ran]** |
| herdr config | `HERDR_CONFIG_PATH` | `herdr config check` read the bundle file and reported its errors. No `%APPDATA%\herdr\config.toml` was created. **[ran]** |
| Claude Code | `CLAUDE_CONFIG_DIR` | With it set to an empty directory, `claude plugin list` printed "No plugins installed" instead of listing the personal ones. **[ran]** |

`CLAUDE_CONFIG_DIR` is documented: "Claude Code then stores your settings,
session history, and plugins there instead." **[source]** The isolated directory
gets its own `.claude.json` with **no credentials**, so a clean profile means a
separate login. **[ran]** For compliance separation that is a feature.

### Where isolation stops

`HERDR_CONFIG_PATH` moves `config.toml` and nothing else. Plugins, logs, the
server socket and session state stay in `%APPDATA%\herdr`. Probed
`HERDR_DATA_DIR`, `HERDR_DATA_PATH`, `HERDR_PLUGIN_DIR`, `HERDR_HOME` and
`XDG_DATA_HOME`; none changed the directory reported by
`herdr plugin config-dir`. **[ran]**

This is stated plainly in the README rather than papered over. `Uninstall.ps1`
offers `-RemoveHerdrData`.

## 7. Everything is a standalone archive

Verified against the GitHub releases API rather than the web pages, which load
their asset lists with JavaScript. **[ran]**

| Component | Asset | Size |
|---|---|---|
| Windows Terminal 1.25.1912.0 | `Microsoft.WindowsTerminalPreview_1.25.1912.0_x64.zip` | 11.6 MB |
| herdr 0.8.2 | `herdr-windows-x86_64.zip` | 8 MB |
| lazygit 0.64.1 | `lazygit_0.64.1_windows_x86_64.zip` | 6.8 MB |
| delta 0.19.2 | `delta-0.19.2-x86_64-pc-windows-msvc.zip` | 3.3 MB |
| bat 0.26.1 | `bat-v0.26.1-x86_64-pc-windows-msvc.zip` | 3.4 MB |
| glow 3.0.0 | `glow_3.0.0_Windows_x86_64.zip` | 6.7 MB |
| Nerd Font 3.5.1 | `JetBrainsMono.zip` | 127.8 MB |

No installer, no admin, no package manager.

## 8. Bugs found while building

Recorded because each one would cost the next person an hour.

### herdr ships its own ConPTY runtime, and it is not optional

The archive contains more than the executable:

```
conpty/conpty.dll
conpty/x64/OpenConsole.exe
conpty/arm64/OpenConsole.exe
conpty/herdr-conpty.json      <- checksums the other three
herdr.exe
```

The first `bootstrap.ps1` extracted only `herdr.exe`, following the same rule as
the other five tools. The result: herdr started and exited instantly, wrote no
log, and left a bare prompt. Diagnosing it took a process-tree dump.

Fixed by giving the manifest a `bundle` kind that copies the whole tree beside
the exe. **[ran]**

### Windows Terminal starts a profile with a fresh environment

The single most consequential finding of the build, because it broke three
things before it was understood.

`Start-Process` does pass a modified `$env:PATH` to its child; that was tested
directly and confirmed. **[ran]** But Windows Terminal does not hand its own
environment to the command line a profile runs. Verified twice:

- `pwsh -NoLogo -NoExit -Command herdr` in a profile left `pwsh` running with no
  herdr child, because `herdr` was not on the profile's PATH even though the
  launcher had put it there.
- `CLAUDE_CONFIG_DIR`, exported by the launcher immediately before
  `Start-Process`, arrived **unset** in the pane.

Consequences and fixes:

| Broken | Fix |
|---|---|
| herdr not found | `pane-init.ps1` derives the bundle root from its own path and calls `herdr.exe` by full path |
| Mode could not be passed by env | Each mode is its own Windows Terminal profile, carrying `-Clean` on the command line |
| Profile name with spaces and parentheses silently opened a default tab | Select the profile by GUID, read out of the rendered settings |

### herdr rebuilds PATH for the panes it spawns

Separate from the above, and found after it. Inside a herdr pane:

```
PS> $env:PATH.Split(";")[0..3]
C:\Program Files\WindowsApps\Microsoft.PowerShell_...
C:\windows\system32
...
PS> where.exe delta
INFO: Could not find files for the given pattern(s).
```

`HERDR_CONFIG_PATH` arrives intact, so herdr passes environment variables
through but rebuilds `PATH` from the system default. **[ran]** That made every
binary in `bin\` invisible to panes and to the file viewer plugin, which looks
for `delta`, `bat` and `glow` on PATH and had been silently falling back to
plain text.

herdr's config has no environment key, so the fix goes through
`[terminal] default_shell`, which accepts an executable. `agent-shell.cmd`
re-adds `bin\` from `%~dp0` and then starts PowerShell. Verified: `where.exe
delta` inside a pane now returns `C:\devgent-consolein\delta.exe`, and the
viewer renders diffs through delta instead of showing the fallback notice.
**[ran]**

Popup keybindings bypass `default_shell` (the default config notes that on
Windows command strings run through `cmd.exe /d /c`), so the lazygit binding
uses an absolute path from the same `__BUNDLE__` token.

### A shared herdr server would have made -Clean a lie

The worst bug of the build, and it only appears when both modes are used.

herdr's server is persistent, and panes inherit the environment the **server**
started with, not the client's. A clean-mode client attaching to a server that
had been started in personal mode produced panes with no `CLAUDE_CONFIG_DIR`
at all: the launcher printed "clean", and Claude Code loaded the full personal
profile. **[ran]**

For a compliance feature, a silent false negative is worse than a crash.

Fixed by giving clean mode its own named herdr session. Named sessions get
their own directory, socket and server process:

```
name      status   directory                                   socket
default   stopped  %APPDATA%\herdr                             ...\herdr.sock
clean     running  %APPDATA%\herdr\sessions\clean              ...\clean\herdr.sock
```

Verified end to end: in a clean pane, `$env:CLAUDE_CONFIG_DIR` reports the
bundle profile and `claude plugin list` answers "No plugins installed", against
the full personal list in personal mode. **[ran]**

### `Set-Content -Encoding UTF8` writes a BOM under PowerShell 5.1

The rendered `settings.json` came out with a byte order mark, which is a parse
error for a strict JSON reader. Replaced with
`[System.IO.File]::WriteAllText` and a `UTF8Encoding($false)`. **[ran]**

### The theme name was invented

`rose-pine-moon` is not a valid herdr theme. `herdr config check` listed the
real set; the correct name is `rose-pine`. The terminal palette was realigned
to match. **[ran]**

Worth noting the general point: `herdr config check` catches this class of
error in a second, and should be run after every config edit.

### Windows action ids carry a suffix

The plugin's README says the Windows open actions use `-windows` action ids.
Confirmed against the live plugin: `open-file-viewer` and
`open-file-viewer-tab` declare `platforms: ["linux","macos"]`, while
`open-file-viewer-windows` and `open-file-viewer-tab-windows` declare
`platforms: ["windows"]`. The config binds the Windows pair. **[ran]**

This is the one place `config/` is not cross platform.

## 9. Unrelated defect found on the way

The machine's `~/.claude/settings.json` pointed its statusline at
`plugins\cache\ponytail\ponytail\4.8.4\hooks\ponytail-statusline.ps1`. That path
does not exist; `plugins\cache\` is gone entirely. The script now lives at
`plugins\marketplaces\ponytail\hooks\ponytail-statusline.ps1` and runs
correctly from there. **[ran]**

It then repaired itself: running `claude` during this session rebuilt
`plugins\cache\`, and the configured path exists again. **[ran]** So the
statusline is not currently broken.

What remains is latent, not active: the version number is hardcoded, so the same
failure returns the next time ponytail updates. The machine's own July bundle at
`C:\dev\claude-setup-bundle` already solved this by globbing for the newest
installed version. Left untouched here, since nothing is broken today and this
is outside the bundle's scope.

## 10. Verification status

| # | Claim | Status |
|---|---|---|
| 1 | herdr reports 0.8.2 | **[ran]** |
| 2 | Portable WT runs from the bundle and writes state there, not to `%LOCALAPPDATA%` | **[ran]** |
| 3 | herdr reads the bundle config and creates no global one | **[ran]** |
| 4 | herdr TUI renders with the rose-pine palette and the spaces/agents sidebar | **[ran]**, from an escape-sequence capture |
| 5 | herdr server starts and stays running when launched by the bundle | **[ran]** |
| 6 | The file viewer opens a second pane and its action exits 0 | **[ran]** |
| 7 | `CLAUDE_CONFIG_DIR` isolates plugins and login | **[ran]** |
| 8 | All three scripts parse under PowerShell 5.1 and 7 | **[ran]** |
| 9 | The file viewer renders a real diff through delta, two columns | **[ran]** |
| 10 | herdr detects the agent: sidebar shows `claude`, status `idle` | **[ran]** |
| 11 | `-Clean` isolates: clean pane reports the bundle profile and lists no personal plugins | **[ran]** |
| 12 | Clean mode runs its own herdr session with its own socket | **[ran]** |
| 13 | The bundle works on a machine that is not this one | **not verified** |
| 14 | A fresh login inside a clean profile | **not verified** |
| 15 | Long-run stability of herdr on Windows | **not verified** |

## 11. Not checked

- The two source videos. YouTube returns no transcript to a fetch, and the
  HackerNoon writeup returns 403. The tool inventory comes from Kun Chen's
  dotfiles repository, a secondary writeup, and the screenshot.
- WSL2 with a real distribution as an alternative architecture. Only
  `docker-desktop` is installed here, and the native route preserves the
  existing `C:\dev` workflow and `~/.claude`.
- Whether endpoint protection on another machine blocks the downloads.
- The other 762 plugins in the herdr marketplace.
- Whether the Claude Code desktop application honours `CLAUDE_CONFIG_DIR`. An
  issue reports the VS Code extension ignores it, so assume the desktop app does
  too. It does not matter here: `-Clean` targets the CLI inside herdr.

## 12. Next

1. Prove `-Clean` end to end.
2. Test on a second machine. Until then, "your brother can run this" is a
   hypothesis, not a result.
3. Optional: `platform/macos/` with a shell launcher and a Brewfile.
4. Optional: Neovim, once there is a reason to edit in the right pane rather
   than read.
