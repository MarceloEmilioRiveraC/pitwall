# pitwall keys

Which keys work depends on **which pane has focus**. Three sets:

```
ctrl+b then ...                          WORKS ANYWHERE
  i  this card       f  file panel        z  zoom pane full screen
  (ctrl+alt+k opens this card WITHOUT the prefix, if ctrl+b is misbehaving)
  ?  all herdr keys  b  agent sidebar     x  close pane
  h j k l  move focus  left down up right
  c  new tab    n p  next / prev tab    1..9  jump to tab
  w  projects   alt+g  lazygit          q  detach, keeps running
```

```
IN THE FILE PANEL                  single keys, no ctrl, no prefix
  ] [  next / previous CHANGED file        <- start here
  enter open   tab  tree <-> content       e  EDIT beside the tree
  c  only changed   d  diffs               D  diff style
  f  find file      /  search  n N  hits   z  hide tree
  y Y  copy path    A  annotate for agent  ?  all viewer keys
  esc or q  CLOSES the panel   ->  ctrl+b f brings it back
```

```
WHILE EDITING (micro)              it repeats these on its bottom row
  ctrl+s  save    ctrl+q  quit    ctrl+z  undo    ctrl+f  find
```

```
CAREFUL                            same key, other pane, other job
  esc  in the agent pane  = interrupt the agent
  esc  in the file panel  = close the panel

STUCK?
  forgot a key      ctrl+b i          panel gone       ctrl+b f
  plain PS prompt   press enter       nothing responds check the focus
```

*Press any key to close.*
