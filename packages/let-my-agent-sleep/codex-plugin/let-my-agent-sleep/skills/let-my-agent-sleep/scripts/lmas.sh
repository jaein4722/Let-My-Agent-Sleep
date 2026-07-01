#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

for candidate in \
  "$SCRIPT_DIR/../../../../../bin/lmas.sh" \
  "$PWD/bin/lmas.sh"
do
  if [ -x "$candidate" ]; then
    exec "$candidate" "$@"
  fi
done

printf 'Could not find repo-local bin/lmas.sh. Run from the Let My Agent Sleep repo or copy bin/lmas.sh into this plugin package.\n' >&2
exit 127
