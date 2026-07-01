#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-codex.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"
MOCK_BIN="$TMPDIR_ROOT/bin"
MOCK_CODEX_ARGS="$TMPDIR_ROOT/codex.args"
MOCK_CODEX_STDIN="$TMPDIR_ROOT/codex.stdin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_CODEX_ARGS"
cat > "$MOCK_CODEX_STDIN"
SH
chmod +x "$MOCK_BIN/codex"

OUTPUT=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" LMAS_RUNS_DIR="$RUNS_DIR" LMAS_CODEX_SESSION_ID="codex-session-123" ./bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$MOCK_CODEX_STDIN" ] && break
  sleep 0.1
done

[ -f "$MOCK_CODEX_ARGS" ] || { printf 'mock codex was not called\n' >&2; exit 1; }
grep -qx 'exec' "$MOCK_CODEX_ARGS" || { printf 'missing exec arg\n' >&2; exit 1; }
grep -qx 'resume' "$MOCK_CODEX_ARGS" || { printf 'missing resume arg\n' >&2; exit 1; }
grep -qx 'codex-session-123' "$MOCK_CODEX_ARGS" || { printf 'missing session id arg\n' >&2; exit 1; }
grep -qx -- '-' "$MOCK_CODEX_ARGS" || { printf 'missing stdin prompt marker\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$MOCK_CODEX_STDIN" || { printf 'missing completion prompt on stdin\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'expected SUCCEEDED\n' >&2; exit 1; }
grep -q '^codex_session_id=codex-session-123$' "$RUN_DIR/metadata.txt" || { printf 'missing explicit codex session id metadata\n' >&2; exit 1; }

rm -f "$MOCK_CODEX_ARGS" "$MOCK_CODEX_STDIN"
OUTPUT_AUTO=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" LMAS_RUNS_DIR="$RUNS_DIR" CODEX_THREAD_ID="codex-thread-auto-456" ./bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
RUN_ID_AUTO=$(printf '%s\n' "$OUTPUT_AUTO" | awk '/^run_id:/ { print $2 }')
RUN_DIR_AUTO="$RUNS_DIR/$RUN_ID_AUTO"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$MOCK_CODEX_STDIN" ] && break
  sleep 0.1
done

[ -f "$MOCK_CODEX_ARGS" ] || { printf 'mock codex was not called for CODEX_THREAD_ID fallback\n' >&2; exit 1; }
grep -qx 'codex-thread-auto-456' "$MOCK_CODEX_ARGS" || { printf 'missing CODEX_THREAD_ID fallback session id arg\n' >&2; exit 1; }
grep -q '^codex_session_id=codex-thread-auto-456$' "$RUN_DIR_AUTO/metadata.txt" || { printf 'missing auto codex session id metadata\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR_AUTO/completion_event.txt" || { printf 'expected SUCCEEDED for CODEX_THREAD_ID fallback\n' >&2; exit 1; }

printf 'ok codex adapter: %s %s\n' "$RUN_ID" "$RUN_ID_AUTO"
