#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-success.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR/completion_event.txt" ] || { printf 'missing completion_event.txt\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'expected SUCCEEDED\n' >&2; exit 1; }
grep -q '^exit_code: 0$' "$RUN_DIR/completion_event.txt" || { printf 'expected exit_code 0\n' >&2; exit 1; }
grep -q 'metric.accuracy=0.91' "$RUN_DIR/stdout.log" || { printf 'missing stdout metric\n' >&2; exit 1; }
[ -f "$RUN_DIR/metadata.txt" ] || { printf 'missing metadata.txt\n' >&2; exit 1; }
[ ! -f "$RUN_DIR/metadata.env" ] || { printf 'metadata.env should not be created\n' >&2; exit 1; }
[ -f "$RUN_DIR/resume_prompt.txt" ] || { printf 'missing resume_prompt.txt\n' >&2; exit 1; }
STATUS=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./bin/lmas.sh status "$RUN_ID")
printf '%s\n' "$STATUS" | grep -q '^LMAS_STATUS v1$' || { printf 'missing status event\n' >&2; exit 1; }
printf '%s\n' "$STATUS" | grep -q '^status: SUCCEEDED$' || { printf 'status command did not report SUCCEEDED\n' >&2; exit 1; }
printf 'ok success completion: %s\n' "$RUN_ID"
