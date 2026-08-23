@echo off
rem The editor the file viewer hands off to when you press `e`.
rem
rem The viewer suspends itself, runs this in the same pane, and comes back when
rem the editor exits. The viewer never writes a file itself.
rem
rem This is a wrapper rather than micro.exe directly for three reasons:
rem
rem   1. MICRO_CONFIG_HOME keeps micro's settings, colourscheme and cursor
rem      history inside the bundle instead of %APPDATA%\micro. Delete the
rem      folder and nothing of micro's is left behind.
rem   2. %~dp0 resolves the bundle from this file's own location, so a bundle
rem      cloned into a path with spaces still works. Passing a quoted path
rem      through the viewer's own argument splitter is less predictable.
rem   3. COLORTERM, same as the renderers. Without it micro falls back to
rem      256-colour approximations of the palette.
rem
rem %* is the file path the viewer appends.
rem
rem Keys inside micro, for anyone who has not used it:
rem   ctrl+s save    ctrl+q quit    ctrl+z undo    ctrl+f find
rem   ctrl+g help    ctrl+e command prompt         mouse works

set "AC_ROOT=%~dp0..\.."
set "MICRO_CONFIG_HOME=%AC_ROOT%\bin\micro-config"
set "COLORTERM=truecolor"

"%AC_ROOT%\bin\micro.exe" %*
