# User manual

Everything you need to run, drive and reshape the agent console. The
[README](../README.md) is the sales pitch and the install; this is the manual.

If you only read one section, read [The daily loop](#the-daily-loop).

---

## Contents

- [First run](#first-run)
- [What you are looking at](#what-you-are-looking-at)
- [The daily loop](#the-daily-loop)
- [Every key](#every-key)
- [The two modes](#the-two-modes)
- [Customising: where everything lives](#customising-where-everything-lives)
  - [Keybindings](#keybindings)
  - [Your own commands](#your-own-commands)
  - [Colours and theme](#colours-and-theme)
  - [The look: transparency, chrome, font](#the-look-transparency-chrome-font)
  - [The editor](#the-editor)
  - [The sidebar](#the-sidebar)
  - [Which shell the panes use](#which-shell-the-panes-use)
  - [Worktrees](#worktrees)
  - [Notifications](#notifications)
- [Driving it from a script](#driving-it-from-a-script)
- [Updating](#updating)
- [When something breaks](#when-something-breaks)
- [Uninstalling](#uninstalling)

---

## First run

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
.\bin\herdr.exe plugin install smarzban/herdr-file-viewer --yes
powershell -ExecutionPolicy Bypass -File .\Test-Bundle.ps1
.\Start-AgentConsole.ps1
```

`Test-Bundle.ps1` runs 40 checks: files, versions, config validity, a live
herdr session it starts and tears down, and a confirmation that nothing outside
the folder was touched. It prints a fix line for every failure. Run it whenever
something is off, and paste its whole output if you need to ask someone.

```powershell
.\Test-Bundle.ps1 -SkipLive     # static checks only, a few seconds
.\Test-Bundle.ps1 -Detailed     # show what each check actually found
```

Make a shortcut so you are not typing paths. Right-click the desktop, New,
Shortcut, and use:

```
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\dev\agent-console\Start-AgentConsole.ps1"
```

---

## What you are looking at

Three layers, stacked. Knowing which layer owns a thing is the whole trick to
customising it.

| Layer | What it is | Owns | Configured in |
|---|---|---|---|
| 1 | Windows Terminal, portable | The window. Font, colours, transparency, whether there is a title bar | `platform/windows/wt-settings.json` |
| 2 | herdr | The sidebar, panes, tabs, workspaces, agent state, keybindings | `config/herdr/config.toml` |
| 3 | What runs in a pane | Claude Code, the file viewer, lazygit, a shell | their own configs |

Three regions on screen:

- **Sidebar, left.** `spaces` lists your workspaces with their git branch.
  `agents` lists every agent herdr can see and whether it is working, blocked,
  done or idle. Click either to jump.
- **Centre.** Whatever you started. Usually the agent.
- **Right.** The file viewer, when you press `ctrl+b f`.

---

## The daily loop

1. `.\Start-AgentConsole.ps1 -WorkDir C:\dev\my-project`
2. Type `claude` in the centre pane. The sidebar picks it up within a second or
   two and starts tracking its state.
3. Give it work.
4. When it stops, press `ctrl+b f`. The file viewer opens on the right with a
   tree of the repo, `M` next to modified files and `?` next to untracked ones.
5. Press `]` repeatedly. Each press jumps to the next changed file and shows its
   diff. `[` goes back.
6. See something wrong? Press `A` to annotate the range, then `y` to copy the
   note, and paste it into the agent's prompt. It gets the file, the lines and
   your comment, without you describing where anything is.
7. Need to fix something yourself? Press `e`. The viewer steps aside, micro
   opens **in the same pane** on that file, and the viewer comes back when you
   quit, already showing your change as a diff.
8. `ctrl+b alt+g` for lazygit when you want to stage, commit or discard.

The viewer itself is **read-only** by design, and that is the point: reviewing
cannot damage what the agent wrote. Editing happens in the editor it hands off
to, never in the viewer.

Two ways to get a change made, and they are for different things:

| You want | Do this |
|---|---|
| A typo, a constant, a quick fix | `e`, edit, `ctrl+s`, `ctrl+q` |
| Anything the agent should understand | `A` to annotate the range, `y` to copy, paste into the agent |

The annotation carries the file, the lines and your comment, so the agent does
not have to be told where to look.

### Getting more room for the diff

The viewer collapses to tree-only below roughly 90 columns. Two ways to fix
that when the split is too narrow:

- `ctrl+b z` zooms the focused pane to the whole window. Press it again to go
  back. This is the fastest option and the one to reach for.
- Drag the border between panes with the mouse, or use the resize keys.

---

## Every key

The prefix is `ctrl+b`. Press `ctrl+b ?` at any time for the live list, which is
authoritative if this table ever drifts.

### herdr

| Key | Action |
|---|---|
| `ctrl+b f` | **File viewer in a split.** The right-hand panel |
| `ctrl+b shift+f` | File viewer in its own tab |
| `ctrl+b alt+g` | lazygit in a popup |
| `ctrl+b c` | New tab |
| `ctrl+b v` | Split right |
| `ctrl+b -` | Split down |
| `ctrl+b h` `j` `k` `l` | Move focus left, down, up, right |
| `ctrl+b tab` | Cycle to the next pane |
| `ctrl+b z` | Zoom the focused pane |
| `ctrl+b r` | Resize mode, then arrows |
| `ctrl+b x` | Close pane |
| `ctrl+b shift+p` | Rename pane |
| `ctrl+b n` / `ctrl+b p` | Next / previous tab |
| `ctrl+b 1` .. `9` | Jump to tab |
| `ctrl+b shift+t` | Rename tab |
| `ctrl+b shift+x` | Close tab |
| `ctrl+b w` | Workspace picker |
| `ctrl+b shift+n` | New workspace |
| `ctrl+b shift+g` | New git worktree |
| `ctrl+b b` | Toggle the sidebar |
| `ctrl+b g` | Session navigator, a searchable tree of everything |
| `ctrl+b e` | Open this pane's scrollback in your editor |
| `ctrl+b s` | Settings |
| `ctrl+b shift+r` | Reload the config without restarting |
| `ctrl+b q` | Detach. The session keeps running |
| `ctrl+b ?` | Every binding |

Every row above was read out of `herdr --default-config`, so it matches what
herdr actually binds. `ctrl+b ?` is still the authority if you have remapped
anything.

herdr is mouse-first as well. Click the sidebar to switch, drag pane borders to
resize, right-click for a context menu.

### Inside the file viewer

| Key | Action |
|---|---|
| `]` / `[` | Next / previous **changed** file |
| `v` | Cycle the view: diff, rendered markdown, syntax highlighted |
| `b` | Toggle the diff baseline between merge-base and HEAD |
| `f` | Fuzzy find a file |
| `p` | Pin the current file and keep browsing, for side by side |
| `a` / `A` | Annotate a file or a line range |
| `y` | Copy the annotations, to paste to the agent |
| `L` | Copy a `path:line` reference |
| `W` | Switch git worktree |
| `Z` | Full-screen the current file |
| `e` | Open in your editor |
| `O` / `R` | Open in the OS app / reveal in file manager |
| `?` | Help overlay |

### Inside micro, the editor

`e` opens it. No modes, and the mouse works.

| Key | Action |
|---|---|
| `ctrl+s` | Save |
| `ctrl+q` | Quit, back to the viewer |
| `ctrl+z` / `ctrl+y` | Undo / redo |
| `ctrl+f` | Find, then `ctrl+n` / `ctrl+p` for next and previous |
| `ctrl+c` / `ctrl+v` / `ctrl+x` | Copy, paste, cut |
| `ctrl+g` | Help |
| `ctrl+e` | Command prompt, for `replace`, `goto` and the rest |

Nothing is auto-saved. Quitting with unsaved changes asks first.

### Windows Terminal

The window starts with no title bar and no tab bar, because herdr provides its
own tabs.

| Key | Action |
|---|---|
| `ctrl+shift+.` | Toggle the title bar and tab bar back |
| `f11` | Fullscreen |
| `ctrl+shift+c` / `ctrl+shift+v` | Copy / paste |
| `ctrl+shift+f` | Windows Terminal's own search |
| `ctrl+plus` / `ctrl+minus` / `ctrl+0` | Font size up, down, reset |

---

## The two modes

| Command | Claude Code reads | herdr session |
|---|---|---|
| `.\Start-AgentConsole.ps1` | your `~/.claude`: your plugins, CLAUDE.md, statusline, login | `default` |
| `.\Start-AgentConsole.ps1 -Clean` | `config/claude/` inside the bundle: nothing personal, its own login | `clean` |

Use `-Clean` for client work and anything you screen-share. The first time you
use it, Claude Code will ask you to log in, because credentials live in the
config directory and the clean one starts empty. That is the point.

The two use **separate herdr sessions**, each with its own server and socket.
This is not cosmetic: herdr's server is persistent and panes inherit the
environment the *server* started with, so sharing one would have meant a clean
client attaching to a personal server and getting no isolation at all while
still saying "clean".

Both are also Windows Terminal profiles. Press `ctrl+shift+.` to bring back the
tab bar, then use the `+` dropdown to open the other mode in a new tab.

```powershell
.\Start-AgentConsole.ps1 -WorkDir C:\dev\Exposoft          # start somewhere specific
.\Start-AgentConsole.ps1 -Clean -WorkDir C:\work\client
```

---

## Customising: where everything lives

| I want to change | Edit | Applies |
|---|---|---|
| Keybindings, sidebar, herdr theme, worktrees | `config/herdr/config.toml` | Next launch |
| Font, transparency, window chrome, terminal palette | `platform/windows/wt-settings.json` | After `bootstrap.ps1 -Force` |
| What a pane runs at startup | `platform/windows/pane-init.ps1` | Next launch |
| Which tools are bundled and their versions | `bootstrap.ps1`, the `$Manifest` block | After `bootstrap.ps1 -Redownload` |

Two of these are **templates**. They contain a `__BUNDLE__` token that is
replaced with the real folder path, which is what lets the same repo work on any
machine. Never hardcode a path where a `__BUNDLE__` would do.

- `config/herdr/config.toml` is rendered to `bin/herdr-config.toml` on **every
  launch**, so your edits apply the next time you start the console.
- `platform/windows/wt-settings.json` is rendered to
  `bin/WindowsTerminal/settings/settings.json` by **bootstrap**, so run
  `bootstrap.ps1 -Force` after editing it. `-Force` reuses the download cache,
  so it takes seconds, and it now closes a running console for you first.

Always run this after editing the herdr config:

```powershell
.\bin\herdr.exe config check
```

It prints `config: ok` or tells you exactly what is wrong. It matters more than
it looks: an **unknown theme name is silently replaced by catppuccin**, so a
typo gives you a working console with the wrong colours and no error.

### Keybindings

In `config/herdr/config.toml`:

```toml
[keys]
prefix = "ctrl+b"
new_tab = "prefix+c"
next_tab = "prefix+n"
focus_pane_left = "prefix+h"
split_horizontal = "prefix+minus"
```

Change the prefix if `ctrl+b` collides with something:

```toml
[keys]
prefix = "ctrl+space"
```

Two shortcuts for one action:

```toml
next_tab = ["prefix+n", "ctrl+alt+]"]
```

To start over:

```powershell
.\bin\herdr.exe config reset-keys
```

### Your own commands

This is the part worth knowing. `[[keys.command]]` binds any command to any key.

```toml
[[keys.command]]
key = "prefix+alt+g"
type = "popup"
command = "__BUNDLE__/bin/lazygit.exe"
description = "lazygit"
width = "90%"
height = "90%"
```

`type` is one of:

| type | Behaviour |
|---|---|
| `popup` | A modal terminal over everything, closes when the command exits |
| `pane` | A temporary pane that closes when the command exits |
| `shell` | Runs detached in the background, nothing appears |
| `plugin_action` | Invokes a plugin action, which is how the file viewer is bound |

**Use an absolute path for anything in `bin/`.** Popup and pane commands run
through `cmd.exe /d /c` on Windows and do not get the pane shell's PATH, so a
bare `lazygit` will not be found. `__BUNDLE__/bin/lazygit.exe` will.

Some worked examples to paste in:

```toml
# Run the test suite in a popup
[[keys.command]]
key = "prefix+alt+t"
type = "popup"
command = "powershell -NoProfile -ExecutionPolicy Bypass -File __BUNDLE__/Test-Bundle.ps1 -SkipLive"
description = "self test"
width = "80%"
height = "80%"

# Open the current workspace in VS Code, no window
[[keys.command]]
key = "prefix+alt+c"
type = "shell"
command = "code ."
description = "open in vscode"

# A second agent in a split pane
[[keys.command]]
key = "prefix+alt+a"
type = "pane"
command = "claude"
description = "another claude"
```

### Colours and theme

Two palettes have to agree, one per layer.

**herdr**, in `config/herdr/config.toml`. Built-in names, and only these:

```
catppuccin, catppuccin-latte, terminal, tokyo-night, tokyo-night-day,
dracula, nord, gruvbox, gruvbox-light, one-dark, one-light,
solarized, solarized-light, kanagawa, kanagawa-lotus,
rose-pine, rose-pine-dawn, vesper
```

```toml
[theme]
name = "rose-pine"
```

Override individual tokens on top of the base. This is how the bundle gets the
Rose Pine **Moon** look, which herdr does not ship:

```toml
[theme.custom]
panel_bg      = "reset"      # let the terminal's transparency through
sidebar_bg    = "#232136"
active_row_bg = "#2a273f"
selection_bg  = "#44415a"
accent        = "#c4a7e7"
red           = "#eb6f92"
green         = "#3e8fb0"
```

`panel_bg = "reset"` is the one that matters for the layered look. Without it
herdr paints an opaque rectangle behind the panes and the window transparency
does nothing.

Follow the host terminal's light and dark setting instead:

```toml
[theme]
auto_switch = true
dark_name  = "rose-pine"
light_name = "rose-pine-dawn"
```

**The content pane** is a third palette, and the one most likely to be the
problem if reading a file is uncomfortable.

The file viewer pipes content through `bat` for code, `delta` for diffs and
`glow` for markdown. Their stock themes are tuned for their own backgrounds, not
this one. Measured against `#232136`, the comment colour of each candidate, that
being the dimmest thing any theme draws:

| Theme | Contrast | |
|---|---|---|
| Catppuccin Macchiato | **5.62** | the default here, clears WCAG AA |
| Catppuccin Mocha | 5.54 | |
| gruvbox-dark | 4.26 | below AA |
| Dracula | 3.32 | |
| Monokai | 3.19 | bat's own default, the unreadable one |
| TwoDark, OneHalfDark | 2.59 | |

Change it in `config/file-viewer/config.toml`, which bootstrap renders into the
directory `herdr plugin config-dir herdr-file-viewer` prints. It points at two
wrappers rather than inline commands, because the viewer splits a command
string on whitespace itself and delta's style arguments contain spaces:

| File | Renders |
|---|---|
| `platform/windows/render-syntax.cmd` | code, through `bat --theme` |
| `platform/windows/render-diff.cmd` | diffs, through `delta` with hand-picked backgrounds |

`bat --list-themes` shows what you can put there. Two things to know before
editing them:

- **Overriding a renderer replaces the whole command.** Flags are not merged, so
  every flag the default had has to be repeated.
- **Both wrappers set `COLORTERM=truecolor`.** Without it bat and delta fall
  back to 256-colour approximations and every palette arrives muddied, which
  looks like a bad theme but is not.

The diff backgrounds were picked the same way rather than by eye:

| Role | Colour | Comment contrast | Text contrast |
|---|---|---|---|
| removed | `#3a2733` | 4.97 | 9.32 |
| added | `#22342e` | 4.72 | 8.85 |
| removed, word | `#54303e` | 4.04 | 7.57 |
| added, word | `#2a5145` | 3.20 | 5.99 |

The word-level pair sits lower on purpose: it marks changed tokens, which are
never the dim colour, and both clear 4.5 for real changed text.

Markdown is left at the plugin's own bundled palette. Overriding the `markdown`
key would replace the whole command and lose it.

**Windows Terminal**, in `platform/windows/wt-settings.json`, under `schemes`.
That palette is what the text inside the panes uses. Keep the two roughly in
agreement or the seams show.

### The look: transparency, chrome, font

All in `platform/windows/wt-settings.json`. Run `bootstrap.ps1 -Force` after.

**Transparency.** Two different effects that look nothing alike, and the choice
between them is a real trade-off rather than a matter of taste.

| Want | Settings | What you get |
|---|---|---|
| **Frosted glass (the default)** | `"useAcrylic": true, "opacity": 82` | Blurs whatever is behind into a smooth wash. Translucent, and never competes with the text in front |
| Sharp wallpaper | `"useAcrylic": false, "opacity": 90` | Plain alpha. You see exactly what is behind, wallpaper detail included |
| Opaque | `"opacity": 100` | No transparency at all |

Plain alpha is the look of the WezTerm setups this bundle imitates, and it is
genuinely nicer **over a wallpaper**. Over another window it is not: with no
blur to average it out, the text of a bright window behind stays legible
through the text in front, at any opacity worth having. Acrylic has no such
problem because the blur destroys the detail. If your terminal usually sits
over a browser or a chat app, keep acrylic.

Lower `opacity` means more see-through, in both modes.

There is a third way to get the reference look without the trade-off. Skip
window transparency entirely and put the wallpaper *inside* the terminal:

```json
"opacity": 100,
"backgroundImage": "C:/path/to/wallpaper.jpg",
"backgroundImageOpacity": 0.18,
"backgroundImageStretchMode": "uniformToFill"
```

That gives you a visible wallpaper, sharp, with nothing behind it ever bleeding
in, because the window is opaque.

If transparency does nothing at all, check Windows Settings, Personalisation,
Colours, and make sure "Transparency effects" is on. It gates both effects.

**Window chrome.** `launchMode` is a top-level key:

| Value | Result |
|---|---|
| `"maximizedFocus"` | Maximised, no title bar, no tab bar. The current default |
| `"focus"` | Frameless in a normal window |
| `"maximized"` | Maximised with the usual chrome |
| `"default"` | Normal window with chrome |

`ctrl+shift+.` toggles focus mode at runtime whatever you set here.

**Font.** Under `profiles.defaults`:

```json
"font": { "face": "JetBrainsMono Nerd Font", "size": 10.5, "weight": "normal" }
```

Smaller size means more columns, which is what the file viewer's two-column
layout wants. 9.5 buys roughly 25 more columns on a 1920 wide screen.

Any Nerd Font works, but it **must** be a Nerd Font or the sidebar icons render
as empty boxes. To bundle a different one, change the `JetBrainsMonoNerdFont`
entry in the `bootstrap.ps1` manifest and the four filenames in `$wantedFaces`.

**Padding** around the text: `"padding": "12, 10, 12, 6"` as left, top, right,
bottom.

### The editor

`e` hands the selected file to whatever `editor` names in
`config/file-viewer/config.toml`, which bootstrap renders into the plugin's
config directory. The viewer suspends, the editor runs in the same pane, and
the viewer resumes when the editor exits.

The default points at a wrapper, not at micro directly:

```toml
editor = "__BUNDLE__/platform/windows/edit.cmd"
```

`platform/windows/edit.cmd` sets `MICRO_CONFIG_HOME` to `bin/micro-config` so
micro leaves nothing in `%APPDATA%\micro`, sets `COLORTERM`, and resolves the
bundle from its own location so a path with spaces still works.

To use something else, replace the value:

```toml
editor = "code --wait"     # VS Code, opens in its own window not the pane
editor = "notepad"         # anything already on the Windows PATH
```

`--wait` matters for editors that fork: without it the viewer resumes
immediately and you end up editing behind it.

**Do not rely on `$EDITOR` here.** The viewer reads it from the herdr
*server's* environment, not the shell you are attached to, so anything the
launcher exports never arrives. Verified: with `EDITOR` unset the viewer
answers "Could not open editor: program not found". The config key sidesteps it.

micro's own settings live in `config/micro/`:

| File | What |
|---|---|
| `settings.json` | mouse, soft wrap, tab size, clipboard, status line |
| `colorschemes/rose-pine-moon.micro` | the palette, matched to the rest of the console |

Both are copied into `bin/micro-config/` by bootstrap, so run
`bootstrap.ps1 -Force` after editing them. micro's runtime writes stay in
`bin/` and out of git.

The colourscheme was built the same way as the content pane: every colour that
carries text measured against `#232136`. Worth knowing if you write your own,
because the palette's own `muted` (`#6e6a86`) scores 3.03 and is exactly the
kind of choice that makes comments unreadable. Comments use `subtle`
(`#908caa`, 4.86) instead.

### The sidebar

Each row is a list of tokens, and each list is a line of text.

```toml
[ui.sidebar.agents]
row_gap = 0
rows = [
  ["state_icon", "workspace", "tab"],
  ["agent"],
]

[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace"],
  ["branch", "git_status"],
]
```

| Available in | Tokens |
|---|---|
| agents | `state_icon`, `state_text`, `workspace`, `tab`, `pane`, `agent`, `terminal_title` |
| spaces | `state_icon`, `state_text`, `workspace`, `branch`, `git_status` |

Want a one-line sidebar? Use a single row. Want to see the pane id while
debugging? Add `pane`.

Other bits of chrome:

```toml
[ui]
tab_bar_position = "bottom"       # or "top"
pane_scrollbars = false           # reclaims a column per pane
```

### Which shell the panes use

```toml
[terminal]
default_shell = "__BUNDLE__/platform/windows/agent-shell.cmd"
shell_mode = "auto"
new_cwd = "follow"                # or "home", "current", or a fixed path
```

**Do not point `default_shell` straight at `pwsh`.** herdr rebuilds `PATH` for
the panes it spawns, so `bin/` would be invisible and `delta`, `bat`, `glow` and
`lazygit` would all silently disappear. The file viewer would keep working but
fall back to unstyled plain text.

`agent-shell.cmd` re-adds `bin/` and then starts PowerShell 7, falling back to
Windows PowerShell when 7 is not installed. To use a different shell, edit that
file rather than the config, so the PATH fix stays in place:

```cmd
set "AC_BIN=%~dp0..\..\bin"
set "PATH=%AC_BIN%;%PATH%"
nu.exe %*
```

### Worktrees

herdr manages git worktrees natively, which is the parallel-agents workflow:
one worktree per task, one agent per worktree, no branch switching.

```toml
[worktrees]
directory = "__BUNDLE__/../.worktrees"
```

Checkouts land in `<directory>/<repo>/<branch-slug>`. From the CLI:

```powershell
.\bin\herdr.exe worktree --help
```

### Notifications

```toml
[ui.toast]
delivery = "herdr"        # "herdr", "terminal", "system", or "off"
delay_seconds = 1

[ui.sound.agents]
claude = "on"
```

`delivery = "herdr"` keeps them inside the window so a background agent
finishing does not steal focus. `"system"` uses Windows notifications instead.

`onboarding = false` at the top of the config skips herdr's first-run wizard.
Note that **removing the key is not the same as setting it false**; herdr's own
default config says a missing key also shows onboarding.

---

## Driving it from a script

Everything the UI does is on the CLI, which is how the bundle's own tests work.
Set the config path first so you are talking to the bundle's session:

```powershell
$env:PATH = "C:\dev\agent-console\bin;$env:PATH"
$env:HERDR_CONFIG_PATH = "C:\dev\agent-console\bin\herdr-config.toml"
```

```powershell
herdr status                              # is a server running
herdr session list                        # default and clean
herdr pane list                           # ids, cwd, which has focus
herdr pane read w1:p1 --source visible    # what a pane is showing
herdr pane send-text w1:p1 'npm test'     # type into a pane
herdr pane send-keys  w1:p1 'Enter'       # press a key in a pane
herdr pane split w1:p1 --direction down
herdr pane zoom w1:p2 --on
herdr agent list                          # every agent and its state
herdr plugin action list                  # what plugins expose
herdr plugin action invoke herdr-file-viewer.open-file-viewer-windows
herdr server reload-config                # re-read config.toml live
```

Add `--session clean` to any of these to target the clean-mode session.

The action ids carry a `-windows` suffix on Windows:
`open-file-viewer-windows`, not `open-file-viewer`. The unsuffixed ones declare
`platforms = ["linux", "macos"]` and will not fire here. This is the one place
in `config/` that is not cross platform.

The file viewer action is a **toggle**. Invoking it when the viewer is already
open closes it.

---

## Updating

```powershell
.\bootstrap.ps1 -Force        # re-extract everything, reuse the download cache
.\bootstrap.ps1 -Redownload   # refetch every archive too
.\bootstrap.ps1 -SkipFont     # leave the font alone
```

`-Force` closes a running console first, because herdr holds `conpty.dll` open
and the copy would otherwise fail. herdr persists its session, so reopening
restores your workspaces.

To move to a newer herdr or Windows Terminal, bump the version and URL in the
`$Manifest` block at the top of `bootstrap.ps1` and run `-Redownload`. Then run
`Test-Bundle.ps1`.

Update the file viewer plugin separately:

```powershell
.\bin\herdr.exe plugin install smarzban/herdr-file-viewer --yes
```

---

## When something breaks

Run `.\Test-Bundle.ps1` first. It names the problem and the fix for 38 of them.

| Symptom | Cause | Fix |
|---|---|---|
| Pane opens at a bare prompt, no console | herdr failed to start | Read `bin\pane-init.log`. It records the bundle root and whether `herdr.exe`, `conpty\conpty.dll` and the config were found, plus the mode and session |
| herdr starts and vanishes instantly, no log | `conpty\` is missing beside `herdr.exe` | `.\bootstrap.ps1 -Force`. herdr ships its own ConPTY runtime and will not run without it |
| Sidebar icons are empty boxes | The Nerd Font is not installed | `.\bootstrap.ps1 -Force`, check the face count it reports |
| Viewer says a renderer is missing | `bin\` is not on the pane's PATH | Check `default_shell` points at `agent-shell.cmd`, then `.\bootstrap.ps1 -Force` |
| Colours are wrong, no error | An invalid theme name fell back to catppuccin | `.\bin\herdr.exe config check` |
| Transparency does nothing | Windows transparency effects are off | Settings, Personalisation, Colours, Transparency effects |
| `-Clean` seems to load your normal setup | A stale session | `.\bin\herdr.exe session list`, then `session stop clean`, then relaunch |
| Viewer shows only the tree | The pane is under about 90 columns | `ctrl+b z` to zoom, or drag the border, or lower the font size |
| Shift+Enter behaves like Enter | The terminal is not reporting the Kitty keyboard protocol | Launch through the bundle's Windows Terminal 1.25, not the system 1.24 |
| `bootstrap.ps1` fails on a locked file | Something outside the bundle holds it | Close every terminal from this folder and retry |

Logs worth knowing:

```
bin\pane-init.log                              what each pane resolved at startup
%APPDATA%\herdr\herdr-server.log               the default session
%APPDATA%\herdr\sessions\clean\herdr-server.log  the clean session
.\bin\herdr.exe plugin log                     what plugin actions did, with exit codes
```

---

## Uninstalling

```powershell
.\Uninstall.ps1                                   # the per-user font only
.\Uninstall.ps1 -RemoveHerdrData -RemoveBinaries  # font, %APPDATA%\herdr, and bin\
```

Then delete the folder. Two things live outside it and both are per user, need
no admin, and are handled above: the Nerd Font, and `%APPDATA%\herdr`.

Your system Windows Terminal and your `~/.claude` were never written to, so
there is nothing to undo there.
