#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-install-home.XXXXXX")

FIRST_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent all --yes)
SECOND_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent all --yes)

printf '%s\n' "$FIRST_OUTPUT" | grep -q 'Let My Agent Sleep install complete' || { printf 'first install did not complete\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] write:' || { printf 'second install did not skip unchanged writes\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] copy:' || { printf 'second install did not skip unchanged file copy\n' >&2; exit 1; }
printf '%s\n' "$SECOND_OUTPUT" | grep -q '\[skip\] copy-dir:' || { printf 'second install did not skip unchanged directory copy\n' >&2; exit 1; }

if find "$TMP_HOME" -name '*.bak.*' -print -quit | grep -q .; then
  printf 'second identical install created backup files\n' >&2
  exit 1
fi

printf 'ok idempotent install\n'
