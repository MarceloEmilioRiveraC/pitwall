@echo off
rem The ctrl+b i key card: renders docs\keys.md into a herdr popup.
rem
rem Why a wrapper and not `glow -p` straight from the keybinding.
rem
rem   1. glow's pager shells out to `less`, which does not exist on Windows.
rem      The popup ran glow, glow died with "unable to run command: exec:
rem      \"less\": executable file not found in %PATH%", glow exited, and herdr
rem      closed the popup on the spot. Pressing ctrl+b i looked like a key that
rem      did nothing at all. bat --paging=always fails the same way.
rem   2. Without a pager glow renders and EXITS, which closes the popup just as
rem      fast. Something has to hold it open, hence the pause.
rem
rem So the card is sized to fit one screen instead of scrolling: 34 rendered
rem rows against the popup's ~43. That is better anyway. A reference you scroll
rem is a reference you stop opening.
rem
rem COLORTERM for the same reason as the renderers: without it glow falls back
rem to 256-colour approximations of the palette.

setlocal
set "AC_ROOT=%~dp0..\.."
set "COLORTERM=truecolor"

"%AC_ROOT%\bin\glow.exe" -w 76 "%AC_ROOT%\docs\keys.md"

rem Any key closes. keys.md says so on its last line.
pause >nul
