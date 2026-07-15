#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-claude.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"
MOCK_BIN="$TMPDIR_ROOT/bin"
MOCK_CLAUDE_ARGS="$TMPDIR_ROOT/claude.args"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_CLAUDE_ARGS"
printf '%s\n' "$@"
SH
chmod +x "$MOCK_BIN/claude"

OUTPUT=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" MOCK_CLAUDE_ARGS="$MOCK_CLAUDE_ARGS" LMAS_RUNS_DIR="$RUNS_DIR" CLAUDE_CODE_SESSION_ID="claude-session-123" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter claude -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in $(seq 1 100); do
  [ -f "$MOCK_CLAUDE_ARGS" ] && break
  sleep 0.1
done

[ -f "$MOCK_CLAUDE_ARGS" ] || { printf 'mock claude was not called\n' >&2; exit 1; }
grep -qx -- '--resume' "$MOCK_CLAUDE_ARGS" || { printf 'missing --resume arg\n' >&2; exit 1; }
grep -qx 'claude-session-123' "$MOCK_CLAUDE_ARGS" || { printf 'missing session id arg\n' >&2; exit 1; }
grep -qx -- '-p' "$MOCK_CLAUDE_ARGS" || { printf 'missing print prompt arg\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$RUN_DIR/adapter.log" || { printf 'missing completion prompt in mock adapter log\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'expected SUCCEEDED\n' >&2; exit 1; }
grep -q '^claude_session_id=claude-session-123$' "$RUN_DIR/metadata.txt" || { printf 'missing native claude session id metadata\n' >&2; exit 1; }

rm -f "$MOCK_CLAUDE_ARGS"
OUTPUT_CONTINUE=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" MOCK_CLAUDE_ARGS="$MOCK_CLAUDE_ARGS" LMAS_RUNS_DIR="$RUNS_DIR" CLAUDE_CODE_SESSION_ID= LMAS_CLAUDE_CONTINUE=1 ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter claude -- ./examples/fake_train.sh success)
RUN_ID_CONTINUE=$(printf '%s\n' "$OUTPUT_CONTINUE" | awk '/^run_id:/ { print $2 }')
RUN_DIR_CONTINUE="$RUNS_DIR/$RUN_ID_CONTINUE"

for _ in $(seq 1 100); do
  [ -f "$MOCK_CLAUDE_ARGS" ] && break
  sleep 0.1
done

[ -f "$MOCK_CLAUDE_ARGS" ] || { printf 'mock claude was not called for continue mode\n' >&2; exit 1; }
grep -qx -- '--continue' "$MOCK_CLAUDE_ARGS" || { printf 'missing --continue arg\n' >&2; exit 1; }
grep -qx -- '-p' "$MOCK_CLAUDE_ARGS" || { printf 'missing continue print prompt arg\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$RUN_DIR_CONTINUE/adapter.log" || { printf 'missing completion prompt in continue adapter log\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR_CONTINUE/completion_event.txt" || { printf 'expected continue SUCCEEDED\n' >&2; exit 1; }

rm -f "$MOCK_CLAUDE_ARGS"
OUTPUT_SKIP=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" MOCK_CLAUDE_ARGS="$MOCK_CLAUDE_ARGS" LMAS_RUNS_DIR="$RUNS_DIR" CLAUDE_CODE_SESSION_ID= ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter claude -- ./examples/fake_train.sh success)
RUN_ID_SKIP=$(printf '%s\n' "$OUTPUT_SKIP" | awk '/^run_id:/ { print $2 }')
RUN_DIR_SKIP="$RUNS_DIR/$RUN_ID_SKIP"

for _ in $(seq 1 100); do
  [ -f "$RUN_DIR_SKIP/adapter.log" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR_SKIP/adapter.log" ] || { printf 'missing claude skip adapter log\n' >&2; exit 1; }
grep -q 'claude adapter skipped: claude_session_id and CLAUDE_CODE_SESSION_ID are empty; set LMAS_CLAUDE_CONTINUE=1' "$RUN_DIR_SKIP/adapter.log" || {
  printf 'claude adapter did not explain missing session id skip\n' >&2
  exit 1
}
[ ! -f "$MOCK_CLAUDE_ARGS" ] || { printf 'claude adapter should not call claude when resume and continue are unset\n' >&2; exit 1; }
[ -f "$RUN_DIR_SKIP/resume_prompt.txt" ] || { printf 'claude skip did not leave resume_prompt.txt\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR_SKIP/completion_event.txt" || { printf 'claude skip should not change completion status\n' >&2; exit 1; }

printf 'ok claude adapter: %s %s %s\n' "$RUN_ID" "$RUN_ID_CONTINUE" "$RUN_ID_SKIP"
