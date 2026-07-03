#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

for candidate in \
  "$SCRIPT_DIR/../bin/lmas.sh" \
  "$SCRIPT_DIR/../../../bin/lmas.sh" \
  "$SCRIPT_DIR/../../../../../bin/lmas.sh" \
  "$PWD/packages/let-my-agent-sleep/bin/lmas.sh"
do
  if [ -x "$candidate" ]; then
    exec "$candidate" "$@"
  fi
done

if command -v lmas >/dev/null 2>&1; then
  exec lmas "$@"
fi

printf 'Could not find bin/lmas.sh in the installed Let My Agent Sleep plugin, repo, current workspace, or PATH.\n' >&2
exit 127
