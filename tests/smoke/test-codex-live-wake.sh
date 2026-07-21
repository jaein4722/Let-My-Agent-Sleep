#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-codex-live-wake.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"
MOCK_BIN="$TMPDIR_ROOT/bin"
MOCK_CODEX_ARGS="$TMPDIR_ROOT/codex.args"
MOCK_CODEX_STDIN="$TMPDIR_ROOT/codex.stdin"
THREAD_ID="11111111-1111-7111-8111-111111111111"
SERVER_PID=
RUN_CASE_ID=
APP_SERVER_CASE_INDEX=0
mkdir -p "$MOCK_BIN"

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

cat > "$MOCK_BIN/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_CODEX_ARGS"
cat > "$MOCK_CODEX_STDIN"
SH
chmod +x "$MOCK_BIN/codex"

wait_for_file() {
  local path
  path=$1
  for _ in $(seq 1 150); do
    [ -f "$path" ] && return 0
    sleep 0.1
  done
  return 1
}

wait_for_log() {
  local path pattern
  path=$1
  pattern=$2
  for _ in $(seq 1 150); do
    if [ -f "$path" ] && grep -q "$pattern" "$path"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

start_desktop_server() {
  local mode socket capture ready server_log
  mode=$1
  socket=$2
  capture=$3
  ready=$4
  server_log=$5
  node "$ROOT/tests/smoke/mock-codex-ipc.cjs" "$socket" "$mode" "$capture" "$ready" > "$server_log" 2>&1 &
  SERVER_PID=$!
  wait_for_file "$ready" || {
    printf 'mock Codex IPC server did not become ready for mode %s\n' "$mode" >&2
    [ -f "$server_log" ] && sed -n '1,160p' "$server_log" >&2
    exit 1
  }
}

start_app_server() {
  local mode socket capture ready server_log
  mode=$1
  socket=$2
  capture=$3
  ready=$4
  server_log=$5
  node "$ROOT/tests/smoke/mock-codex-app-server.cjs" "$socket" "$mode" "$capture" "$ready" > "$server_log" 2>&1 &
  SERVER_PID=$!
  wait_for_file "$ready" || {
    printf 'mock Codex app-server did not become ready for mode %s\n' "$mode" >&2
    [ -f "$server_log" ] && sed -n '1,160p' "$server_log" >&2
    exit 1
  }
}

finish_server() {
  if [ -n "$SERVER_PID" ]; then
    wait "$SERVER_PID" >/dev/null 2>&1 || true
    SERVER_PID=
  fi
}

run_live_case() {
  local mode timeout socket capture ready server_log output run_id
  mode=$1
  timeout=$2
  socket="$TMPDIR_ROOT/$mode.sock"
  capture="$TMPDIR_ROOT/$mode.request.json"
  ready="$TMPDIR_ROOT/$mode.ready"
  server_log="$TMPDIR_ROOT/$mode.server.log"
  start_desktop_server "$mode" "$socket" "$capture" "$ready" "$server_log"

  output=$(cd "$ROOT" && \
    PATH="$MOCK_BIN:$PATH" \
    MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" \
    MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" \
    LMAS_CODEX_BIN="$MOCK_BIN/codex" \
    LMAS_CODEX_APP_SERVER_WAKE=0 \
    LMAS_CODEX_IPC_SOCKET="$socket" \
    LMAS_CODEX_LIVE_WAKE_TIMEOUT_MS="$timeout" \
    LMAS_RUNS_DIR="$RUNS_DIR" \
    CODEX_THREAD_ID="$THREAD_ID" \
    ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
  run_id=$(printf '%s\n' "$output" | awk '/^run_id:/ { print $2 }')
  [ -n "$run_id" ] || { printf 'live wake case did not emit run id\n' >&2; exit 1; }
  RUN_CASE_ID=$run_id
}

run_app_server_case() {
  local mode timeout socket capture ready server_log output run_id
  mode=$1
  timeout=$2
  APP_SERVER_CASE_INDEX=$((APP_SERVER_CASE_INDEX + 1))
  socket="$TMPDIR_ROOT/as$APP_SERVER_CASE_INDEX.sock"
  capture="$TMPDIR_ROOT/app-server-$mode.requests.json"
  ready="$TMPDIR_ROOT/app-server-$mode.ready"
  server_log="$TMPDIR_ROOT/app-server-$mode.server.log"
  start_app_server "$mode" "$socket" "$capture" "$ready" "$server_log"

  output=$(cd "$ROOT" && \
    PATH="$MOCK_BIN:$PATH" \
    MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" \
    MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" \
    LMAS_CODEX_BIN="$MOCK_BIN/codex" \
    LMAS_CODEX_APP_SERVER_SOCKET="$socket" \
    LMAS_CODEX_IPC_SOCKET="$TMPDIR_ROOT/no-desktop.sock" \
    LMAS_CODEX_LIVE_WAKE_TIMEOUT_MS="$timeout" \
    LMAS_RUNS_DIR="$RUNS_DIR" \
    CODEX_THREAD_ID="$THREAD_ID" \
    ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
  run_id=$(printf '%s\n' "$output" | awk '/^run_id:/ { print $2 }')
  [ -n "$run_id" ] || { printf 'app-server wake case did not emit run id\n' >&2; exit 1; }
  RUN_CASE_ID=$run_id
}

run_app_server_case success 2000
APP_SERVER_SUCCESS_RUN_ID=$RUN_CASE_ID
APP_SERVER_SUCCESS_RUN_DIR="$RUNS_DIR/$APP_SERVER_SUCCESS_RUN_ID"
wait_for_log "$APP_SERVER_SUCCESS_RUN_DIR/adapter.log" 'codex live wake succeeded' || { printf 'app-server live wake success was not logged\n' >&2; exit 1; }
finish_server
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'successful app-server wake should not call codex exec resume\n' >&2; exit 1; }
grep -q '"transport":"codex-app-server"' "$APP_SERVER_SUCCESS_RUN_DIR/codex-live-wake.log" || { printf 'app-server transport was not preserved\n' >&2; exit 1; }

node - "$TMPDIR_ROOT/app-server-success.requests.json" "$THREAD_ID" <<'JS'
const { readFileSync } = require("node:fs")
const requests = JSON.parse(readFileSync(process.argv[2], "utf8"))
const expectedThreadId = process.argv[3]
const initialize = requests.find((request) => request.method === "initialize")
if (initialize?.params?.clientInfo?.name !== "let-my-agent-sleep") throw new Error("missing LMAS initialize client info")
if (initialize?.params?.capabilities?.experimentalApi !== true) throw new Error("experimental app-server API was not enabled")
if (!requests.some((request) => request.method === "initialized")) throw new Error("initialized notification was not sent")
const resume = requests.find((request) => request.method === "thread/resume")
if (resume?.params?.threadId !== expectedThreadId) throw new Error("thread/resume used the wrong thread id")
if (resume?.params?.excludeTurns !== true) throw new Error("thread/resume did not request metadata-only rejoin")
const turn = requests.find((request) => request.method === "turn/start")
if (turn?.params?.threadId !== expectedThreadId) throw new Error("turn/start used the wrong thread id")
if (typeof turn?.params?.clientUserMessageId !== "string" || turn.params.clientUserMessageId.length === 0) {
  throw new Error("turn/start is missing clientUserMessageId")
}
const input = turn?.params?.input?.[0]
if (input?.type !== "text" || !input.text.includes("LMAS_COMPLETION_EVENT v1")) {
  throw new Error("turn/start is missing the completion prompt")
}
if (!Array.isArray(input.text_elements) || input.text_elements.length !== 0) {
  throw new Error("turn/start text_elements must be empty")
}
JS

rm -f "$MOCK_CODEX_ARGS" "$MOCK_CODEX_STDIN"
run_app_server_case timeout-after-turn 250
APP_SERVER_TIMEOUT_RUN_ID=$RUN_CASE_ID
APP_SERVER_TIMEOUT_RUN_DIR="$RUNS_DIR/$APP_SERVER_TIMEOUT_RUN_ID"
wait_for_file "$TMPDIR_ROOT/app-server-timeout-after-turn.requests.json" || { printf 'ambiguous app-server wake was not captured\n' >&2; exit 1; }
wait_for_log "$APP_SERVER_TIMEOUT_RUN_DIR/adapter.log" 'fallback suppressed' || { printf 'ambiguous app-server wake did not suppress duplicate fallback\n' >&2; exit 1; }
finish_server
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'ambiguous app-server wake must not call codex exec resume\n' >&2; exit 1; }
grep -q '"kind":"ambiguous"' "$APP_SERVER_TIMEOUT_RUN_DIR/codex-live-wake.log" || { printf 'ambiguous app-server outcome was not preserved\n' >&2; exit 1; }
grep -q '"transport":"codex-app-server"' "$APP_SERVER_TIMEOUT_RUN_DIR/codex-live-wake.log" || { printf 'ambiguous app-server transport was not preserved\n' >&2; exit 1; }

rm -f "$MOCK_CODEX_ARGS" "$MOCK_CODEX_STDIN"
run_live_case success 2000
SUCCESS_RUN_ID=$RUN_CASE_ID
SUCCESS_RUN_DIR="$RUNS_DIR/$SUCCESS_RUN_ID"
wait_for_file "$TMPDIR_ROOT/success.request.json" || { printf 'live wake request was not captured\n' >&2; exit 1; }
wait_for_log "$SUCCESS_RUN_DIR/adapter.log" 'codex live wake succeeded' || { printf 'live wake success was not logged\n' >&2; exit 1; }
finish_server
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'successful live wake should not call codex exec resume\n' >&2; exit 1; }

node - "$TMPDIR_ROOT/success.request.json" "$THREAD_ID" <<'JS'
const { readFileSync } = require("node:fs")
const request = JSON.parse(readFileSync(process.argv[2], "utf8"))
const expectedThreadId = process.argv[3]
if (request.type !== "request") throw new Error("wake message is not a request")
if (request.method !== "thread-follower-start-turn") throw new Error("wrong wake method")
if (request.version !== 1) throw new Error("wrong wake protocol version")
if (request.sourceClientId !== "mock-lmas-client") throw new Error("wake request did not use initialized client id")
if (request.params?.conversationId !== expectedThreadId) throw new Error("wake request used wrong thread id")
const params = request.params?.turnStartParams
if (typeof params?.clientUserMessageId !== "string" || params.clientUserMessageId.length === 0) {
  throw new Error("wake request is missing clientUserMessageId")
}
const input = params.input?.[0]
if (input?.type !== "text" || !input.text.includes("LMAS_COMPLETION_EVENT v1")) {
  throw new Error("wake request is missing the completion prompt")
}
if (!Array.isArray(input.text_elements) || input.text_elements.length !== 0) {
  throw new Error("wake request text_elements must be empty")
}
JS

rm -f "$MOCK_CODEX_ARGS" "$MOCK_CODEX_STDIN"
run_live_case no-client 2000
NO_CLIENT_RUN_ID=$RUN_CASE_ID
NO_CLIENT_RUN_DIR="$RUNS_DIR/$NO_CLIENT_RUN_ID"
wait_for_file "$MOCK_CODEX_STDIN" || { printf 'no-client live wake should fall back to codex exec resume\n' >&2; exit 1; }
wait_for_log "$NO_CLIENT_RUN_DIR/adapter.log" 'using separate-process fallback' || { printf 'no-client fallback was not logged\n' >&2; exit 1; }
finish_server
grep -q '"reason":"no-client-found"' "$NO_CLIENT_RUN_DIR/codex-live-wake.log" || { printf 'no-client reason was not preserved\n' >&2; exit 1; }
grep -qx 'resume' "$MOCK_CODEX_ARGS" || { printf 'no-client fallback did not call codex resume\n' >&2; exit 1; }
grep -q 'reload or reopen the task' "$MOCK_CODEX_STDIN" || { printf 'fallback prompt is missing reload guidance\n' >&2; exit 1; }

rm -f "$MOCK_CODEX_ARGS" "$MOCK_CODEX_STDIN"
run_live_case timeout 250
TIMEOUT_RUN_ID=$RUN_CASE_ID
TIMEOUT_RUN_DIR="$RUNS_DIR/$TIMEOUT_RUN_ID"
wait_for_file "$TMPDIR_ROOT/timeout.request.json" || { printf 'ambiguous wake request was not dispatched\n' >&2; exit 1; }
wait_for_log "$TIMEOUT_RUN_DIR/adapter.log" 'fallback suppressed' || { printf 'ambiguous wake did not suppress duplicate fallback\n' >&2; exit 1; }
finish_server
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'ambiguous live wake must not call codex exec resume\n' >&2; exit 1; }
grep -q '"kind":"ambiguous"' "$TIMEOUT_RUN_DIR/codex-live-wake.log" || { printf 'ambiguous wake outcome was not preserved\n' >&2; exit 1; }
[ -f "$TIMEOUT_RUN_DIR/resume_prompt.txt" ] || { printf 'ambiguous wake must retain resume prompt\n' >&2; exit 1; }

printf 'ok codex live wake: %s %s %s %s %s\n' "$APP_SERVER_SUCCESS_RUN_ID" "$APP_SERVER_TIMEOUT_RUN_ID" "$SUCCESS_RUN_ID" "$NO_CLIENT_RUN_ID" "$TIMEOUT_RUN_ID"
