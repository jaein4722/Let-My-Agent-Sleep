#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-status.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"
CLI_START_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js start --adapter noop -- ./examples/fake_train.sh success)
CLI_START_RUN_ID=$(printf '%s\n' "$CLI_START_OUTPUT" | awk '/^run_id:/ { print $2 }')
CLI_START_RUN_DIR="$RUNS_DIR/$CLI_START_RUN_ID"

[ -n "$CLI_START_RUN_ID" ] || { printf 'package cli start did not emit run_id\n' >&2; exit 1; }
printf '%s\n' "$CLI_START_OUTPUT" | grep -q '^LMAS_HANDOFF v1$' || { printf 'package cli start did not emit handoff event\n' >&2; exit 1; }

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$CLI_START_RUN_DIR/completion_event.txt" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR/completion_event.txt" ] || { printf 'missing completion_event.txt\n' >&2; exit 1; }
[ -f "$CLI_START_RUN_DIR/completion_event.txt" ] || { printf 'missing package cli start completion_event.txt\n' >&2; exit 1; }
printf 'step=12 loss=0.42\n' > "$RUN_DIR/progress.txt"

STATUS_BY_ID=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$RUN_ID")
STATUS_BY_DIR=$(cd "$ROOT" && ./packages/let-my-agent-sleep/bin/lmas.sh status "$RUN_DIR")
STATUS_BY_CLI=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js status "$RUN_ID")
CLI_START_STATUS_BY_CLI=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js status "$CLI_START_RUN_ID")
LIST_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh list)
LIST_BY_CLI=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js list)
LOST_RUN_ID="lmas_lost_test"
LOST_RUN_DIR="$RUNS_DIR/$LOST_RUN_ID"
mkdir -p "$LOST_RUN_DIR"
cat > "$LOST_RUN_DIR/handoff.txt" <<EOF
LMAS_HANDOFF v1
run_id: $LOST_RUN_ID
status: STARTED
cwd: $ROOT
command: 'sleep' '999'
pid_or_job_id: 999999999
stdout: $LOST_RUN_DIR/stdout.log
stderr: $LOST_RUN_DIR/stderr.log
metadata: $LOST_RUN_DIR/metadata.txt
artifacts_dir: $LOST_RUN_DIR
started_at: 2026-07-01T00:00:00Z
resume_instruction: Wait for completion event or inspect $LOST_RUN_DIR/resume_prompt.txt after the job exits.
EOF
LOST_STATUS=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$LOST_RUN_ID")
TMUX_LOST_RUN_ID="lmas_tmux_lost_test"
TMUX_LOST_RUN_DIR="$RUNS_DIR/$TMUX_LOST_RUN_ID"
mkdir -p "$TMUX_LOST_RUN_DIR"
cat > "$TMUX_LOST_RUN_DIR/handoff.txt" <<EOF
LMAS_HANDOFF v1
run_id: $TMUX_LOST_RUN_ID
status: STARTED
cwd: $ROOT
command: 'sleep' '999'
pid_or_job_id: tmux:lmas_missing_session
stdout: $TMUX_LOST_RUN_DIR/stdout.log
stderr: $TMUX_LOST_RUN_DIR/stderr.log
metadata: $TMUX_LOST_RUN_DIR/metadata.txt
artifacts_dir: $TMUX_LOST_RUN_DIR
started_at: 2026-07-01T00:00:00Z
resume_instruction: Wait for completion event or inspect $TMUX_LOST_RUN_DIR/resume_prompt.txt after the job exits.
EOF
TMUX_LOST_STATUS=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$TMUX_LOST_RUN_ID")
printf '%s\n' "$STATUS_BY_ID" | grep -q '^LMAS_STATUS v1$' || { printf 'missing status by id event\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q '^status: SUCCEEDED$' || { printf 'status by id did not report SUCCEEDED\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^run_dir: $RUN_DIR$" || { printf 'status by id missing run_dir\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^stdout: $RUN_DIR/stdout.log$" || { printf 'status by id missing stdout path\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^stderr: $RUN_DIR/stderr.log$" || { printf 'status by id missing stderr path\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^metadata: $RUN_DIR/metadata.txt$" || { printf 'status by id missing metadata path\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^watcher_log: $RUN_DIR/watcher.log$" || { printf 'status by id missing watcher log path\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^adapter_log: $RUN_DIR/adapter.log$" || { printf 'status by id missing adapter log path\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^resume_prompt: $RUN_DIR/resume_prompt.txt$" || { printf 'status by id missing resume prompt path\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -Eq '^elapsed_seconds: [0-9]+$' || { printf 'status by id missing elapsed_seconds\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^command: './examples/fake_train.sh' 'success'$" || { printf 'status by id missing command\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q '^progress: step=12 loss=0.42$' || { printf 'status by id missing progress\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_ID" | grep -q "^progress_path: $RUN_DIR/progress.txt$" || { printf 'status by id missing progress path\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_DIR" | grep -q "^run_id: $RUN_ID$" || { printf 'status by dir reported wrong run id\n' >&2; exit 1; }
printf '%s\n' "$STATUS_BY_CLI" | grep -q '^LMAS_STATUS v1$' || { printf 'package cli status did not emit status event\n' >&2; exit 1; }
printf '%s\n' "$CLI_START_STATUS_BY_CLI" | grep -q '^status: SUCCEEDED$' || { printf 'package cli started run did not report SUCCEEDED\n' >&2; exit 1; }
grep -Eq '^started_epoch=[0-9]+$' "$RUN_DIR/metadata.txt" || { printf 'metadata missing started_epoch\n' >&2; exit 1; }
grep -Eq '^finished_epoch=[0-9]+$' "$RUN_DIR/metadata.txt" || { printf 'metadata missing finished_epoch\n' >&2; exit 1; }
printf '%s\n' "$LIST_OUTPUT" | grep -q $'run_id\tstatus\texit_code\telapsed_seconds\tcommand\trun_dir' || { printf 'list header missing observability columns\n' >&2; exit 1; }
printf '%s\n' "$LIST_OUTPUT" | grep -q "$RUN_ID[[:space:]]*SUCCEEDED[[:space:]]*0" || { printf 'list did not include completed run\n' >&2; exit 1; }
printf '%s\n' "$LIST_OUTPUT" | grep -q "$RUN_ID[[:space:]]*SUCCEEDED[[:space:]]*0[[:space:]]*[0-9][0-9]*[[:space:]]*'./examples/fake_train.sh' 'success'" || { printf 'list did not include elapsed command summary\n' >&2; exit 1; }
printf '%s\n' "$LIST_OUTPUT" | grep -q "$CLI_START_RUN_ID[[:space:]]*SUCCEEDED[[:space:]]*0" || { printf 'list did not include package cli started run\n' >&2; exit 1; }
printf '%s\n' "$LIST_BY_CLI" | grep -q "$RUN_ID[[:space:]]*SUCCEEDED[[:space:]]*0" || { printf 'package cli list did not include completed run\n' >&2; exit 1; }
printf '%s\n' "$LIST_BY_CLI" | grep -q "$CLI_START_RUN_ID[[:space:]]*SUCCEEDED[[:space:]]*0" || { printf 'package cli list did not include package cli started run\n' >&2; exit 1; }
printf '%s\n' "$LOST_STATUS" | grep -q '^status: LOST$' || { printf 'lost run did not report LOST\n' >&2; exit 1; }
printf '%s\n' "$LOST_STATUS" | grep -q "^run_dir: $LOST_RUN_DIR$" || { printf 'lost status missing run_dir\n' >&2; exit 1; }
printf '%s\n' "$LOST_STATUS" | grep -q "^watcher_log: $LOST_RUN_DIR/watcher.log$" || { printf 'lost status missing watcher log path\n' >&2; exit 1; }
if printf '%s\n' "$LOST_STATUS" | grep -q '^resume_prompt: '; then
  printf 'lost status should not report resume_prompt before completion\n' >&2
  exit 1
fi
printf '%s\n' "$TMUX_LOST_STATUS" | grep -q '^status: LOST$' || { printf 'missing tmux session did not report LOST\n' >&2; exit 1; }

printf 'ok status/list: %s\n' "$RUN_ID"
