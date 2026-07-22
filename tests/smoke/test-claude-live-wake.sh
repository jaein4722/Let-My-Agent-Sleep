#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LMAS="$ROOT/packages/let-my-agent-sleep/bin/lmas.sh"
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-claude-live-wake.XXXXXX")
MOCK_BIN="$TMPDIR_ROOT/bin"
BACKGROUND_PIDS=

cleanup() {
  local pid socket
  for pid in $BACKGROUND_PIDS; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  for socket_file in "$TMPDIR_ROOT"/*/runs/lmas_*/tmux_socket.txt; do
    [ -f "$socket_file" ] || continue
    socket=$(sed -n '1p' "$socket_file")
    [ -n "$socket" ] || continue
    tmux -S "$socket" kill-server >/dev/null 2>&1 || true
  done
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'claude live-wake smoke failed: %s\n' "$*" >&2
  if [ -n "${RUN_DIR:-}" ] && [ -d "$RUN_DIR" ]; then
    printf 'run_dir=%s\n' "$RUN_DIR" >&2
    for diagnostic in delivery.claim/winner native_waiter.ready adapter.log watcher.log completion_event.txt resume_prompt.txt; do
      if [ -f "$RUN_DIR/$diagnostic" ]; then
        printf '%s:\n' "$diagnostic" >&2
        sed -n '1,120p' "$RUN_DIR/$diagnostic" >&2
      fi
    done
  fi
  exit 1
}

wait_for_file() {
  local file attempt
  file=$1
  attempt=0
  while [ "$attempt" -lt 240 ]; do
    [ -f "$file" ] && return 0
    sleep 0.05
    attempt=$((attempt + 1))
  done
  return 1
}

wait_for_text() {
  local file pattern attempt
  file=$1
  pattern=$2
  attempt=0
  while [ "$attempt" -lt 240 ]; do
    if [ -f "$file" ] && grep -q -- "$pattern" "$file"; then
      return 0
    fi
    sleep 0.05
    attempt=$((attempt + 1))
  done
  return 1
}

process_started_at() {
  ps -p "$1" -o lstart= 2>/dev/null | sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}'
}

new_case() {
  CASE_NAME=$1
  CASE_DIR="$TMPDIR_ROOT/$CASE_NAME"
  RUNS_DIR="$CASE_DIR/runs"
  MOCK_CLAUDE_ARGS="$CASE_DIR/claude.calls"
  mkdir -p "$RUNS_DIR"
}

start_run() {
  local grace delay exit_code output
  grace=$1
  delay=$2
  exit_code=$3
  output=$(cd "$ROOT" && \
    PATH="$MOCK_BIN:$PATH" \
    MOCK_CLAUDE_ARGS="$MOCK_CLAUDE_ARGS" \
    LMAS_CLAUDE_NATIVE_GRACE_SECONDS="$grace" \
    LMAS_CLAUDE_NATIVE_POLL_INTERVAL=0.02 \
    LMAS_RUNS_DIR="$RUNS_DIR" \
    CLAUDE_CODE_SESSION_ID="claude-$CASE_NAME" \
    "$LMAS" start --adapter claude -- /bin/sh -c "sleep $delay; exit $exit_code") || fail "$CASE_NAME start failed"
  RUN_ID=$(printf '%s\n' "$output" | awk '/^run_id:/ { print $2; exit }')
  [ -n "$RUN_ID" ] || fail "$CASE_NAME handoff omitted run id"
  RUN_DIR="$RUNS_DIR/$RUN_ID"
}

start_gated_run() {
  local grace exit_code output
  grace=$1
  exit_code=$2
  RELEASE_FILE="$CASE_DIR/job.release"
  output=$(cd "$ROOT" && \
    PATH="$MOCK_BIN:$PATH" \
    MOCK_CLAUDE_ARGS="$MOCK_CLAUDE_ARGS" \
    LMAS_CLAUDE_NATIVE_GRACE_SECONDS="$grace" \
    LMAS_CLAUDE_NATIVE_POLL_INTERVAL=0.02 \
    LMAS_RUNS_DIR="$RUNS_DIR" \
    CLAUDE_CODE_SESSION_ID="claude-$CASE_NAME" \
    "$LMAS" start --adapter claude -- /bin/sh -c 'while [ ! -f "$1" ]; do sleep 0.02; done; exit "$2"' sh "$RELEASE_FILE" "$exit_code") || fail "$CASE_NAME gated start failed"
  RUN_ID=$(printf '%s\n' "$output" | awk '/^run_id:/ { print $2; exit }')
  [ -n "$RUN_ID" ] || fail "$CASE_NAME gated handoff omitted run id"
  RUN_DIR="$RUNS_DIR/$RUN_ID"
}

start_await_for_owner() {
  local owner_pid
  owner_pid=$1
  AWAIT_OUTPUT="$CASE_DIR/await.out"
  AWAIT_ERROR="$CASE_DIR/await.err"
  (
    cd "$ROOT" || exit 1
    LMAS_RUNS_DIR="$RUNS_DIR" \
    LMAS_CLAUDE_AWAIT_POLL_INTERVAL=0.02 \
    LMAS_CLAUDE_OWNER_PID="$owner_pid" \
    CLAUDE_CODE_SESSION_ID="claude-$CASE_NAME" \
    "$LMAS" await "$RUN_ID"
  ) > "$AWAIT_OUTPUT" 2> "$AWAIT_ERROR" &
  AWAIT_PID=$!
  BACKGROUND_PIDS="$BACKGROUND_PIDS $AWAIT_PID"
}

start_await() {
  start_await_for_owner "$$"
}

mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/claude" <<'SH'
#!/usr/bin/env bash
{
  printf 'CALL pid=%s\n' "$$"
  printf '%s\n' "$@"
  printf 'END\n'
} >> "$MOCK_CLAUDE_ARGS"
SH
chmod +x "$MOCK_BIN/claude"

# A registered waiter owns delivery and the separate-process fallback is silent.
new_case native
start_gated_run 2 0
start_await
wait_for_file "$RUN_DIR/native_waiter.ready" || fail "native waiter did not publish readiness"
: > "$RELEASE_FILE"
wait "$AWAIT_PID" || fail "native waiter exited nonzero: $(cat "$AWAIT_ERROR" 2>/dev/null)"
wait_for_text "$RUN_DIR/adapter.log" 'native waiter committed' || fail "native adapter did not observe committed claim"
grep -q '^LMAS_COMPLETION_EVENT v1$' "$AWAIT_OUTPUT" || fail "native waiter omitted completion payload"
grep -q '^status: SUCCEEDED$' "$AWAIT_OUTPUT" || fail "native waiter emitted wrong status"
grep -q '^winner=native$' "$RUN_DIR/delivery.claim/winner" || fail "native waiter did not win claim"
[ ! -s "$MOCK_CLAUDE_ARGS" ] || fail "native delivery also invoked claude --resume"

# No waiter means fallback is proven safe and claims delivery exactly once.
new_case absent
start_run 0 0.1 0
wait_for_text "$MOCK_CLAUDE_ARGS" '^CALL ' || fail "absent waiter did not invoke fallback"
grep -q '^winner=fallback$' "$RUN_DIR/delivery.claim/winner" || fail "absent waiter did not create fallback claim"
grep -q '^--resume$' "$MOCK_CLAUDE_ARGS" || fail "absent waiter fallback omitted --resume"

# A stale ready marker whose process is dead is also a proven fallback case.
new_case dead
start_gated_run 1 0
sleep 5 &
DEAD_PID=$!
DEAD_STARTED_AT=$(process_started_at "$DEAD_PID")
kill "$DEAD_PID" >/dev/null 2>&1 || true
wait "$DEAD_PID" 2>/dev/null || true
{
  printf 'waiter_pid=%s\n' "$DEAD_PID"
  printf 'waiter_started_at=%s\n' "$DEAD_STARTED_AT"
  printf 'owner_pid=%s\n' "$$"
  printf 'owner_started_at=%s\n' "$(process_started_at "$$")"
  printf 'claude_session_id=claude-dead\n'
  printf 'epoch=%s\n' "$(date '+%s')"
} > "$RUN_DIR/native_waiter.ready"
: > "$RELEASE_FILE"
wait_for_text "$MOCK_CLAUDE_ARGS" '^CALL ' || fail "dead waiter did not invoke fallback"
grep -q '^winner=fallback$' "$RUN_DIR/delivery.claim/winner" || fail "dead waiter did not create fallback claim"

# Claude can exit while its background Bash child remains orphaned. The owner,
# not merely the waiter PID, decides whether native delivery is still possible.
new_case owner-dead
start_gated_run 1 0
sleep 30 &
OWNER_PID=$!
BACKGROUND_PIDS="$BACKGROUND_PIDS $OWNER_PID"
start_await_for_owner "$OWNER_PID"
wait_for_file "$RUN_DIR/native_waiter.ready" || fail "owner-dead waiter did not publish readiness"
kill "$OWNER_PID" >/dev/null 2>&1 || true
wait "$OWNER_PID" 2>/dev/null || true
: > "$RELEASE_FILE"
if wait "$AWAIT_PID"; then
  fail "orphaned waiter unexpectedly claimed native delivery"
fi
wait_for_text "$MOCK_CLAUDE_ARGS" '^CALL ' || fail "dead Claude owner did not invoke fallback"
grep -q 'owning Claude process exited' "$AWAIT_ERROR" || fail "orphaned waiter did not explain owner death"
grep -q '^winner=fallback$' "$RUN_DIR/delivery.claim/winner" || fail "dead Claude owner did not create fallback claim"
[ ! -s "$AWAIT_OUTPUT" ] || fail "orphaned waiter emitted a native completion payload"

# A native claim survives a waiter crash and suppresses fallback conservatively.
new_case committed
start_gated_run 0 0
mkdir "$RUN_DIR/delivery.claim" || fail "could not stage committed native claim"
printf 'winner=native\n' > "$RUN_DIR/delivery.claim/winner"
: > "$RELEASE_FILE"
wait_for_text "$RUN_DIR/adapter.log" 'native waiter committed' || fail "committed native claim was not honored"
[ ! -s "$MOCK_CLAUDE_ARGS" ] || fail "committed native claim invoked fallback"
[ -f "$RUN_DIR/resume_prompt.txt" ] || fail "committed native claim did not retain resume prompt"

# A fast completion without a registered waiter falls back after the configured grace.
new_case fast
start_run 0 0 0
wait_for_text "$MOCK_CLAUDE_ARGS" '^CALL ' || fail "fast completion did not fall back"
grep -q '^winner=fallback$' "$RUN_DIR/delivery.claim/winner" || fail "fast completion did not create fallback claim"

# A live-but-stalled waiter is ambiguous: retain the prompt and never resume.
new_case ambiguous
start_gated_run 1 0
sleep 5 &
LIVE_PID=$!
BACKGROUND_PIDS="$BACKGROUND_PIDS $LIVE_PID"
{
  printf 'waiter_pid=%s\n' "$LIVE_PID"
  printf 'waiter_started_at=%s\n' "$(process_started_at "$LIVE_PID")"
  printf 'owner_pid=%s\n' "$$"
  printf 'owner_started_at=%s\n' "$(process_started_at "$$")"
  printf 'claude_session_id=claude-ambiguous\n'
  printf 'epoch=%s\n' "$(date '+%s')"
} > "$RUN_DIR/native_waiter.ready"
: > "$RELEASE_FILE"
wait_for_text "$RUN_DIR/adapter.log" 'outcome is ambiguous' || fail "live stalled waiter was not treated as ambiguous"
[ ! -e "$RUN_DIR/delivery.claim" ] || fail "ambiguous waiter should not be claimed by fallback"
[ ! -s "$MOCK_CLAUDE_ARGS" ] || fail "ambiguous waiter invoked fallback"
[ -f "$RUN_DIR/resume_prompt.txt" ] || fail "ambiguous waiter did not retain resume prompt"
kill "$LIVE_PID" >/dev/null 2>&1 || true
wait "$LIVE_PID" 2>/dev/null || true

# Cancellation writes CANCELLED, wakes the native waiter, and never also resumes.
new_case cancel
start_run 2 30 0
start_await
wait_for_file "$RUN_DIR/native_waiter.ready" || fail "cancel waiter did not publish readiness"
CANCEL_OUTPUT=$(cd "$ROOT" && \
  PATH="$MOCK_BIN:$PATH" \
  MOCK_CLAUDE_ARGS="$MOCK_CLAUDE_ARGS" \
  LMAS_CLAUDE_NATIVE_GRACE_SECONDS=2 \
  LMAS_CLAUDE_NATIVE_POLL_INTERVAL=0.02 \
  LMAS_RUNS_DIR="$RUNS_DIR" \
  CLAUDE_CODE_SESSION_ID=claude-cancel \
  "$LMAS" cancel "$RUN_ID") || fail "cancel command failed"
wait "$AWAIT_PID" || fail "cancel waiter exited nonzero"
printf '%s\n' "$CANCEL_OUTPUT" | grep -q '^status: CANCELLED$' || fail "cancel command omitted CANCELLED"
grep -q '^status: CANCELLED$' "$AWAIT_OUTPUT" || fail "cancel waiter omitted CANCELLED payload"
grep -q '^winner=native$' "$RUN_DIR/delivery.claim/winner" || fail "cancel waiter did not own claim"
[ ! -s "$MOCK_CLAUDE_ARGS" ] || fail "cancel native delivery also invoked fallback"

# Runs keep independent ready and claim state when they finish concurrently.
new_case multi-a
start_gated_run 2 0
RUNS_DIR_A=$RUNS_DIR
RUN_ID_A=$RUN_ID
RUN_DIR_A=$RUN_DIR
CASE_DIR_A=$CASE_DIR
MOCK_A=$MOCK_CLAUDE_ARGS
RELEASE_A=$RELEASE_FILE
start_await
AWAIT_PID_A=$AWAIT_PID
AWAIT_OUTPUT_A=$AWAIT_OUTPUT
wait_for_file "$RUN_DIR_A/native_waiter.ready" || fail "first concurrent waiter did not publish readiness"

new_case multi-b
start_gated_run 2 1
RUNS_DIR_B=$RUNS_DIR
RUN_ID_B=$RUN_ID
RUN_DIR_B=$RUN_DIR
CASE_DIR_B=$CASE_DIR
MOCK_B=$MOCK_CLAUDE_ARGS
RELEASE_B=$RELEASE_FILE
start_await
AWAIT_PID_B=$AWAIT_PID
AWAIT_OUTPUT_B=$AWAIT_OUTPUT
wait_for_file "$RUN_DIR_B/native_waiter.ready" || fail "second concurrent waiter did not publish readiness"

: > "$RELEASE_A"
: > "$RELEASE_B"

wait "$AWAIT_PID_A" || fail "first concurrent waiter exited nonzero"
wait "$AWAIT_PID_B" || fail "second concurrent waiter exited nonzero"
grep -q '^winner=native$' "$RUN_DIR_A/delivery.claim/winner" || fail "first concurrent run lost native claim"
grep -q '^winner=native$' "$RUN_DIR_B/delivery.claim/winner" || fail "second concurrent run lost native claim"
grep -q "^run_id: $RUN_ID_A$" "$AWAIT_OUTPUT_A" || fail "first waiter received another run's payload"
grep -q "^run_id: $RUN_ID_B$" "$AWAIT_OUTPUT_B" || fail "second waiter received another run's payload"
grep -q '^status: SUCCEEDED$' "$AWAIT_OUTPUT_A" || fail "first concurrent status was wrong"
grep -q '^status: FAILED$' "$AWAIT_OUTPUT_B" || fail "second concurrent status was wrong"
[ ! -s "$MOCK_A" ] || fail "first concurrent native run invoked fallback"
[ ! -s "$MOCK_B" ] || fail "second concurrent native run invoked fallback"

# A waiter registered after fallback sees only a no-op payload, so completion is not duplicated.
new_case late
start_run 0 0 0
wait_for_text "$MOCK_CLAUDE_ARGS" '^CALL ' || fail "late-waiter setup did not invoke fallback"
LATE_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" LMAS_CLAUDE_AWAIT_POLL_INTERVAL=0.02 LMAS_CLAUDE_OWNER_PID="$$" "$LMAS" await "$RUN_ID") || fail "late waiter exited nonzero"
printf '%s\n' "$LATE_OUTPUT" | grep -q '^LMAS_NATIVE_DELIVERY_NOOP v1$' || fail "late waiter did not emit no-op"
if printf '%s\n' "$LATE_OUTPUT" | grep -q '^LMAS_COMPLETION_EVENT v1$'; then
  fail "late waiter duplicated the completion payload"
fi
[ "$(grep -c '^CALL ' "$MOCK_CLAUDE_ARGS")" -eq 1 ] || fail "late waiter caused duplicate fallback"

printf 'ok claude native live wake: native fallback dead owner-dead committed fast ambiguous cancel concurrent late\n'
