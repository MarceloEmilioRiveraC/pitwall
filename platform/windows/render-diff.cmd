@echo off
rem Diff rendering for the file viewer's content pane.
rem
rem A unified diff arrives on stdin. delta reads stdin by default, so there is
rem no trailing "-" here, unlike bat.
rem
rem delta's stock red and green are saturated enough to fight the text sitting
rem on them. These backgrounds were picked by measuring contrast against the
rem dimmest foreground the syntax theme draws (#939ab7, Macchiato's comment):
rem
rem   minus       #3a2733   comment 4.97   text 9.32
rem   plus        #22342e   comment 4.72   text 8.85
rem   minus emph  #54303e   comment 4.04   text 7.57
rem   plus emph   #2a5145   comment 3.20   text 5.99
rem
rem The two main backgrounds clear WCAG AA at 4.5. The emph pair sits lower by
rem design: it marks changed words, which are never the dim colour, and both
rem stay above 4.5 for actual changed text.
rem
rem "syntax" as the foreground keeps syntax highlighting inside the diff instead
rem of flattening every changed line to one colour.

set "AC_BIN=%~dp0..\..\bin"
set "COLORTERM=truecolor"

"%AC_BIN%\delta.exe" ^
  --paging=never ^
  --syntax-theme="Catppuccin Macchiato" ^
  --minus-style="syntax #3a2733" ^
  --minus-emph-style="syntax #54303e" ^
  --plus-style="syntax #22342e" ^
  --plus-emph-style="syntax #2a5145" ^
  --line-numbers ^
  --line-numbers-minus-style="#eb6f92" ^
  --line-numbers-plus-style="#9ccfd8" ^
  --line-numbers-zero-style="#6e6a86" ^
  --line-numbers-left-style="#44415a" ^
  --line-numbers-right-style="#44415a" ^
  --hunk-header-style="omit" ^
  --file-style="omit" ^
  --zero-style="syntax"
