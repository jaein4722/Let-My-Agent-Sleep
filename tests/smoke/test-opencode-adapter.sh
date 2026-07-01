#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-opencode.XXXXXX")
RUNS_DIR="$TMPDIR_ROOT/runs"
PORT_FILE="$TMPDIR_ROOT/port"
REQUEST_LOG="$TMPDIR_ROOT/request.log"

python3 - "$PORT_FILE" "$REQUEST_LOG" <<'PY' &
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

OUTPUT=$(cd "$ROOT" && LMAS_RUNS_DIR="$RUNS_DIR" LMAS_OPENCODE_SESSION_ID="session-123" LMAS_OPENCODE_SERVER_URL="http://127.0.0.1:$PORT" ./bin/lmas.sh start --adapter opencode -- ./examples/fake_train.sh success)
RUN_ID=$(printf '%s\n' "$OUTPUT" | awk '/^run_id:/ { print $2 }')
RUN_DIR="$RUNS_DIR/$RUN_ID"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [ -f "$REQUEST_LOG" ] && break
  sleep 0.1
done

wait "$SERVER_PID"

[ -f "$REQUEST_LOG" ] || { printf 'adapter did not call fake server\n' >&2; exit 1; }
grep -q '^/session/session-123/prompt_async$' "$REQUEST_LOG" || { printf 'unexpected adapter endpoint\n' >&2; exit 1; }
grep -q 'LMAS_COMPLETION_EVENT v1' "$REQUEST_LOG" || { printf 'missing completion event in adapter payload\n' >&2; exit 1; }
grep -q '^status: SUCCEEDED$' "$RUN_DIR/completion_event.txt" || { printf 'expected SUCCEEDED\n' >&2; exit 1; }
printf 'ok opencode adapter: %s\n' "$RUN_ID"
