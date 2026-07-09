#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-doctor-home.XXXXXX")
SERVER_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lmas-doctor-server.XXXXXX")
SERVER_PID=""
trap '[ -z "$SERVER_PID" ] || kill "$SERVER_PID" >/dev/null 2>&1 || true; rm -rf "$TMP_HOME" "$SERVER_DIR"' EXIT

INSTALL_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent opencode --yes)
printf '%s\n' "$INSTALL_OUTPUT" | grep -q 'OpenCode install configured' || {
  printf 'opencode install did not complete before doctor test\n' >&2
  exit 1
}

DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --yes)
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'Let My Agent Sleep doctor passed' || {
  printf 'doctor did not pass after opencode install\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'let-my-agent-sleep is first in the OpenCode plugin list' || {
  printf 'doctor did not verify LMAS-first plugin order\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'OMO continuation hooks are disabled' || {
  printf 'doctor did not verify OMO continuation hooks\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'live OpenCode tool check skipped' || {
  printf 'doctor without server-url should explain live check skip\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}

cat > "$SERVER_DIR/server.mjs" <<'JS'
import http from "node:http"

const mode = process.argv[2]
const expectedAuth = `Basic ${Buffer.from("opencode:s3cr3t").toString("base64")}`
const server = http.createServer((request, response) => {
  if (request.url !== "/experimental/tool/ids") {
    response.writeHead(404, { "content-type": "application/json" })
    response.end(JSON.stringify({ error: "not found" }))
    return
  }

  if (mode === "auth-ok" && request.headers.authorization !== expectedAuth) {
    response.writeHead(401, { "www-authenticate": "Basic realm=\"Secure Area\"" })
    response.end()
    return
  }

  if (mode === "slow") {
    setTimeout(() => {
      response.writeHead(200, { "content-type": "application/json" })
      response.end(JSON.stringify(["bash", "lmas_start", "lmas_status", "lmas_cancel"]))
    }, 3000)
    return
  }

  const tools = mode === "ok"
    || mode === "auth-ok"
    ? ["bash", "lmas_start", "lmas_status", "lmas_cancel"]
    : ["bash", "lmas_status"]
  response.writeHead(200, { "content-type": "application/json" })
  response.end(JSON.stringify(tools))
})

server.listen(0, "127.0.0.1", () => {
  const address = server.address()
  console.log(address.port)
})
JS

node "$SERVER_DIR/server.mjs" ok > "$SERVER_DIR/port" &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$SERVER_DIR/port" ] && break
  sleep 0.1
done
SERVER_URL="http://127.0.0.1:$(cat "$SERVER_DIR/port")"

LIVE_DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --server-url "$SERVER_URL" --yes)
printf '%s\n' "$LIVE_DOCTOR_OUTPUT" | grep -q 'OpenCode live server exposes LMAS tools' || {
  printf 'doctor did not verify live OpenCode tools\n%s\n' "$LIVE_DOCTOR_OUTPUT" >&2
  exit 1
}

kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" >/dev/null 2>&1 || true
SERVER_PID=""
rm -f "$SERVER_DIR/port"

node "$SERVER_DIR/server.mjs" auth-ok > "$SERVER_DIR/port" &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$SERVER_DIR/port" ] && break
  sleep 0.1
done
AUTH_SERVER_URL="http://127.0.0.1:$(cat "$SERVER_DIR/port")"

AUTH_DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --server-url "$AUTH_SERVER_URL" --server-password "s3cr3t" --yes)
printf '%s\n' "$AUTH_DOCTOR_OUTPUT" | grep -q 'OpenCode live server exposes LMAS tools' || {
  printf 'doctor did not verify authenticated live OpenCode tools\n%s\n' "$AUTH_DOCTOR_OUTPUT" >&2
  exit 1
}

kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" >/dev/null 2>&1 || true
SERVER_PID=""
rm -f "$SERVER_DIR/port"

node "$SERVER_DIR/server.mjs" auth-ok > "$SERVER_DIR/port" &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$SERVER_DIR/port" ] && break
  sleep 0.1
done
AUTH_FAIL_SERVER_URL="http://127.0.0.1:$(cat "$SERVER_DIR/port")"
AUTH_FAIL_OUTPUT="$SERVER_DIR/auth-fail.out"
if cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --server-url "$AUTH_FAIL_SERVER_URL" --yes >"$AUTH_FAIL_OUTPUT" 2>&1; then
  printf 'doctor should fail when authenticated OpenCode server is checked without password\n' >&2
  cat "$AUTH_FAIL_OUTPUT" >&2
  exit 1
fi
grep -q 'rejected live doctor authentication' "$AUTH_FAIL_OUTPUT" || {
  printf 'doctor auth failure did not explain missing server password\n' >&2
  cat "$AUTH_FAIL_OUTPUT" >&2
  exit 1
}

kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" >/dev/null 2>&1 || true
SERVER_PID=""
rm -f "$SERVER_DIR/port"

node "$SERVER_DIR/server.mjs" missing > "$SERVER_DIR/port" &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$SERVER_DIR/port" ] && break
  sleep 0.1
done
MISSING_SERVER_URL="http://127.0.0.1:$(cat "$SERVER_DIR/port")"

LIVE_FAIL_OUTPUT="$SERVER_DIR/live-fail.out"
if cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --server-url "$MISSING_SERVER_URL" --yes >"$LIVE_FAIL_OUTPUT" 2>&1; then
  printf 'doctor should fail when live OpenCode server lacks LMAS tools\n' >&2
  cat "$LIVE_FAIL_OUTPUT" >&2
  exit 1
fi

grep -q 'OpenCode live server does not expose LMAS tools' "$LIVE_FAIL_OUTPUT" || {
  printf 'doctor live failure did not explain missing LMAS tools\n' >&2
  cat "$LIVE_FAIL_OUTPUT" >&2
  exit 1
}

kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" >/dev/null 2>&1 || true
SERVER_PID=""
rm -f "$SERVER_DIR/port"

node "$SERVER_DIR/server.mjs" slow > "$SERVER_DIR/port" &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$SERVER_DIR/port" ] && break
  sleep 0.1
done
SLOW_SERVER_URL="http://127.0.0.1:$(cat "$SERVER_DIR/port")"

SLOW_FAIL_OUTPUT="$SERVER_DIR/slow-fail.out"
if cd "$ROOT" && HOME="$TMP_HOME" LMAS_HTTP_MAX_TIME=1 node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --server-url "$SLOW_SERVER_URL" --yes >"$SLOW_FAIL_OUTPUT" 2>&1; then
  printf 'doctor should fail when live OpenCode server times out\n' >&2
  cat "$SLOW_FAIL_OUTPUT" >&2
  exit 1
fi

grep -q 'live doctor timed out' "$SLOW_FAIL_OUTPUT" || {
  printf 'doctor timeout failure did not explain timeout\n' >&2
  cat "$SLOW_FAIL_OUTPUT" >&2
  exit 1
}

kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" >/dev/null 2>&1 || true
SERVER_PID=""

node --input-type=module - "$TMP_HOME/.config/opencode/opencode.jsonc" <<'JS'
import { readFileSync, writeFileSync } from "node:fs"

const target = process.argv[2]
const config = JSON.parse(readFileSync(target, "utf8"))
config.plugin = ["oh-my-openagent@latest", ...config.plugin.filter((item) => item !== "oh-my-openagent@latest")]
writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`)
JS

ORDER_FAIL_OUTPUT="$SERVER_DIR/order-fail.out"
if cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --yes >"$ORDER_FAIL_OUTPUT" 2>&1; then
  printf 'doctor should fail when Oh My OpenAgent loads before LMAS\n' >&2
  cat "$ORDER_FAIL_OUTPUT" >&2
  exit 1
fi

grep -q 'is not first in the OpenCode plugin list' "$ORDER_FAIL_OUTPUT" || {
  printf 'doctor failure did not explain plugin order problem\n' >&2
  cat "$ORDER_FAIL_OUTPUT" >&2
  exit 1
}

printf 'ok doctor\n'
