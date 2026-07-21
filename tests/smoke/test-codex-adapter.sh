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

OUTPUT=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" LMAS_CODEX_BIN="$MOCK_BIN/codex" LMAS_CODEX_LIVE_WAKE=0 LMAS_RUNS_DIR="$RUNS_DIR" CODEX_THREAD_ID="codex-thread-123" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in $(seq 1 100); do
  [ -f "$MOCK_CODEX_STDIN" ] && break
  sleep 0.1
done

[ -f "$MOCK_CODEX_ARGS" ] || { printf 'mock codex was not called\n' >&2; exit 1; }
grep -qx 'exec' "$MOCK_CODEX_ARGS" || { printf 'missing exec arg\n' >&2; exit 1; }
grep -qx 'resume' "$MOCK_CODEX_ARGS" || { printf 'missing resume arg\n' >&2; exit 1; }
grep -qx -- '--skip-git-repo-check' "$MOCK_CODEX_ARGS" || { printf 'missing non-git resume arg\n' >&2; exit 1; }
grep -qx 'codex-thread-123' "$MOCK_CODEX_ARGS" || { printf 'missing native thread id arg\n' >&2; exit 1; }
grep -qx -- '-' "$MOCK_CODEX_ARGS" || { printf 'missing stdin prompt marker\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$MOCK_CODEX_STDIN" || { printf 'missing completion prompt on stdin\n' >&2; exit 1; }
grep -q 'reload or reopen the task' "$MOCK_CODEX_STDIN" || { printf 'missing Codex Desktop synchronization warning\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'expected SUCCEEDED\n' >&2; exit 1; }
grep -q '^codex_session_id=codex-thread-123$' "$RUN_DIR/metadata.txt" || { printf 'missing native codex thread id metadata\n' >&2; exit 1; }

rm -f "$MOCK_CODEX_ARGS" "$MOCK_CODEX_STDIN"
OUTPUT_SKIP=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" LMAS_RUNS_DIR="$RUNS_DIR" CODEX_THREAD_ID= ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
RUN_ID_SKIP=$(printf '%s\n' "$OUTPUT_SKIP" | awk '/^run_id:/ { print $2 }')
RUN_DIR_SKIP="$RUNS_DIR/$RUN_ID_SKIP"

for _ in $(seq 1 100); do
  [ -f "$RUN_DIR_SKIP/adapter.log" ] && break
  sleep 0.1
done

[ -f "$RUN_DIR_SKIP/adapter.log" ] || { printf 'missing codex skip adapter log\n' >&2; exit 1; }
grep -q 'codex adapter skipped: codex_session_id and CODEX_THREAD_ID are empty' "$RUN_DIR_SKIP/adapter.log" || {
  printf 'codex adapter did not explain missing session id skip\n' >&2
  exit 1
}
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'codex adapter should not call codex when session id is missing\n' >&2; exit 1; }
[ -f "$RUN_DIR_SKIP/resume_prompt.txt" ] || { printf 'codex skip did not leave resume_prompt.txt\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR_SKIP/completion_event.txt" || { printf 'codex skip should not change completion status\n' >&2; exit 1; }

printf 'ok codex adapter: %s %s\n' "$RUN_ID" "$RUN_ID_SKIP"
