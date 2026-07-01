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

OUTPUT=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" MOCK_CLAUDE_ARGS="$MOCK_CLAUDE_ARGS" LMAS_RUNS_DIR="$RUNS_DIR" LMAS_CLAUDE_SESSION_ID="claude-session-123" ./bin/lmas.sh start --adapter claude -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$MOCK_CLAUDE_ARGS" ] && break
  sleep 0.1
done

[ -f "$MOCK_CLAUDE_ARGS" ] || { printf 'mock claude was not called\n' >&2; exit 1; }
grep -qx -- '--resume' "$MOCK_CLAUDE_ARGS" || { printf 'missing --resume arg\n' >&2; exit 1; }
grep -qx 'claude-session-123' "$MOCK_CLAUDE_ARGS" || { printf 'missing session id arg\n' >&2; exit 1; }
grep -qx -- '-p' "$MOCK_CLAUDE_ARGS" || { printf 'missing print prompt arg\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$RUN_DIR/adapter.log" || { printf 'missing completion prompt in mock adapter log\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'expected SUCCEEDED\n' >&2; exit 1; }

printf 'ok claude adapter: %s\n' "$RUN_ID"
