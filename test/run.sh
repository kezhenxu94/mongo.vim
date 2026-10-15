#!/usr/bin/env bash
# Run the test suite in Vim and Neovim against a throwaway MongoDB container.
# Set MONGODB_URI to use an existing server instead (it gets demo/seed.js data).
set -euo pipefail
cd "$(dirname "$0")/.."

container=mongodb-vim-test
if [[ -z "${MONGODB_URI:-}" ]]; then
  export MONGODB_URI=mongodb://localhost:27118
  if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    docker run -d --rm --name "$container" -p 27118:27017 mongo:8 >/dev/null
    trap 'docker stop "$container" >/dev/null' EXIT
  fi
  until mongosh "$MONGODB_URI" --quiet --eval 1 >/dev/null 2>&1; do sleep 0.5; done
fi
mongosh "$MONGODB_URI" --quiet demo/seed.js

status=0
export TEST_RESULT
TEST_RESULT=$(mktemp)
for editor in vim nvim; do
  command -v "$editor" >/dev/null || continue
  echo "== $editor"
  if [[ $editor == vim ]]; then
    cmd=(vim -Nu NONE -i NONE -es)
  else
    cmd=(nvim --headless -u NONE -i NONE)
  fi
  "${cmd[@]}" --cmd 'set rtp^=.' -c 'filetype plugin on | syntax on' -S test/test_mongodb.vim </dev/null || status=1
  cat "$TEST_RESULT"
done
rm -f "$TEST_RESULT"
exit $status
