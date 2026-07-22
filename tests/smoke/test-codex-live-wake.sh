#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-codex-live-wake.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"
MOCK_BIN="$TMPDIR_ROOT/bin"
MOCK_CODEX_ARGS="$TMPDIR_ROOT/codex.args"
MOCK_CODEX_STDIN="$TMPDIR_ROOT/codex.stdin"
LIVE_HELPER_STUB="$TMPDIR_ROOT/live-helper-stub.cjs"
REAL_LIVE_HELPER="$ROOT/packages/let-my-agent-sleep/bin/codex-live-wake.cjs"
THREAD_ID="11111111-1111-7111-8111-111111111111"
SERVER_PID=
AUX_SERVER_PID=
RUN_CASE_ID=
APP_SERVER_CASE_INDEX=0
APP_SERVER_CAPTURE=
DESKTOP_CAPTURE=
CASE_LIVE_HELPER=
CASE_HELPER_MODE=
CASE_MARKER_CAPTURE=
CASE_DESKTOP_SOCKET=
mkdir -p "$MOCK_BIN"

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$AUX_SERVER_PID" ]; then
    kill "$AUX_SERVER_PID" >/dev/null 2>&1 || true
    wait "$AUX_SERVER_PID" >/dev/null 2>&1 || true
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

cat > "$LIVE_HELPER_STUB" <<'JS'
#!/usr/bin/env node
const fs = require("node:fs")
const net = require("node:net")

const mode = process.env.LMAS_TEST_HELPER_MODE || "real"
const markerIndex = process.argv.indexOf("--dispatch-marker")
const markerPath = markerIndex >= 0 ? process.argv[markerIndex + 1] : ""
const markerCapture = process.env.MOCK_MARKER_PATH_CAPTURE || ""
const realHelper = process.env.LMAS_TEST_REAL_HELPER || ""

if (markerCapture) fs.writeFileSync(markerCapture, `${markerPath}\n`)

if (mode === "crash-before-marker") {
  process.stderr.write("mock helper crash before dispatch\n")
  process.exit(1)
}

if (mode === "crash-after-marker") {
  const descriptor = fs.openSync(markerPath, "wx", 0o600)
  fs.closeSync(descriptor)
  process.stderr.write("mock helper crash after dispatch marker\n")
  process.exit(1)
}

if (mode === "exit11-no-marker") {
  process.stderr.write("mock helper explicit ambiguous exit without marker\n")
  process.exit(11)
}

if (mode === "marker-eexist") {
  const descriptor = fs.openSync(markerPath, "wx", 0o600)
  fs.closeSync(descriptor)
}

if (mode === "marker-eacces") {
  const originalOpenSync = fs.openSync
  fs.openSync = (path, ...args) => {
    if (path === markerPath) {
      const error = new Error("mock dispatch marker permission denial")
      error.code = "EACCES"
      throw error
    }
    return originalOpenSync(path, ...args)
  }
}

if (mode === "clear-failure") {
  const originalUnlinkSync = fs.unlinkSync
  fs.unlinkSync = (path, ...args) => {
    if (path === markerPath) {
      const error = new Error("mock dispatch marker clear failure")
      error.code = "EACCES"
      throw error
    }
    return originalUnlinkSync(path, ...args)
  }
}

if (mode === "desktop-create-crash") {
  const originalCreateConnection = net.createConnection
  let createCount = 0
  net.createConnection = (...args) => {
    createCount += 1
    if (createCount === 2) {
      const error = new Error("mock Desktop connection crash before dispatch")
      error.code = "EMFILE"
      throw error
    }
    return originalCreateConnection(...args)
  }
}

if (!realHelper) throw new Error("LMAS_TEST_REAL_HELPER is required")
require(realHelper)
JS
chmod +x "$LIVE_HELPER_STUB"

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

marker_for_run() {
  local run_dir marker
  run_dir=$1
  for marker in "$run_dir"/codex-live-wake.*.dispatch; do
    if [ -e "$marker" ] || [ -L "$marker" ]; then
      printf '%s\n' "$marker"
      return 0
    fi
  done
  return 1
}

reset_codex_mock() {
  rm -f "$MOCK_CODEX_ARGS" "$MOCK_CODEX_STDIN"
}

reset_case_options() {
  CASE_LIVE_HELPER=
  CASE_HELPER_MODE=
  CASE_MARKER_CAPTURE=
  CASE_DESKTOP_SOCKET=
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

start_aux_desktop_server() {
  local mode socket capture ready server_log
  mode=$1
  socket=$2
  capture=$3
  ready=$4
  server_log=$5
  node "$ROOT/tests/smoke/mock-codex-ipc.cjs" "$socket" "$mode" "$capture" "$ready" > "$server_log" 2>&1 &
  AUX_SERVER_PID=$!
  wait_for_file "$ready" || {
    printf 'auxiliary mock Codex IPC server did not become ready for mode %s\n' "$mode" >&2
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

finish_aux_server() {
  if [ -n "$AUX_SERVER_PID" ]; then
    kill "$AUX_SERVER_PID" >/dev/null 2>&1 || true
    wait "$AUX_SERVER_PID" >/dev/null 2>&1 || true
    AUX_SERVER_PID=
  fi
}

run_live_case() {
  local mode timeout case_name socket capture ready server_log output run_id live_helper helper_mode
  mode=$1
  timeout=$2
  case_name=${3:-$mode}
  live_helper=${CASE_LIVE_HELPER:-$REAL_LIVE_HELPER}
  helper_mode=${CASE_HELPER_MODE:-real}
  socket="$TMPDIR_ROOT/$case_name.sock"
  capture="$TMPDIR_ROOT/$case_name.request.json"
  ready="$TMPDIR_ROOT/$case_name.ready"
  server_log="$TMPDIR_ROOT/$case_name.server.log"
  start_desktop_server "$mode" "$socket" "$capture" "$ready" "$server_log"
  DESKTOP_CAPTURE=$capture

  output=$(cd "$ROOT" && \
    PATH="$MOCK_BIN:$PATH" \
    MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" \
    MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" \
    LMAS_CODEX_BIN="$MOCK_BIN/codex" \
    LMAS_CODEX_LIVE_WAKE_HELPER="$live_helper" \
    LMAS_CODEX_APP_SERVER_WAKE=0 \
    LMAS_CODEX_IPC_SOCKET="$socket" \
    LMAS_CODEX_LIVE_WAKE_TIMEOUT_MS="$timeout" \
    LMAS_RUNS_DIR="$RUNS_DIR" \
    LMAS_TEST_HELPER_MODE="$helper_mode" \
    LMAS_TEST_REAL_HELPER="$REAL_LIVE_HELPER" \
    MOCK_MARKER_PATH_CAPTURE="$CASE_MARKER_CAPTURE" \
    CODEX_THREAD_ID="$THREAD_ID" \
    ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
  run_id=$(printf '%s\n' "$output" | awk '/^run_id:/ { print $2 }')
  [ -n "$run_id" ] || { printf 'live wake case did not emit run id\n' >&2; exit 1; }
  RUN_CASE_ID=$run_id
}

run_app_server_case() {
  local mode timeout socket capture ready server_log output run_id live_helper helper_mode desktop_socket
  mode=$1
  timeout=$2
  live_helper=${CASE_LIVE_HELPER:-$REAL_LIVE_HELPER}
  helper_mode=${CASE_HELPER_MODE:-real}
  desktop_socket=${CASE_DESKTOP_SOCKET:-$TMPDIR_ROOT/no-desktop.sock}
  APP_SERVER_CASE_INDEX=$((APP_SERVER_CASE_INDEX + 1))
  socket="$TMPDIR_ROOT/as$APP_SERVER_CASE_INDEX.sock"
  capture="$TMPDIR_ROOT/app-server-$APP_SERVER_CASE_INDEX-$mode.requests.json"
  ready="$TMPDIR_ROOT/app-server-$APP_SERVER_CASE_INDEX-$mode.ready"
  server_log="$TMPDIR_ROOT/app-server-$APP_SERVER_CASE_INDEX-$mode.server.log"
  start_app_server "$mode" "$socket" "$capture" "$ready" "$server_log"
  APP_SERVER_CAPTURE=$capture

  output=$(cd "$ROOT" && \
    PATH="$MOCK_BIN:$PATH" \
    MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" \
    MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" \
    LMAS_CODEX_BIN="$MOCK_BIN/codex" \
    LMAS_CODEX_LIVE_WAKE_HELPER="$live_helper" \
    LMAS_CODEX_APP_SERVER_SOCKET="$socket" \
    LMAS_CODEX_IPC_SOCKET="$desktop_socket" \
    LMAS_CODEX_LIVE_WAKE_TIMEOUT_MS="$timeout" \
    LMAS_RUNS_DIR="$RUNS_DIR" \
    LMAS_TEST_HELPER_MODE="$helper_mode" \
    LMAS_TEST_REAL_HELPER="$REAL_LIVE_HELPER" \
    MOCK_MARKER_PATH_CAPTURE="$CASE_MARKER_CAPTURE" \
    CODEX_THREAD_ID="$THREAD_ID" \
    ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
  run_id=$(printf '%s\n' "$output" | awk '/^run_id:/ { print $2 }')
  [ -n "$run_id" ] || { printf 'app-server wake case did not emit run id\n' >&2; exit 1; }
  RUN_CASE_ID=$run_id
}

run_stub_case() {
  local helper_mode output run_id
  helper_mode=$1
  output=$(cd "$ROOT" && \
    PATH="$MOCK_BIN:$PATH" \
    MOCK_CODEX_ARGS="$MOCK_CODEX_ARGS" \
    MOCK_CODEX_STDIN="$MOCK_CODEX_STDIN" \
    MOCK_MARKER_PATH_CAPTURE="$CASE_MARKER_CAPTURE" \
    LMAS_CODEX_BIN="$MOCK_BIN/codex" \
    LMAS_CODEX_LIVE_WAKE_HELPER="$LIVE_HELPER_STUB" \
    LMAS_CODEX_APP_SERVER_WAKE=0 \
    LMAS_CODEX_IPC_SOCKET="$TMPDIR_ROOT/no-desktop.sock" \
    LMAS_RUNS_DIR="$RUNS_DIR" \
    LMAS_TEST_HELPER_MODE="$helper_mode" \
    LMAS_TEST_REAL_HELPER="$REAL_LIVE_HELPER" \
    CODEX_THREAD_ID="$THREAD_ID" \
    ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter codex -- ./examples/fake_train.sh success)
  run_id=$(printf '%s\n' "$output" | awk '/^run_id:/ { print $2 }')
  [ -n "$run_id" ] || { printf 'stub helper case did not emit run id for %s\n' "$helper_mode" >&2; exit 1; }
  RUN_CASE_ID=$run_id
}

run_app_server_case success 2000
APP_SERVER_SUCCESS_RUN_ID=$RUN_CASE_ID
APP_SERVER_SUCCESS_RUN_DIR="$RUNS_DIR/$APP_SERVER_SUCCESS_RUN_ID"
APP_SERVER_SUCCESS_CAPTURE=$APP_SERVER_CAPTURE
wait_for_log "$APP_SERVER_SUCCESS_RUN_DIR/adapter.log" 'codex live wake succeeded' || { printf 'app-server live wake success was not logged\n' >&2; exit 1; }
finish_server
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'successful app-server wake should not call codex exec resume\n' >&2; exit 1; }
grep -q '"transport":"codex-app-server"' "$APP_SERVER_SUCCESS_RUN_DIR/codex-live-wake.log" || { printf 'app-server transport was not preserved\n' >&2; exit 1; }

node - "$APP_SERVER_SUCCESS_CAPTURE" "$THREAD_ID" "$ROOT/packages/let-my-agent-sleep/package.json" <<'JS'
const { readFileSync } = require("node:fs")
const requests = JSON.parse(readFileSync(process.argv[2], "utf8"))
const expectedThreadId = process.argv[3]
const packageVersion = JSON.parse(readFileSync(process.argv[4], "utf8")).version
const initialize = requests.find((request) => request.method === "initialize")
if (initialize?.params?.clientInfo?.name !== "let-my-agent-sleep") throw new Error("missing LMAS initialize client info")
if (initialize?.params?.clientInfo?.version !== packageVersion) throw new Error("LMAS initialize client version does not match package.json")
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
APP_SERVER_TIMEOUT_CAPTURE=$APP_SERVER_CAPTURE
wait_for_file "$APP_SERVER_TIMEOUT_CAPTURE" || { printf 'ambiguous app-server wake was not captured\n' >&2; exit 1; }
wait_for_log "$APP_SERVER_TIMEOUT_RUN_DIR/adapter.log" 'fallback suppressed' || { printf 'ambiguous app-server wake did not suppress duplicate fallback\n' >&2; exit 1; }
finish_server
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'ambiguous app-server wake must not call codex exec resume\n' >&2; exit 1; }
grep -q '"kind":"ambiguous"' "$APP_SERVER_TIMEOUT_RUN_DIR/codex-live-wake.log" || { printf 'ambiguous app-server outcome was not preserved\n' >&2; exit 1; }
grep -q '"transport":"codex-app-server"' "$APP_SERVER_TIMEOUT_RUN_DIR/codex-live-wake.log" || { printf 'ambiguous app-server transport was not preserved\n' >&2; exit 1; }
marker_for_run "$APP_SERVER_TIMEOUT_RUN_DIR" >/dev/null || { printf 'ambiguous app-server wake did not retain its dispatch marker\n' >&2; exit 1; }

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
if marker_for_run "$NO_CLIENT_RUN_DIR" >/dev/null; then
  printf 'definitive Desktop no-client response did not clear its dispatch marker\n' >&2
  exit 1
fi

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
marker_for_run "$TIMEOUT_RUN_DIR" >/dev/null || { printf 'ambiguous Desktop wake did not retain its dispatch marker\n' >&2; exit 1; }

reset_codex_mock
reset_case_options
CASE_MARKER_CAPTURE="$TMPDIR_ROOT/crash-before-marker.path"
run_stub_case crash-before-marker
CRASH_BEFORE_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
wait_for_file "$MOCK_CODEX_STDIN" || { printf 'pre-dispatch helper crash did not use the Codex fallback\n' >&2; exit 1; }
wait_for_file "$CASE_MARKER_CAPTURE" || { printf 'pre-dispatch helper crash did not capture its marker path\n' >&2; exit 1; }
CRASH_BEFORE_MARKER=$(sed -n '1p' "$CASE_MARKER_CAPTURE")
if [ -e "$CRASH_BEFORE_MARKER" ] || [ -L "$CRASH_BEFORE_MARKER" ]; then
  printf 'pre-dispatch helper crash unexpectedly created a dispatch marker\n' >&2
  exit 1
fi
grep -q 'before creating a dispatch marker (status 1)' "$CRASH_BEFORE_RUN_DIR/adapter.log" || { printf 'pre-dispatch helper crash was not classified as fallback-safe\n' >&2; exit 1; }

reset_codex_mock
reset_case_options
CASE_MARKER_CAPTURE="$TMPDIR_ROOT/crash-after-marker.path"
run_stub_case crash-after-marker
CRASH_AFTER_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
wait_for_log "$CRASH_AFTER_RUN_DIR/adapter.log" 'fallback suppressed' || { printf 'post-marker helper crash did not suppress fallback\n' >&2; exit 1; }
wait_for_file "$CASE_MARKER_CAPTURE" || { printf 'post-marker helper crash did not capture its marker path\n' >&2; exit 1; }
CRASH_AFTER_MARKER=$(sed -n '1p' "$CASE_MARKER_CAPTURE")
[ -e "$CRASH_AFTER_MARKER" ] || { printf 'post-marker helper crash did not retain its dispatch marker\n' >&2; exit 1; }
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'post-marker helper crash must not call codex exec resume\n' >&2; exit 1; }

reset_codex_mock
reset_case_options
CASE_MARKER_CAPTURE="$TMPDIR_ROOT/exit11-no-marker.path"
run_stub_case exit11-no-marker
EXIT11_NO_MARKER_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
wait_for_file "$MOCK_CODEX_STDIN" || { printf 'exit 11 without a marker did not use the Codex fallback\n' >&2; exit 1; }
EXIT11_NO_MARKER=$(sed -n '1p' "$CASE_MARKER_CAPTURE")
if [ -e "$EXIT11_NO_MARKER" ] || [ -L "$EXIT11_NO_MARKER" ]; then
  printf 'exit 11 no-marker case unexpectedly created a dispatch marker\n' >&2
  exit 1
fi
grep -q 'before creating a dispatch marker (status 11)' "$EXIT11_NO_MARKER_RUN_DIR/adapter.log" || { printf 'exit 11 without a marker was not classified as fallback-safe\n' >&2; exit 1; }

reset_codex_mock
reset_case_options
CASE_LIVE_HELPER=$LIVE_HELPER_STUB
CASE_HELPER_MODE=marker-eacces
CASE_MARKER_CAPTURE="$TMPDIR_ROOT/marker-eacces.path"
run_live_case success 2000 marker-eacces
MARKER_FAILURE_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
MARKER_FAILURE_CAPTURE=$DESKTOP_CAPTURE
wait_for_file "$MOCK_CODEX_STDIN" || { printf 'dispatch marker creation failure did not use the Codex fallback\n' >&2; exit 1; }
finish_server
MARKER_FAILURE_PATH=$(sed -n '1p' "$CASE_MARKER_CAPTURE")
if [ -e "$MARKER_FAILURE_PATH" ] || [ -L "$MARKER_FAILURE_PATH" ]; then
  printf 'failed dispatch marker creation left a marker behind\n' >&2
  exit 1
fi
[ ! -f "$MARKER_FAILURE_CAPTURE" ] || { printf 'marker creation failure sent a Desktop wake request\n' >&2; exit 1; }
grep -q 'dispatch-marker-failed:EACCES' "$MARKER_FAILURE_RUN_DIR/codex-live-wake.log" || { printf 'marker creation failure reason was not preserved\n' >&2; exit 1; }

reset_codex_mock
reset_case_options
CASE_LIVE_HELPER=$LIVE_HELPER_STUB
CASE_HELPER_MODE=marker-eexist
CASE_MARKER_CAPTURE="$TMPDIR_ROOT/marker-eexist.path"
run_live_case success 2000 marker-eexist
MARKER_EEXIST_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
MARKER_EEXIST_CAPTURE=$DESKTOP_CAPTURE
wait_for_log "$MARKER_EEXIST_RUN_DIR/adapter.log" 'fallback suppressed' || { printf 'EEXIST dispatch marker did not suppress fallback\n' >&2; exit 1; }
finish_server
MARKER_EEXIST_PATH=$(sed -n '1p' "$CASE_MARKER_CAPTURE")
[ -e "$MARKER_EEXIST_PATH" ] || { printf 'EEXIST dispatch marker was removed without ownership\n' >&2; exit 1; }
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'EEXIST dispatch marker must not call codex exec resume\n' >&2; exit 1; }
[ ! -f "$MARKER_EEXIST_CAPTURE" ] || { printf 'EEXIST dispatch marker sent a Desktop wake request\n' >&2; exit 1; }
grep -q 'dispatch-marker-exists:EEXIST' "$MARKER_EEXIST_RUN_DIR/codex-live-wake.log" || { printf 'EEXIST marker reason was not preserved\n' >&2; exit 1; }

reset_codex_mock
reset_case_options
run_app_server_case turn-error 2000
TURN_REJECT_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
wait_for_file "$MOCK_CODEX_STDIN" || { printf 'definitive app-server turn rejection did not use the Codex fallback\n' >&2; exit 1; }
finish_server
if marker_for_run "$TURN_REJECT_RUN_DIR" >/dev/null; then
  printf 'definitive app-server turn rejection did not clear its dispatch marker\n' >&2
  exit 1
fi
grep -q 'turn-start-rejected:mock turn rejected' "$TURN_REJECT_RUN_DIR/codex-live-wake.log" || { printf 'app-server turn rejection reason was not preserved\n' >&2; exit 1; }

reset_codex_mock
reset_case_options
run_app_server_case late-errors-after-turn 250
LATE_ERRORS_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
wait_for_log "$LATE_ERRORS_RUN_DIR/adapter.log" 'fallback suppressed' || { printf 'late app-server responses did not remain ambiguous\n' >&2; exit 1; }
finish_server
[ ! -f "$MOCK_CODEX_ARGS" ] || { printf 'late app-server responses must not call codex exec resume\n' >&2; exit 1; }
marker_for_run "$LATE_ERRORS_RUN_DIR" >/dev/null || { printf 'late app-server responses cleared the active dispatch marker\n' >&2; exit 1; }
grep -q 'timeout-after-turn-start' "$LATE_ERRORS_RUN_DIR/codex-live-wake.log" || { printf 'late app-server responses did not preserve the active turn timeout\n' >&2; exit 1; }
if grep -q 'late initialize error\|late resume error' "$LATE_ERRORS_RUN_DIR/codex-live-wake.log"; then
  printf 'late app-server initialize/resume responses bypassed phase guards\n' >&2
  exit 1
fi

reset_codex_mock
reset_case_options
CASE_LIVE_HELPER=$LIVE_HELPER_STUB
CASE_HELPER_MODE=clear-failure
CASE_MARKER_CAPTURE="$TMPDIR_ROOT/clear-failure.path"
run_app_server_case turn-error 2000
CLEAR_FAILURE_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
wait_for_file "$MOCK_CODEX_STDIN" || { printf 'dispatch marker clear failure did not use the Codex fallback\n' >&2; exit 1; }
finish_server
CLEAR_FAILURE_MARKER=$(sed -n '1p' "$CASE_MARKER_CAPTURE")
[ -e "$CLEAR_FAILURE_MARKER" ] || { printf 'dispatch marker clear failure did not retain uncertainty evidence\n' >&2; exit 1; }
grep -q '"markerClearFailed":true' "$CLEAR_FAILURE_RUN_DIR/codex-live-wake.log" || { printf 'dispatch marker clear failure was not reported\n' >&2; exit 1; }
if grep -q '"transport":"desktop-ipc"' "$CLEAR_FAILURE_RUN_DIR/codex-live-wake.log"; then
  printf 'Desktop live wake was attempted after dispatch marker clear failure\n' >&2
  exit 1
fi

reset_codex_mock
reset_case_options
COMPOSITE_DESKTOP_SOCKET="$TMPDIR_ROOT/composite-desktop.sock"
start_aux_desktop_server timeout "$COMPOSITE_DESKTOP_SOCKET" "$TMPDIR_ROOT/composite-desktop.request.json" "$TMPDIR_ROOT/composite-desktop.ready" "$TMPDIR_ROOT/composite-desktop.server.log"
CASE_LIVE_HELPER=$LIVE_HELPER_STUB
CASE_HELPER_MODE=desktop-create-crash
CASE_MARKER_CAPTURE="$TMPDIR_ROOT/composite.path"
CASE_DESKTOP_SOCKET=$COMPOSITE_DESKTOP_SOCKET
run_app_server_case turn-error 2000
COMPOSITE_RUN_DIR="$RUNS_DIR/$RUN_CASE_ID"
wait_for_file "$MOCK_CODEX_STDIN" || { printf 'app-server rejection followed by pre-dispatch Desktop crash did not use fallback\n' >&2; exit 1; }
finish_server
finish_aux_server
COMPOSITE_MARKER=$(sed -n '1p' "$CASE_MARKER_CAPTURE")
if [ -e "$COMPOSITE_MARKER" ] || [ -L "$COMPOSITE_MARKER" ]; then
  printf 'app-server rejection did not clear its marker before the Desktop attempt\n' >&2
  exit 1
fi
grep -q 'before creating a dispatch marker (status 11)' "$COMPOSITE_RUN_DIR/adapter.log" || { printf 'pre-dispatch Desktop crash was not classified using marker evidence\n' >&2; exit 1; }
grep -q '"transport":"orchestrator"' "$COMPOSITE_RUN_DIR/codex-live-wake.log" || { printf 'pre-dispatch Desktop crash did not reach the orchestrator outcome\n' >&2; exit 1; }

printf 'ok codex live wake: %s %s %s %s %s plus marker crash/rejection coverage\n' "$APP_SERVER_SUCCESS_RUN_ID" "$APP_SERVER_TIMEOUT_RUN_ID" "$SUCCESS_RUN_ID" "$NO_CLIENT_RUN_ID" "$TIMEOUT_RUN_ID"
