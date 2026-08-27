@echo off
rem PROTOTYPE editor: opens micro in a pane BESIDE the viewer instead of on top
rem of it, so the file tree stays on screen while you edit.
rem
rem Point `editor` in the file viewer's config.toml here to try it, or back at
rem edit.cmd for the stock in-pane behaviour. See edit-split.ps1 for how and why.
rem
rem A .cmd wrapper for the same reason edit.cmd is one: the viewer splits its
rem `editor` string on whitespace itself, so letting cmd.exe do the quoting is
rem more predictable than handing a quoted path through that splitter.
rem
rem %* is the file path the viewer appends.

set "AC_ROOT=%~dp0..\.."

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0edit-split.ps1" -BundleRoot "%AC_ROOT%" -Path %*
