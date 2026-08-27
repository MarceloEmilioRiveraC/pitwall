<#
.SYNOPSIS
  The F1 key card. Draws itself, rather than rendering a markdown file.

.DESCRIPTION
  The first version was docs/keys.md rendered through glow, and it failed the
  only test that matters: "I read this and I do not know where to start."

  Two reasons, both structural rather than a matter of wording. glow draws
  fenced code blocks as flat uncoloured text, so every line carried identical
  weight and the whole card read as one mass. And the content was ordered by
  topic instead of by urgency, so the four keys someone actually needs sat in
  the same visual rank as copy-path and annotate.

  So this draws directly. Colour separates a key from its description, blank
  lines and rules separate the zones, and the four keys that matter are alone
  at the top under a heading that says so. Everything rare moved to the bottom.

  The palette is Rose Pine Moon, the same one the rest of the bundle uses.
  Truecolor escapes, which is safe here: the pane is a ConPTY and COLORTERM is
  already set by the wrapper. Nothing here needs a pager, which is the other
  reason it is not markdown: there is no `less` on Windows, so the card has to
  fit one screen and it is easier to keep it that way when the layout is
  explicit.
#>

$e = [char]27
function C($r, $g, $b) { "$e[38;2;$r;$g;${b}m" }

$reset  = "$e[0m"
$bold   = "$e[1m"
$iris   = C 196 167 231   # headings
$foam   = C 156 207 216   # keys
$text   = C 224 222 244   # normal
$muted  = C 110 106 134   # descriptions, rules
$love   = C 235 111 146   # warnings
$gold   = C 246 193 119   # pointers

# key column, description column
function Row($key, $desc) {
    '    {0}{1}{2}{3}  {4}{5}{6}' -f $foam, $bold, $key.PadRight(16), $reset, $muted, $desc, $reset
}
function Head($t, $note) {
    ''
    '  {0}{1}{2}{3}   {4}{5}{6}' -f $iris, $bold, $t, $reset, $muted, $note, $reset
}
function Rule { '  {0}{1}{2}' -f $muted, ('-' * 70), $reset }

$out = @()
$out += ''
$out += '  {0}{1}pitwall keys{2}      {3}any key closes this{4}' -f $iris, $bold, $reset, $muted, $reset
$out += ''
$out += '  {0}{1}THE FOUR YOU NEED{2}' -f $gold, $bold, $reset
$out += (Row 'F1'         'this card, from anywhere, no prefix')
$out += (Row 'ctrl+b  f'  'show or hide the file panel')
$out += (Row 'ctrl+b  z'  'zoom the focused pane full screen')
$out += (Row 'ctrl+b  ?'  'every herdr key there is')
$out += ''
$out += (Rule)
$out += '  {0}{1}WHERE YOU ARE DECIDES WHICH KEYS WORK{2}' -f $iris, $bold, $reset

$out += (Head 'AGENT PANE' 'Claude Code')
$out += (Row 'esc'          'interrupt the agent')
$out += (Row 'ctrl+b  h l'  'move focus left or right')

$out += (Head 'FILE PANEL' 'single keys. no ctrl, no prefix')
$out += (Row '] ['          'next / previous CHANGED file          <- the loop')
$out += (Row 'e'            'EDIT it, opens beside the tree')
$out += (Row 'enter   tab'  'open file   /   tree <-> content')
$out += (Row 'c   d   D'    'only changed  /  diffs  /  diff style')
$out += (Row 'f   /'        'find a file  /  search inside this one')
$out += (Row 'A  then  y'   'annotate for the agent, then copy it')
$out += (Row 'esc  or  q'   'CLOSES the panel. ctrl+b f brings it back')

$out += (Head 'EDITOR' 'micro. it repeats these on its own bottom row')
$out += (Row 'ctrl+s  ctrl+q'  'save   /   quit')

$out += ''
$out += (Rule)
$out += '  {0}{1}WATCH OUT{2}' -f $love, $bold, $reset
$out += '    {0}{1}esc{2}       {3}interrupts in the agent pane, CLOSES in the file panel{4}' -f $love, $bold, $reset, $muted, $reset
$out += '    {0}{1}ctrl+b{2}    {3}twice in a row makes Claude background its task{4}' -f $love, $bold, $reset, $muted, $reset
$out += ''
$out += (Rule)
$out += '  {0}{1}THE REST{2}   {3}all with the ctrl+b prefix{4}' -f $muted, $bold, $reset, $muted, $reset
$out += '    {0}c n p 1-9{1} tabs     {2}w{3} projects   {4}b{5} sidebar   {6}x{7} close pane   {8}q{9} detach' -f $foam, $reset, $foam, $reset, $foam, $reset, $foam, $reset, $foam, $reset
$out += '    {0}alt+g{1} lazygit      {2}v{3} split beside     {4}-{5} split below     {6}r{7} resize' -f $foam, $reset, $foam, $reset, $foam, $reset, $foam, $reset
$out += ''

$out | ForEach-Object { Write-Host $_ }
