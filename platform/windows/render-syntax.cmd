@echo off
rem Syntax highlighting for the file viewer's content pane.
rem
rem File content arrives on stdin, never as a path, so bat needs the trailing
rem "-" and needs the file name passed separately to pick the language.
rem   %1 = the file name, substituted by the viewer from its {name} token.
rem
rem Theme choice is measured, not taste. Against the pane background (#232136,
rem Rose Pine Moon) the comment colour of each candidate theme scores:
rem
rem   Catppuccin Macchiato  5.62   <- chosen, passes WCAG AA (4.5)
rem   Catppuccin Mocha      5.54
rem   gruvbox-dark          4.26
rem   Dracula               3.32
rem   Monokai (bat default) 3.19   <- the unreadable one
rem   TwoDark / OneHalfDark 2.59
rem
rem Comments are the worst case because they are the dimmest thing a theme
rem draws, so a theme that keeps them legible keeps everything else legible.
rem
rem The viewer replaces the WHOLE command when you override it, so every flag
rem the default had has to be repeated here.

set "AC_BIN=%~dp0..\..\bin"

rem bat falls back to 256-colour approximations without this, which muddies
rem every colour before it even reaches the screen.
set "COLORTERM=truecolor"

"%AC_BIN%\bat.exe" --color=always --style=numbers --paging=never ^
  --theme="Catppuccin Macchiato" --file-name=%1 -
