#!/usr/bin/env bash
# Record demo/demo.cast and render demo/demo.gif.
# Needs: tmux, asciinema 3, agg, and a server seeded with demo/seed.js at $MONGODB_URI.
set -euo pipefail
cd "$(dirname "$0")/.."

export MONGODB_URI=${MONGODB_URI:-mongodb://localhost:27118}
editor=${EDITOR_CMD:-vim}
session=mongodb-demo
work=$(mktemp -d)
cp demo/demo.mongodb "$work/demo.mongodb"

tmux kill-session -t "$session" 2>/dev/null || true
tmux new-session -d -s "$session" -x 110 -y 32
tmux send-keys -t "$session" "asciinema rec --overwrite --idle-time-limit 2 --window-size 110x32 \
  -c 'cd $work && MONGODB_URI=$MONGODB_URI $editor -Nu $PWD/demo/vimrc demo.mongodb' $PWD/demo/demo.cast; tmux wait-for -S $session" Enter

keys() { tmux send-keys -t "$session" "$@"; }
typ() { # type text one character at a time
  local s=$1 i
  for ((i = 0; i < ${#s}; i++)); do
    tmux send-keys -t "$session" -l "${s:i:1}"
    sleep 0.08
  done
}
pause() { sleep "${1:-1}"; }

pause 3
# Hover a collection: count, indexes, sampled schema
keys 6G 0 4l; pause 1; keys K; pause 3.5
# Run the multi-line statement under the cursor
keys 7G; pause 0.5; typ ' rr'; pause 3
# Hover an aggregation stage, then run the pipeline
keys 13G 0 4l; pause 0.5; keys K; pause 2.5
keys j; typ ' rr'; pause 3
# Completion: collections, methods (with docs), fields (with types)
keys G o; pause 0.5
typ 'db.'; pause 2
typ 'us'; pause 1; keys C-n; pause 0.5; keys C-y
typ '.fi'; pause 1; keys C-n; pause 2.5; keys C-y
typ '({ add'; pause 2; keys C-n C-n; pause 1; keys C-y
typ ": 'Tokyo' }, { name: 1, _id: 0 })"; keys Escape; pause 1
typ ' rr'; pause 3
keys Escape; typ ':qa!'; keys Enter

tmux wait-for "$session"
tmux kill-session -t "$session"

# Drop the recorded command: it contains local paths.
{ head -1 demo/demo.cast | jq -c "del(.command)"; tail -n +2 demo/demo.cast; } >"$work.cast" && mv "$work.cast" demo/demo.cast
agg --theme monokai --font-size 16 demo/demo.cast demo/demo.gif
rm -rf "$work"
