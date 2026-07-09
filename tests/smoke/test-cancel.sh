#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-cancel.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"
WORK_DIR="$TMPDIR_ROOT/work"
mkdir -p "$WORK_DIR"
CHILD_SCRIPT="$TMPDIR_ROOT/cancel-child.sh"
cat > "$CHILD_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$$" > "$1/child.pid"
trap 'printf TERM > "$1/term.txt"; exit 143' TERM HUP INT
sleep 20
EOF
chmod +x "$CHILD_SCRIPT"

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop --cwd "$WORK_DIR" -- "$CHILD_SCRIPT" "$TMPDIR_ROOT")
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in $(seq 1 100); do
  STATUS=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$RUN_ID")
  printf '%s\n' "$STATUS" | grep -q '^status: RUNNING$' && break
  sleep 0.1
done

printf '%s\n' "$STATUS" | grep -q '^status: RUNNING$' || { printf 'run did not enter RUNNING state before cancel\n' >&2; exit 1; }
printf '%s\n' "$STATUS" | grep -q '^agent_instruction: stop now;' || { printf 'running status did not include no-poll instruction\n' >&2; exit 1; }

for _ in $(seq 1 100); do
  [ -f "$TMPDIR_ROOT/child.pid" ] && break
  sleep 0.1
done
[ -f "$TMPDIR_ROOT/child.pid" ] || {
  printf 'child pid was not recorded before cancel\n' >&2
  [ -f "$RUN_DIR/watcher.log" ] && sed -n '1,160p' "$RUN_DIR/watcher.log" >&2
  [ -f "$RUN_DIR/stdout.log" ] && sed -n '1,80p' "$RUN_DIR/stdout.log" >&2
  [ -f "$RUN_DIR/stderr.log" ] && sed -n '1,80p' "$RUN_DIR/stderr.log" >&2
  exit 1
}
CHILD_PID=$(sed -n '1p' "$TMPDIR_ROOT/child.pid")

CANCEL_REASON=$(printf 'smoke-test\nfinished_epoch=bad')
CANCEL_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js cancel --reason "$CANCEL_REASON" "$RUN_ID")

printf '%s\n' "$CANCEL_OUTPUT" | grep -q '^LMAS_CANCEL v1$' || { printf 'cancel did not emit cancel event\n' >&2; exit 1; }
printf '%s\n' "$CANCEL_OUTPUT" | grep -q '^status: CANCELLED$' || { printf 'cancel did not report CANCELLED\n' >&2; exit 1; }
[ -f "$RUN_DIR/completion_event.txt" ] || { printf 'cancel did not write completion_event.txt\n' >&2; exit 1; }
[ -f "$RUN_DIR/resume_prompt.txt" ] || { printf 'cancel did not write resume_prompt.txt\n' >&2; exit 1; }
grep -q '^status: CANCELLED$' "$RUN_DIR/completion_event.txt" || { printf 'completion event did not report CANCELLED\n' >&2; exit 1; }
grep -q '^exit_code: 130$' "$RUN_DIR/completion_event.txt" || { printf 'completion event did not report exit_code 130\n' >&2; exit 1; }
grep -q '^130$' "$RUN_DIR/exit_code" || { printf 'exit_code file did not contain 130\n' >&2; exit 1; }
grep -q '^cancel_reason=smoke-test finished_epoch=bad$' "$RUN_DIR/metadata.txt" || { printf 'cancel reason missing from metadata\n' >&2; exit 1; }
if grep -q '^finished_epoch=bad$' "$RUN_DIR/metadata.txt"; then
  printf 'multiline cancel reason injected a metadata field\n' >&2
  exit 1
fi
grep -q '^cancel_watcher_pid=' "$RUN_DIR/metadata.txt" || { printf 'cancel watcher pid missing from metadata\n' >&2; exit 1; }
grep -q "^cancel_child_pid=$CHILD_PID$" "$RUN_DIR/metadata.txt" || { printf 'cancel child pid missing from metadata\n' >&2; exit 1; }
grep -q '^cancel_killed_pids=' "$RUN_DIR/metadata.txt" || { printf 'cancel killed pids missing from metadata\n' >&2; exit 1; }
if grep -q '^cancel_surviving_pids=' "$RUN_DIR/metadata.txt"; then
  printf 'cancel should not report surviving pids for TERM-aware child\n' >&2
  exit 1
fi

sleep 0.2
if kill -0 "$CHILD_PID" >/dev/null 2>&1; then
  printf 'cancel left child process alive: %s\n' "$CHILD_PID" >&2
  exit 1
fi
[ -f "$TMPDIR_ROOT/term.txt" ] || { printf 'child did not receive termination signal\n' >&2; exit 1; }

STATUS_AFTER=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$RUN_ID")
printf '%s\n' "$STATUS_AFTER" | grep -q '^status: CANCELLED$' || { printf 'status did not report CANCELLED after cancel\n' >&2; exit 1; }
LIST_AFTER=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh list)
printf '%s\n' "$LIST_AFTER" | grep -q "$RUN_ID[[:space:]]*CANCELLED[[:space:]]*130" || { printf 'list did not report CANCELLED after cancel\n' >&2; exit 1; }
LIST_AFTER_BY_CLI=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js list)
printf '%s\n' "$LIST_AFTER_BY_CLI" | grep -q "$RUN_ID[[:space:]]*CANCELLED[[:space:]]*130" || { printf 'package cli list did not report CANCELLED after cancel\n' >&2; exit 1; }

IGNORE_SCRIPT="$TMPDIR_ROOT/ignore-child.sh"
cat > "$IGNORE_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$$" > "$1/ignore-parent.pid"
trap '' TERM HUP INT
sleep 20 &
printf '%s\n' "$!" > "$1/ignore-grandchild.pid"
wait "$!"
EOF
chmod +x "$IGNORE_SCRIPT"

IGNORE_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop --cwd "$WORK_DIR" -- "$IGNORE_SCRIPT" "$TMPDIR_ROOT")
IGNORE_RUN_ID=$(printf '%s\n' "$IGNORE_OUTPUT" | awk '/^run_id:/ { print $2 }')
IGNORE_RUN_DIR="$RUNS_DIR/$IGNORE_RUN_ID"

for _ in $(seq 1 100); do
  [ -f "$TMPDIR_ROOT/ignore-parent.pid" ] && [ -f "$TMPDIR_ROOT/ignore-grandchild.pid" ] && break
  sleep 0.1
done

[ -f "$TMPDIR_ROOT/ignore-parent.pid" ] || {
  printf 'ignore parent pid was not recorded before cancel\n' >&2
  [ -f "$IGNORE_RUN_DIR/watcher.log" ] && sed -n '1,160p' "$IGNORE_RUN_DIR/watcher.log" >&2
  exit 1
}
[ -f "$TMPDIR_ROOT/ignore-grandchild.pid" ] || {
  printf 'ignore grandchild pid was not recorded before cancel\n' >&2
  [ -f "$IGNORE_RUN_DIR/watcher.log" ] && sed -n '1,160p' "$IGNORE_RUN_DIR/watcher.log" >&2
  exit 1
}
IGNORE_PARENT_PID=$(sed -n '1p' "$TMPDIR_ROOT/ignore-parent.pid")
IGNORE_GRANDCHILD_PID=$(sed -n '1p' "$TMPDIR_ROOT/ignore-grandchild.pid")

IGNORE_CANCEL_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js cancel --reason ignore-smoke-test "$IGNORE_RUN_ID")
printf '%s\n' "$IGNORE_CANCEL_OUTPUT" | grep -q '^status: CANCELLED$' || { printf 'ignore cancel did not report CANCELLED\n' >&2; exit 1; }
grep -q '^status: CANCELLED$' "$IGNORE_RUN_DIR/completion_event.txt" || { printf 'ignore completion event did not report CANCELLED\n' >&2; exit 1; }
IGNORE_STATUS_AFTER=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$IGNORE_RUN_ID")
printf '%s\n' "$IGNORE_STATUS_AFTER" | grep -q '^status: CANCELLED$' || { printf 'ignore status did not report CANCELLED after cancel\n' >&2; exit 1; }
grep -q '^cancel_watcher_pid=' "$IGNORE_RUN_DIR/metadata.txt" || { printf 'ignore cancel watcher pid missing from metadata\n' >&2; exit 1; }
grep -q "^cancel_child_pid=$IGNORE_PARENT_PID$" "$IGNORE_RUN_DIR/metadata.txt" || { printf 'ignore cancel child pid missing from metadata\n' >&2; exit 1; }
grep -q "$IGNORE_GRANDCHILD_PID" "$IGNORE_RUN_DIR/metadata.txt" || { printf 'ignore cancel grandchild pid missing from metadata\n' >&2; exit 1; }
if grep -q '^cancel_surviving_pids=' "$IGNORE_RUN_DIR/metadata.txt"; then
  printf 'cancel should not report surviving pids after KILL fallback\n' >&2
  exit 1
fi

sleep 0.3
if kill -0 "$IGNORE_PARENT_PID" >/dev/null 2>&1; then
  printf 'cancel left TERM-ignoring parent process alive: %s\n' "$IGNORE_PARENT_PID" >&2
  kill -KILL "$IGNORE_PARENT_PID" >/dev/null 2>&1 || true
  exit 1
fi
if kill -0 "$IGNORE_GRANDCHILD_PID" >/dev/null 2>&1; then
  printf 'cancel left grandchild process alive: %s\n' "$IGNORE_GRANDCHILD_PID" >&2
  kill -KILL "$IGNORE_GRANDCHILD_PID" >/dev/null 2>&1 || true
  exit 1
fi

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

LOST_CANCEL_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js cancel "$LOST_RUN_ID")
printf '%s\n' "$LOST_CANCEL_OUTPUT" | grep -q '^status: LOST$' || { printf 'cancel should preserve LOST for missing watcher\n' >&2; exit 1; }
[ ! -f "$LOST_RUN_DIR/completion_event.txt" ] || { printf 'lost cancel should not write completion event\n' >&2; exit 1; }

RACE_RUN_ID="lmas_cancel_race_test"
RACE_RUN_DIR="$RUNS_DIR/$RACE_RUN_ID"
RACE_MOCK_BIN="$TMPDIR_ROOT/race-bin"
mkdir -p "$RACE_RUN_DIR" "$RACE_MOCK_BIN"
cat > "$RACE_RUN_DIR/handoff.txt" <<EOF
LMAS_HANDOFF v1
run_id: $RACE_RUN_ID
status: STARTED
cwd: $ROOT
command: 'sleep' '999'
pid_or_job_id: tmux:lmas_race_session
stdout: $RACE_RUN_DIR/stdout.log
stderr: $RACE_RUN_DIR/stderr.log
metadata: $RACE_RUN_DIR/metadata.txt
artifacts_dir: $RACE_RUN_DIR
started_at: 2026-07-01T00:00:00+09:00
resume_instruction: Wait for completion event or inspect $RACE_RUN_DIR/resume_prompt.txt after the job exits.
EOF
printf 'cwd=%s\nadapter=noop\nartifacts_dir=%s\ncommand=%s\n' "$WORK_DIR" "$RACE_RUN_DIR" "'sleep' '999'" > "$RACE_RUN_DIR/metadata.txt"
cat > "$RACE_MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -u
case "$*" in
  *"has-session"*)
    exit 0
    ;;
  *"kill-session"*)
    cat > "$LMAS_RACE_RUN_DIR/completion_event.txt" <<EVENT
LMAS_COMPLETION_EVENT v1
run_id: lmas_cancel_race_test
status: SUCCEEDED
exit_code: 0
cwd: $PWD
command: 'sleep' '999'
stdout: $LMAS_RACE_RUN_DIR/stdout.log
stderr: $LMAS_RACE_RUN_DIR/stderr.log
metadata: $LMAS_RACE_RUN_DIR/metadata.txt
artifacts_dir: $LMAS_RACE_RUN_DIR
finished_at: 2026-07-01T00:00:01+09:00
EVENT
    exit 1
    ;;
  *"display-message"*)
    printf '999999999\n'
    exit 0
    ;;
esac
exit 1
EOF
chmod +x "$RACE_MOCK_BIN/tmux"
RACE_CANCEL_OUTPUT=$(cd "$ROOT" && PATH="$RACE_MOCK_BIN:$PATH" LMAS_RUNS_DIR="$RUNS_DIR" LMAS_RACE_RUN_DIR="$RACE_RUN_DIR" node packages/let-my-agent-sleep/bin/lmas-install.js cancel "$RACE_RUN_ID")
printf '%s\n' "$RACE_CANCEL_OUTPUT" | grep -q '^status: ALREADY_COMPLETED$' || { printf 'race cancel should report ALREADY_COMPLETED\n' >&2; exit 1; }
printf '%s\n' "$RACE_CANCEL_OUTPUT" | grep -q '^existing_status: SUCCEEDED$' || { printf 'race cancel should preserve completed status\n' >&2; exit 1; }

printf 'ok cancel: %s\n' "$RUN_ID"
