#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-cancel.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"
WORK_DIR="$TMPDIR_ROOT/work"
mkdir -p "$WORK_DIR"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop --cwd "$WORK_DIR" -- sleep 20)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  STATUS=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$RUN_ID")
  printf '%s\n' "$STATUS" | grep -q '^status: RUNNING$' && break
  sleep 0.1
done

printf '%s\n' "$STATUS" | grep -q '^status: RUNNING$' || { printf 'run did not enter RUNNING state before cancel\n' >&2; exit 1; }
printf '%s\n' "$STATUS" | grep -q '^agent_instruction: stop now;' || { printf 'running status did not include no-poll instruction\n' >&2; exit 1; }

CANCEL_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh cancel --reason smoke-test "$RUN_ID")

printf '%s\n' "$CANCEL_OUTPUT" | grep -q '^LMAS_CANCEL v1$' || { printf 'cancel did not emit cancel event\n' >&2; exit 1; }
printf '%s\n' "$CANCEL_OUTPUT" | grep -q '^status: CANCELLED$' || { printf 'cancel did not report CANCELLED\n' >&2; exit 1; }
[ -f "$RUN_DIR/completion_event.txt" ] || { printf 'cancel did not write completion_event.txt\n' >&2; exit 1; }
[ -f "$RUN_DIR/resume_prompt.txt" ] || { printf 'cancel did not write resume_prompt.txt\n' >&2; exit 1; }
grep -q '^status: CANCELLED$' "$RUN_DIR/completion_event.txt" || { printf 'completion event did not report CANCELLED\n' >&2; exit 1; }
grep -q '^exit_code: 130$' "$RUN_DIR/completion_event.txt" || { printf 'completion event did not report exit_code 130\n' >&2; exit 1; }
grep -q '^130$' "$RUN_DIR/exit_code" || { printf 'exit_code file did not contain 130\n' >&2; exit 1; }
grep -q '^cancel_reason=smoke-test$' "$RUN_DIR/metadata.txt" || { printf 'cancel reason missing from metadata\n' >&2; exit 1; }

STATUS_AFTER=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$RUN_ID")
printf '%s\n' "$STATUS_AFTER" | grep -q '^status: CANCELLED$' || { printf 'status did not report CANCELLED after cancel\n' >&2; exit 1; }

LOST_RUN_ID="lmas_cancel_lost_test"
LOST_RUN_DIR="$RUNS_DIR/$LOST_RUN_ID"
mkdir -p "$LOST_RUN_DIR"
cat > "$LOST_RUN_DIR/handoff.txt" <<EOF
LMAS_HANDOFF v1
run_id: $LOST_RUN_ID
status: STARTED
cwd: $ROOT
command: 'sleep' '999'
pid_or_job_id: tmux:lmas_missing_session
stdout: $LOST_RUN_DIR/stdout.log
stderr: $LOST_RUN_DIR/stderr.log
metadata: $LOST_RUN_DIR/metadata.txt
artifacts_dir: $LOST_RUN_DIR
started_at: 2026-07-01T00:00:00+09:00
resume_instruction: Wait for completion event or inspect $LOST_RUN_DIR/resume_prompt.txt after the job exits.
EOF
printf 'cwd=%s\nadapter=noop\nartifacts_dir=%s\ncommand=%s\n' "$WORK_DIR" "$LOST_RUN_DIR" "'sleep' '999'" > "$LOST_RUN_DIR/metadata.txt"

LOST_CANCEL_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh cancel "$LOST_RUN_ID")
printf '%s\n' "$LOST_CANCEL_OUTPUT" | grep -q '^status: LOST$' || { printf 'cancel should preserve LOST for missing watcher\n' >&2; exit 1; }
[ ! -f "$LOST_RUN_DIR/completion_event.txt" ] || { printf 'lost cancel should not write completion event\n' >&2; exit 1; }

printf 'ok cancel: %s\n' "$RUN_ID"
