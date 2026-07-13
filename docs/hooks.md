# Save & Restore Hooks

Hooks allow to set custom commands that will be executed during session save
and restore. Most hooks are called with zero arguments, unless explicitly
stated otherwise.

Currently the following hooks are supported:

- `@resurrect-hook-post-save-layout`

  Called after all sessions, panes and windows have been saved.
  Receives the staged layout path as its first argument. A non-zero exit aborts
  the save and preserves the previous `last` target.

  Passed single argument of the state file.

- `@resurrect-hook-post-save-all`

  Called at end of save process right before the spinner is turned off.

## Transactional companion files

A post-save hook can require a versioned file to be committed with each tmux
layout:

```tmux
set -g @resurrect-companion-suffix '.assistants.json'
set -g @resurrect-hook-post-save-layout '/path/to/save-companion.sh'
```

For staged layout `tmux_resurrect_20260712T120000.txt.tmp`, the hook must return
success after atomically creating the non-empty companion
`tmux_resurrect_20260712T120000.assistants.json`. Resurrect validates both files
before atomically moving `last` to the new layout. A failed hook, empty
companion, invalid layout, or failed pane archive leaves the previous pair
selected. Backup pruning removes the layout and companion together.

- `@resurrect-hook-pre-restore-all`

  Called before any tmux state is altered.

- `@resurrect-hook-pre-restore-pane-processes`

  Called before running processes are restored.

### Examples

Here is an example how to save and restore window geometry for most terminals in X11.
Add this to `.tmux.conf`:

    set -g @resurrect-hook-post-save-all 'eval $(xdotool getwindowgeometry --shell $WINDOWID); echo 0,$X,$Y,$WIDTH,$HEIGHT > $HOME/.tmux/resurrect/geometry'
    set -g @resurrect-hook-pre-restore-all 'wmctrl -i -r $WINDOWID -e $(cat $HOME/.tmux/resurrect/geometry)'
