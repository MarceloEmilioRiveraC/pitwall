# pitwall keys

Press `ctrl+b i` any time to bring this back. `q` closes it.

`ctrl+b` is the prefix: hold ctrl, tap b, release, then tap the next key.

## The five that matter

| Key | Does |
|---|---|
| `ctrl+b f` | File viewer on the right. Press again to close it. |
| `ctrl+b i` | This card. |
| `ctrl+b ?` | herdr's own full key list. |
| `ctrl+b z` | Zoom the focused pane to full screen, and back. |
| `ctrl+b alt+g` | lazygit, over everything. |

Nothing here can strand you. Close the console and it offers to reopen.

## Moving around (herdr)

| Key | Does |
|---|---|
| `ctrl+b h` `j` `k` `l` | Focus the pane left / down / up / right |
| `ctrl+b tab` | Next pane |
| `ctrl+b c` | New tab |
| `ctrl+b n` `p` | Next / previous tab |
| `ctrl+b 1`..`9` | Jump to tab by number |
| `ctrl+b v` | Split beside |
| `ctrl+b -` | Split below |
| `ctrl+b x` | Close the focused pane |
| `ctrl+b r` | Resize mode, then arrows |
| `ctrl+b b` | Show or hide the agent sidebar |
| `ctrl+b q` | Detach. The session keeps running. |

## File viewer

No prefix in here. Single keys, no ctrl.

| Key | Does |
|---|---|
| `up` `down` or `k` `j` | Move in the tree |
| `enter` | Open a file, or expand a folder |
| `tab` | Switch between tree and content |
| `e` | Edit the selected file |
| `z` | Hide the tree, content fills the pane |
| `f` | Fuzzy find a file |
| `/` then `n` `N` | Search in the file, next / previous hit |
| `c` | Only changed files |
| `d` | Working-tree diffs |
| `D` | Cycle diff style: unified, side by side, plain |
| `]` `[` | Next / previous changed file |
| `y` `Y` | Copy relative / absolute path |
| `?` | The viewer's own full key list |
| `q` or `esc` | Close the viewer |

`esc` always closes the viewer and cannot be remapped. That is upstream's
safety floor, not a pitwall choice. `ctrl+b f` brings it straight back.

## Editing (micro)

Opened with `e` in the viewer. micro repeats these along its bottom row.

| Key | Does |
|---|---|
| `ctrl+s` | Save |
| `ctrl+q` | Quit, back to the viewer |
| `ctrl+z` | Undo |
| `ctrl+f` | Find |
| `ctrl+g` | micro's own help |

## If something looks wrong

| | |
|---|---|
| Panel missing | `ctrl+b f` |
| Pane too narrow to read a diff | `ctrl+b z` to zoom it |
| Dropped to a plain PowerShell prompt | Press enter, it reopens |
| Everything looks broken | Close the window, run `.\Start-Pitwall.ps1` again |
| Still broken | `powershell -ExecutionPolicy Bypass -File .\Test-Bundle.ps1` |
