@echo off
rem The F1 / ctrl+b i key card, shown in a herdr popup.
rem
rem This wrapper exists for two reasons, both learned the hard way.
rem
rem   1. Something has to HOLD the popup open. The card draws and exits in
rem      milliseconds, and herdr closes a popup the moment its command returns,
rem      so pressing the key looked like nothing happening at all. `pause`
rem      holds it; keycard.ps1 says so on its top line.
rem   2. There is no pager on Windows. The first version rendered markdown with
rem      `glow -p`, whose pager shells out to `less`, which does not exist here,
rem      so glow died instantly with "executable file not found" and the popup
rem      shut again. bat --paging=always fails identically. The card is sized to
rem      fit one screen instead, which is better anyway: a reference you have to
rem      scroll is a reference you stop opening.
rem
rem The card is drawn by keycard.ps1 rather than rendered from markdown, because
rem glow paints fenced code blocks as flat uncoloured text and the whole thing
rem read as one undifferentiated mass. See that file's header.

setlocal
set "AC_ROOT=%~dp0..\.."
set "COLORTERM=truecolor"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0keycard.ps1"

rem Any key closes. keycard.ps1 says so on its top line.
pause >nul
