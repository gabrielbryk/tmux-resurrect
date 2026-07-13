#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d)
SOCKET="resurrect-companion-$$"
RESURRECT_DIR="$TEST_ROOT/resurrect"
HOOK="$TEST_ROOT/companion-hook.sh"
STATUS_FILE="$TEST_ROOT/save-status"
trap 'tmux -L "$SOCKET" kill-server 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT INT TERM

mkdir -p "$RESURRECT_DIR"

cat >"$HOOK" <<'HOOK_EOF'
#!/usr/bin/env bash
set -euo pipefail
layout_tmp="$1"
layout_final="${layout_tmp%.tmp}"
manifest="${layout_final%.*}.assistants.json"
printf '{"layout":"%s"}\n' "$(basename "$layout_final")" >"${manifest}.tmp"
mv -f "${manifest}.tmp" "$manifest"
HOOK_EOF
chmod +x "$HOOK"

tmux -L "$SOCKET" -f /dev/null new-session -d -s atomic
tmux -L "$SOCKET" set-option -g @resurrect-dir "$RESURRECT_DIR"
tmux -L "$SOCKET" set-option -g @resurrect-companion-suffix '.assistants.json'
tmux -L "$SOCKET" set-option -g @resurrect-hook-post-save-layout "$HOOK"
tmux -L "$SOCKET" run-shell "$ROOT_DIR/scripts/save.sh quiet; printf '%s\\n' \$? >'$STATUS_FILE'"
[ "$(cat "$STATUS_FILE")" -eq 0 ]

[ -L "$RESURRECT_DIR/last" ]
first_target=$(readlink "$RESURRECT_DIR/last")
first_layout="$RESURRECT_DIR/$first_target"
first_manifest="${first_layout%.*}.assistants.json"
[ -s "$first_layout" ]
[ -s "$first_manifest" ]

sleep 1
tmux -L "$SOCKET" set-option -g @resurrect-hook-post-save-layout 'false'
tmux -L "$SOCKET" run-shell "$ROOT_DIR/scripts/save.sh quiet; printf '%s\\n' \$? >'$STATUS_FILE'" 2>/dev/null || true
[ "$(cat "$STATUS_FILE")" -ne 0 ]

[ "$(readlink "$RESURRECT_DIR/last")" = "$first_target" ]
[ -s "$first_layout" ]
[ -s "$first_manifest" ]
[ "$(find "$RESURRECT_DIR" -maxdepth 1 -name 'tmux_resurrect_*.txt' | wc -l)" -eq 1 ]
[ "$(find "$RESURRECT_DIR" -maxdepth 1 -name 'tmux_resurrect_*.assistants.json' | wc -l)" -eq 1 ]

printf 'PASS: companion pair promotion is atomic and preserves the previous save on hook failure\n'
