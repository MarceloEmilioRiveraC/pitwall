@echo off
rem Pane shell for the pitwall.
rem
rem herdr rebuilds PATH for the panes it spawns: other environment variables
rem pass through (HERDR_CONFIG_PATH arrives intact) but PATH comes back as the
rem system default. Without this wrapper the bundle's own bin directory is
rem invisible inside panes, so delta, bat and glow are missing and the file
rem viewer falls back to plain text.
rem
rem %~dp0 is this file's directory, so the bundle root is two levels up and no
rem absolute path has to be baked in.

set "AC_BIN=%~dp0..\..\bin"
set "PATH=%AC_BIN%;%PATH%"

rem Without this, colour-aware tools fall back to 256-colour approximations and
rem every palette arrives muddied. Windows Terminal 1.25 renders 24-bit colour
rem fine; nothing was telling the programs inside the pane that.
set "COLORTERM=truecolor"

rem Prefer PowerShell 7. Fall back to Windows PowerShell so a machine without
rem pwsh still gets a working pane instead of an empty one.
where /q pwsh.exe && (
  pwsh.exe -NoLogo %*
) || (
  powershell.exe -NoLogo %*
)
