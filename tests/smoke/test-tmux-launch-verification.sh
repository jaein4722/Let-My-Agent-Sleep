#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-tmux-verify.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"
MOCK_BIN="$TMPDIR_ROOT/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/tmux" <<'SH'
#!/usr/bin/env bash
# Reproduce tmux 3.6a on macOS returning zero after sandbox-denied socket creation.
printf 'error creating mock socket (Operation not permitted)\n' >&2
exit 0
SH
chmod +x "$MOCK_BIN/tmux"

set +e
OUTPUT=$(cd "$ROOT" && PATH="$MOCK_BIN:$PATH" LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter noop -- bash -lc 'printf should-not-run' 2>&1)
STATUS=$?
set -e

[ "$STATUS" -eq 2 ] || { printf 'expected launch verification failure, got %s\n%s\n' "$STATUS" "$OUTPUT" >&2; exit 1; }
printf '%s\n' "$OUTPUT" | grep -q 'failed to verify tmux watcher session' || { printf 'missing tmux verification error\n' >&2; exit 1; }
if printf '%s\n' "$OUTPUT" | grep -q '^LMAS_HANDOFF v1$'; then
  printf 'must not emit handoff when tmux watcher was not created\n' >&2
  exit 1
fi

printf 'ok tmux launch verification\n'
