#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-opencode.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"

file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

PORT_FILE="$TMPDIR_ROOT/port"
REQUEST_LOG="$TMPDIR_ROOT/request.log"
FAIL_PORT_FILE="$TMPDIR_ROOT/fail-port"
FAIL_REQUEST_LOG="$TMPDIR_ROOT/fail-request.log"
NOTIFY_PORT_FILE="$TMPDIR_ROOT/notify-port"
NOTIFY_REQUEST_LOG="$TMPDIR_ROOT/notify-request.log"
SLOW_ADAPTER_PORT_FILE="$TMPDIR_ROOT/slow-adapter-port"
SLOW_ADAPTER_REQUEST_LOG="$TMPDIR_ROOT/slow-adapter-request.log"
SLOW_NOTIFY_PORT_FILE="$TMPDIR_ROOT/slow-notify-port"
SLOW_NOTIFY_REQUEST_LOG="$TMPDIR_ROOT/slow-notify-request.log"

python3 - "$PORT_FILE" "$REQUEST_LOG" <<'PY' &
import http.server
import base64
import json
import socketserver
import sys

port_file, request_log = sys.argv[1], sys.argv[2]
expected_auth = "Basic " + base64.b64encode(b"opencode:s3cr3t").decode("ascii")

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.headers.get("authorization") != expected_auth:
            self.send_response(401)
            self.send_header("www-authenticate", 'Basic realm="Secure Area"')
            self.end_headers()
            return
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        with open(request_log, "w", encoding="utf-8") as handle:
            handle.write(self.path + "\n")
            handle.write(self.headers.get("authorization", "") + "\n")
            handle.write(self.headers.get("content-type", "") + "\n")
            handle.write(body)
            try:
                payload = json.loads(body)
                text = payload["parts"][0]["text"]
            except Exception as error:
                handle.write("\nJSON_ERROR: " + str(error) + "\n")
            else:
                handle.write("\nJSON_TEXT_BEGIN\n")
                handle.write(text)
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as handle:
        handle.write(str(httpd.server_address[1]))
    httpd.handle_request()
PY
SERVER_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$PORT_FILE" ] && break
  sleep 0.1
done

[ -f "$PORT_FILE" ] || { printf 'fake server did not start\n' >&2; exit 1; }
PORT=$(cat "$PORT_FILE")

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" LMAS_OPENCODE_SESSION_ID="session-123" LMAS_OPENCODE_SERVER_URL="http://127.0.0.1:$PORT" LMAS_OPENCODE_PASSWORD="s3cr3t" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter opencode -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$REQUEST_LOG" ] && break
  sleep 0.1
done

wait "$SERVER_PID"

[ -f "$REQUEST_LOG" ] || { printf 'adapter did not call fake server\n' >&2; exit 1; }
grep -q '^/session/session-123/prompt_async$' "$REQUEST_LOG" || { printf 'unexpected adapter endpoint\n' >&2; exit 1; }
grep -q '^Basic b3BlbmNvZGU6czNjcjN0$' "$REQUEST_LOG" || { printf 'adapter did not use expected opencode basic auth header\n' >&2; exit 1; }
grep -q '^application/json$' "$REQUEST_LOG" || { printf 'adapter did not use expected JSON content-type\n' >&2; exit 1; }
if grep -q '^JSON_ERROR:' "$REQUEST_LOG"; then
  printf 'adapter request body was not valid JSON\n' >&2
  cat "$REQUEST_LOG" >&2
  exit 1
fi
grep -q '^JSON_TEXT_BEGIN$' "$REQUEST_LOG" || { printf 'adapter request did not expose parsed prompt text\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$REQUEST_LOG" || { printf 'missing completion event in adapter payload\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$REQUEST_LOG" || { printf 'parsed adapter prompt missing completion status\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'expected SUCCEEDED\n' >&2; exit 1; }

python3 - "$FAIL_PORT_FILE" "$FAIL_REQUEST_LOG" <<'PY' &
import http.server
import socketserver
import sys

port_file, request_log = sys.argv[1], sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        with open(request_log, "w", encoding="utf-8") as handle:
            handle.write(self.path + "\n")
            handle.write(body)
        self.send_response(500)
        self.send_header("content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"adapter failure")

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as handle:
        handle.write(str(httpd.server_address[1]))
    httpd.handle_request()
PY
FAIL_SERVER_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$FAIL_PORT_FILE" ] && break
  sleep 0.1
done

[ -f "$FAIL_PORT_FILE" ] || { printf 'failing fake server did not start\n' >&2; exit 1; }
FAIL_PORT=$(cat "$FAIL_PORT_FILE")

python3 - "$NOTIFY_PORT_FILE" "$NOTIFY_REQUEST_LOG" <<'PY' &
import http.server
import socketserver
import sys

port_file, request_log = sys.argv[1], sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        with open(request_log, "w", encoding="utf-8") as handle:
            handle.write(self.path + "\n")
            handle.write(self.headers.get("content-type", "") + "\n")
            handle.write(body)
        self.send_response(200)
        self.send_header("content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as handle:
        handle.write(str(httpd.server_address[1]))
    httpd.handle_request()
PY
NOTIFY_SERVER_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$NOTIFY_PORT_FILE" ] && break
  sleep 0.1
done

[ -f "$NOTIFY_PORT_FILE" ] || { printf 'notify fake server did not start\n' >&2; exit 1; }
NOTIFY_PORT=$(cat "$NOTIFY_PORT_FILE")
NOTIFY_URL="http://127.0.0.1:$NOTIFY_PORT/notify/topic"

FAIL_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" LMAS_OPENCODE_SESSION_ID="session-500" LMAS_OPENCODE_SERVER_URL="http://127.0.0.1:$FAIL_PORT" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter opencode --notify "$NOTIFY_URL" -- ./examples/fake_train.sh success)
FAIL_RUN_ID=$(printf '%s\n' "$FAIL_OUTPUT" | awk '/^run_id:/ { print $2 }')
FAIL_RUN_DIR="$RUNS_DIR/$FAIL_RUN_ID"

for _ in $(seq 1 100); do
  [ -f "$FAIL_RUN_DIR/adapter.log" ] && [ -f "$FAIL_RUN_DIR/notify.log" ] && break
  sleep 0.1
done

wait "$FAIL_SERVER_PID"
wait "$NOTIFY_SERVER_PID"

[ -f "$FAIL_REQUEST_LOG" ] || { printf 'failing adapter server was not called\n' >&2; exit 1; }
[ -f "$NOTIFY_REQUEST_LOG" ] || { printf 'notify server was not called after adapter failure\n' >&2; exit 1; }
grep -q '^/session/session-500/prompt_async$' "$FAIL_REQUEST_LOG" || { printf 'unexpected failing adapter endpoint\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$FAIL_RUN_DIR/completion_event.txt" || { printf 'adapter failure should not change completion status\n' >&2; exit 1; }
[ -f "$FAIL_RUN_DIR/resume_prompt.txt" ] || { printf 'adapter failure did not leave resume_prompt.txt\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$FAIL_RUN_DIR/resume_prompt.txt" || { printf 'adapter failure resume_prompt missing completion event\n' >&2; exit 1; }
grep -q 'opencode adapter failed for' "$FAIL_RUN_DIR/adapter.log" || { printf 'adapter failure was not recorded in adapter.log\n' >&2; exit 1; }
grep -q '^/notify/topic$' "$NOTIFY_REQUEST_LOG" || { printf 'notify server received unexpected path\n' >&2; exit 1; }
grep -q '^text/plain; charset=utf-8$' "$NOTIFY_REQUEST_LOG" || { printf 'notify server received unexpected content-type\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$NOTIFY_REQUEST_LOG" || { printf 'notify payload missing completion event\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$NOTIFY_REQUEST_LOG" || { printf 'notify payload missing status\n' >&2; exit 1; }
grep -q 'notify sent' "$FAIL_RUN_DIR/notify.log" || { printf 'notify success was not recorded\n' >&2; exit 1; }
grep -q '^notify=enabled$' "$FAIL_RUN_DIR/metadata.txt" || { printf 'metadata did not record notification enabled state\n' >&2; exit 1; }
if grep -q "$NOTIFY_URL" "$FAIL_RUN_DIR/metadata.txt"; then
  printf 'metadata leaked notify url\n' >&2
  exit 1
fi
[ -f "$FAIL_RUN_DIR/notify_url.txt" ] || { printf 'notify url file was not written\n' >&2; exit 1; }
grep -qx "$NOTIFY_URL" "$FAIL_RUN_DIR/notify_url.txt" || { printf 'notify url file did not preserve notification endpoint\n' >&2; exit 1; }
if [ "$(file_mode "$FAIL_RUN_DIR/notify_url.txt")" != "600" ]; then
  printf 'notify url file should be mode 600\n' >&2
  exit 1
fi

FAIL_STATUS=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh status "$FAIL_RUN_ID")
printf '%s\n' "$FAIL_STATUS" | grep -q '^status: SUCCEEDED$' || { printf 'adapter failure status should remain SUCCEEDED\n' >&2; exit 1; }
printf '%s\n' "$FAIL_STATUS" | grep -q "resume_prompt: $FAIL_RUN_DIR/resume_prompt.txt" || { printf 'adapter failure status did not expose resume_prompt path\n' >&2; exit 1; }
printf '%s\n' "$FAIL_STATUS" | grep -q "notify_log: $FAIL_RUN_DIR/notify.log" || { printf 'adapter failure status did not expose notify log path\n' >&2; exit 1; }
if printf '%s\n' "$FAIL_STATUS" | grep -q 'notify_url'; then
  printf 'status leaked notify url field\n' >&2
  exit 1
fi

python3 - "$SLOW_ADAPTER_PORT_FILE" "$SLOW_ADAPTER_REQUEST_LOG" <<'PY' &
import http.server
import socketserver
import sys
import time

port_file, request_log = sys.argv[1], sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        self.rfile.read(length)
        with open(request_log, "w", encoding="utf-8") as handle:
            handle.write(self.path + "\n")
        time.sleep(3)
        try:
            self.send_response(200)
            self.end_headers()
        except BrokenPipeError:
            pass

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as handle:
        handle.write(str(httpd.server_address[1]))
    httpd.handle_request()
PY
SLOW_ADAPTER_SERVER_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$SLOW_ADAPTER_PORT_FILE" ] && break
  sleep 0.1
done

[ -f "$SLOW_ADAPTER_PORT_FILE" ] || { printf 'slow adapter fake server did not start\n' >&2; exit 1; }
SLOW_ADAPTER_PORT=$(cat "$SLOW_ADAPTER_PORT_FILE")

SLOW_ADAPTER_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" LMAS_HTTP_MAX_TIME=1 LMAS_HTTP_CONNECT_TIMEOUT=1 LMAS_OPENCODE_SESSION_ID="session-slow" LMAS_OPENCODE_SERVER_URL="http://127.0.0.1:$SLOW_ADAPTER_PORT" ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter opencode -- ./examples/fake_train.sh success)
SLOW_ADAPTER_RUN_ID=$(printf '%s\n' "$SLOW_ADAPTER_OUTPUT" | awk '/^run_id:/ { print $2 }')
SLOW_ADAPTER_RUN_DIR="$RUNS_DIR/$SLOW_ADAPTER_RUN_ID"

for _ in $(seq 1 40); do
  [ -f "$SLOW_ADAPTER_RUN_DIR/adapter.log" ] && break
  sleep 0.1
done

wait "$SLOW_ADAPTER_SERVER_PID" || true

[ -f "$SLOW_ADAPTER_REQUEST_LOG" ] || { printf 'slow adapter server was not called\n' >&2; exit 1; }
grep -q '^/session/session-slow/prompt_async$' "$SLOW_ADAPTER_REQUEST_LOG" || { printf 'unexpected slow adapter endpoint\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$SLOW_ADAPTER_RUN_DIR/completion_event.txt" || { printf 'slow adapter timeout should not change completion status\n' >&2; exit 1; }
grep -Eq 'timed out|opencode adapter failed for' "$SLOW_ADAPTER_RUN_DIR/adapter.log" || { printf 'slow adapter timeout was not recorded\n' >&2; exit 1; }

python3 - "$SLOW_NOTIFY_PORT_FILE" "$SLOW_NOTIFY_REQUEST_LOG" <<'PY' &
import http.server
import socketserver
import sys
import time

port_file, request_log = sys.argv[1], sys.argv[2]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        self.rfile.read(length)
        with open(request_log, "w", encoding="utf-8") as handle:
            handle.write(self.path + "\n")
        time.sleep(3)
        try:
            self.send_response(200)
            self.end_headers()
        except BrokenPipeError:
            pass

    def log_message(self, format, *args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as handle:
        handle.write(str(httpd.server_address[1]))
    httpd.handle_request()
PY
SLOW_NOTIFY_SERVER_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$SLOW_NOTIFY_PORT_FILE" ] && break
  sleep 0.1
done

[ -f "$SLOW_NOTIFY_PORT_FILE" ] || { printf 'slow notify fake server did not start\n' >&2; exit 1; }
SLOW_NOTIFY_PORT=$(cat "$SLOW_NOTIFY_PORT_FILE")
SLOW_NOTIFY_URL="http://127.0.0.1:$SLOW_NOTIFY_PORT/slow-notify"

SLOW_NOTIFY_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" LMAS_HTTP_MAX_TIME=1 LMAS_HTTP_CONNECT_TIMEOUT=1 ./packages/let-my-agent-sleep/bin/lmas.sh start --notify "$SLOW_NOTIFY_URL" -- ./examples/fake_train.sh success)
SLOW_NOTIFY_RUN_ID=$(printf '%s\n' "$SLOW_NOTIFY_OUTPUT" | awk '/^run_id:/ { print $2 }')
SLOW_NOTIFY_RUN_DIR="$RUNS_DIR/$SLOW_NOTIFY_RUN_ID"

for _ in $(seq 1 40); do
  [ -f "$SLOW_NOTIFY_RUN_DIR/notify.log" ] && break
  sleep 0.1
done

wait "$SLOW_NOTIFY_SERVER_PID" || true

[ -f "$SLOW_NOTIFY_REQUEST_LOG" ] || { printf 'slow notify server was not called\n' >&2; exit 1; }
grep -q '^/slow-notify$' "$SLOW_NOTIFY_REQUEST_LOG" || { printf 'unexpected slow notify endpoint\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$SLOW_NOTIFY_RUN_DIR/completion_event.txt" || { printf 'slow notify timeout should not change completion status\n' >&2; exit 1; }
grep -Eq 'timed out|notify failed' "$SLOW_NOTIFY_RUN_DIR/notify.log" || { printf 'slow notify timeout was not recorded\n' >&2; exit 1; }

INVALID_NOTIFY_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --notify=unexpected -- /bin/true 2>&1)
INVALID_NOTIFY_STATUS=$?
if [ "$INVALID_NOTIFY_STATUS" -eq 0 ]; then
  printf 'unknown --notify=value syntax should not be accepted\n' >&2
  exit 1
fi
printf '%s\n' "$INVALID_NOTIFY_OUTPUT" | grep -q 'unknown option' || { printf 'invalid notify option did not fail safely\n' >&2; exit 1; }

UNSAFE_NOTIFY_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" ./packages/let-my-agent-sleep/bin/lmas.sh start --notify '--config=secret' -- /bin/true)
UNSAFE_NOTIFY_RUN_ID=$(printf '%s\n' "$UNSAFE_NOTIFY_OUTPUT" | awk '/^run_id:/ { print $2 }')
UNSAFE_NOTIFY_RUN_DIR="$RUNS_DIR/$UNSAFE_NOTIFY_RUN_ID"
for _ in $(seq 1 20); do
  [ -f "$UNSAFE_NOTIFY_RUN_DIR/notify.log" ] && break
  sleep 0.1
done
grep -q 'URL must use http:// or https://' "$UNSAFE_NOTIFY_RUN_DIR/notify.log" || { printf 'option-shaped notify URL was not rejected before curl\n' >&2; exit 1; }

INVALID_SERVER_OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" LMAS_OPENCODE_SESSION_ID=session-invalid LMAS_OPENCODE_SERVER_URL='--config=secret' ./packages/let-my-agent-sleep/bin/lmas.sh start --adapter opencode -- /bin/true)
INVALID_SERVER_RUN_ID=$(printf '%s\n' "$INVALID_SERVER_OUTPUT" | awk '/^run_id:/ { print $2 }')
INVALID_SERVER_RUN_DIR="$RUNS_DIR/$INVALID_SERVER_RUN_ID"
for _ in $(seq 1 20); do
  [ -f "$INVALID_SERVER_RUN_DIR/adapter.log" ] && break
  sleep 0.1
done
grep -q 'server URL must use http:// or https://' "$INVALID_SERVER_RUN_DIR/adapter.log" || { printf 'invalid OpenCode server URL was not rejected before curl\n' >&2; exit 1; }

printf 'ok opencode adapter: %s\n' "$RUN_ID"
