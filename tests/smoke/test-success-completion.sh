#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-success.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh success)
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
STATUS=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$RUN_ID")
printf '%s\n' "$STATUS" | grep -q '^LMAS_STATUS v1$' || { printf 'missing status event\n' >&2; exit 1; }
printf '%s\n' "$STATUS" | grep -q '^status: SUCCEEDED$' || { printf 'status command did not report SUCCEEDED\n' >&2; exit 1; }

ALT_CWD=$(mktemp -d "${TMPDIR:-/tmp}/lmas-success-cwd.XXXXXX")
CALLER_CWD=$(mktemp -d "${TMPDIR:-/tmp}/lmas-success-caller.XXXXXX")
ALT_OUTPUT=$(cd "$CALLER_CWD" && "$ROOT/packages/let-my-agent-sleep/bin/lmas.sh" start --adapter noop --cwd "$ALT_CWD" -- /bin/sh -c 'printf "ran\n" > cwd-marker.txt')
ALT_RUN_ID=$(printf '%s\n' "$ALT_OUTPUT" | awk '/^run_id:/ { print $2 }')
ALT_RUN_DIR="$ALT_CWD/.lmas/runs/$ALT_RUN_ID"

[ -n "$ALT_RUN_ID" ] || { printf 'missing --cwd run_id\n' >&2; exit 1; }

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$ALT_RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$ALT_RUN_DIR/completion_event.txt" ] || { printf 'missing --cwd completion_event.txt\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$ALT_RUN_DIR/completion_event.txt" || { printf 'expected --cwd SUCCEEDED\n' >&2; exit 1; }
[ -f "$ALT_CWD/cwd-marker.txt" ] || { printf 'command did not run in requested --cwd\n' >&2; exit 1; }

if [ -e "$CALLER_CWD/.lmas/runs/$ALT_RUN_ID" ]; then
  printf 'relative runs_dir was incorrectly created under caller cwd\n' >&2
  exit 1
fi

REL_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-success-relative-parent.XXXXXX")
mkdir -p "$REL_PARENT/job-cwd"
REL_OUTPUT=$(cd "$REL_PARENT" && "$ROOT/packages/let-my-agent-sleep/bin/lmas.sh" start --adapter noop --cwd job-cwd -- /bin/sh -c 'printf "ran\n" > relative-cwd-marker.txt')
REL_RUN_ID=$(printf '%s\n' "$REL_OUTPUT" | awk '/^run_id:/ { print $2 }')
REL_RUN_DIR="$REL_PARENT/job-cwd/.lmas/runs/$REL_RUN_ID"

[ -n "$REL_RUN_ID" ] || { printf 'missing relative --cwd run_id\n' >&2; exit 1; }

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$REL_RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$REL_RUN_DIR/completion_event.txt" ] || { printf 'missing relative --cwd completion_event.txt\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$REL_RUN_DIR/completion_event.txt" || { printf 'expected relative --cwd SUCCEEDED\n' >&2; exit 1; }
[ -f "$REL_PARENT/job-cwd/relative-cwd-marker.txt" ] || { printf 'command did not run in relative --cwd\n' >&2; exit 1; }

if [ -e "$REL_PARENT/job-cwd/job-cwd/.lmas/runs/$REL_RUN_ID" ]; then
  printf 'relative --cwd caused nested run directory\n' >&2
  exit 1
fi

MULTILINE_COMMAND=$(printf 'printf multi\nprintf done\n')
MULTILINE_METADATA=$(printf 'note=line1\nfinished_epoch=bad')
MULTILINE_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop --metadata "$MULTILINE_METADATA" -- /bin/sh -c "$MULTILINE_COMMAND")
MULTILINE_RUN_ID=$(printf '%s\n' "$MULTILINE_OUTPUT" | awk '/^run_id:/ { print $2 }')
MULTILINE_RUN_DIR="$RUNS_DIR/$MULTILINE_RUN_ID"

[ -n "$MULTILINE_RUN_ID" ] || { printf 'missing multiline run_id\n' >&2; exit 1; }

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$MULTILINE_RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$MULTILINE_RUN_DIR/completion_event.txt" ] || { printf 'missing multiline completion_event.txt\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$MULTILINE_RUN_DIR/completion_event.txt" || { printf 'expected multiline SUCCEEDED\n' >&2; exit 1; }
grep -q '^multidone$' "$MULTILINE_RUN_DIR/stdout.log" || { printf 'multiline command did not execute as multiline shell input\n' >&2; exit 1; }
grep -q '^note=line1 finished_epoch=bad$' "$MULTILINE_RUN_DIR/metadata.txt" || { printf 'multiline metadata was not normalized to a single line\n' >&2; exit 1; }
if grep -q '^finished_epoch=bad$' "$MULTILINE_RUN_DIR/metadata.txt"; then
  printf 'multiline metadata injected a synthetic finished_epoch line\n' >&2
  exit 1
fi
COMMAND_LINE_COUNT=$(grep -c '^command=' "$MULTILINE_RUN_DIR/metadata.txt")
[ "$COMMAND_LINE_COUNT" -eq 1 ] || { printf 'multiline command should be recorded as one metadata line\n' >&2; exit 1; }
grep -q "^command: '/bin/sh' '-c' 'printf multi printf done'$" "$MULTILINE_RUN_DIR/completion_event.txt" || {
  printf 'multiline command was not normalized in completion event\n' >&2
  exit 1
}

printf 'ok success completion: %s\n' "$RUN_ID"
