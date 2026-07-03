#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-failed.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh fail)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR/completion_event.txt" ] || { printf 'missing completion_event.txt\n' >&2; exit 1; }
grep -q '^status: FAILED$' "$RUN_DIR/completion_event.txt" || { printf 'expected FAILED\n' >&2; exit 1; }
grep -q '^exit_code: 7$' "$RUN_DIR/completion_event.txt" || { printf 'expected exit_code 7\n' >&2; exit 1; }
grep -q 'simulated failure' "$RUN_DIR/stderr.log" || { printf 'missing stderr failure text\n' >&2; exit 1; }
[ -f "$RUN_DIR/resume_prompt.txt" ] || { printf 'missing resume_prompt.txt\n' >&2; exit 1; }
printf 'ok failed completion: %s\n' "$RUN_ID"
