#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-handoff.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh sleep 1)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

[ -n "$RUN_ID" ] || { printf 'missing run_id\n' >&2; exit 1; }
[ -f "$RUN_DIR/handoff.txt" ] || { printf 'missing handoff.txt\n' >&2; exit 1; }
grep -q '^status: STARTED$' "$RUN_DIR/handoff.txt" || { printf 'handoff did not report STARTED\n' >&2; exit 1; }

if [ -f "$RUN_DIR/completion_event.txt" ]; then
  printf 'completion was written before handoff test could observe non-blocking start\n' >&2
  exit 1
fi

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR/completion_event.txt" ] || { printf 'missing completion_event.txt\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'completion did not report SUCCEEDED\n' >&2; exit 1; }
printf 'ok basic handoff: %s\n' "$RUN_ID"
