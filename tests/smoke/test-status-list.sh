#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-status.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR/completion_event.txt" ] || { printf 'missing completion_event.txt\n' >&2; exit 1; }

STATUS_BY_ID=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./bin/lmas.sh status "$RUN_ID")
STATUS_BY_DIR=$(cd "$ROOT" && ./bin/lmas.sh status "$RUN_DIR")
STATUS_BY_CLI=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js status "$RUN_ID")
LIST_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./bin/lmas.sh list)

printf '%s\n' "$STATUS_BY_ID" | grep -q '^LMAS_STATUS v1$' || { printf 'missing status by id event\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q '^status: SUCCEEDED$' || { printf 'status by id did not report SUCCEEDED\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_DIR" | grep -q "^run_id: $RUN_ID$" || { printf 'status by dir reported wrong run id\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_CLI" | grep -q '^LMAS_STATUS v1$' || { printf 'package cli status did not emit status event\n' >&2; exit 1; }
printf '%s\n' "$LIST_OUTPUT" | grep -q "$RUN_ID[[:space:]]*SUCCEEDED[[:space:]]*0" || { printf 'list did not include completed run\n' >&2; exit 1; }

printf 'ok status/list: %s\n' "$RUN_ID"
