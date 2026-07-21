#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/lmas-doctor-home.XXXXXX")
SERVER_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lmas-doctor-server.XXXXXX")
SERVER_PID=""
trap '[ -z "$SERVER_PID" ] || kill "$SERVER_PID" >/dev/null 2>&1 || true; rm -rf "$TMP_HOME" "$SERVER_DIR"' EXIT

unset OPENCODE_CONFIG OPENCODE_CONFIG_FILE OPENCODE_CONFIG_DIR OPENCODE_CACHE_DIR
export HOME="$TMP_HOME"
export XDG_CONFIG_HOME="$TMP_HOME/.config"
export XDG_CACHE_HOME="$TMP_HOME/.cache"

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
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'Oh My OpenAgent config is absent; LMAS did not create one' || {
  printf 'doctor did not report non-mutating OMO policy\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'live OpenCode tool check skipped' || {
  printf 'doctor without server-url should explain live check skip\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}

printf '%s\n' "$DOCTOR_OUTPUT" | grep -q 'has not resolved this LMAS version in a recognized cache layout' || {
  printf 'doctor should explain that OpenCode resolves its own cache after restart\n%s\n' "$DOCTOR_OUTPUT" >&2
  exit 1
}

PACKAGE_VERSION=$(cd "$ROOT" && node -p "require('./packages/let-my-agent-sleep/package.json').version")
CURRENT_CACHE_PACKAGE="$TMP_HOME/.cache/opencode/packages/let-my-agent-sleep@$PACKAGE_VERSION/node_modules/let-my-agent-sleep/package.json"
mkdir -p "$(dirname "$CURRENT_CACHE_PACKAGE")" \
  "$TMP_HOME/.cache/opencode/packages/let-my-agent-sleep" \
  "$TMP_HOME/.cache/opencode/packages/let-my-agent-sleep@latest" \
  "$TMP_HOME/.cache/opencode/node_modules/let-my-agent-sleep"
cat > "$TMP_HOME/.cache/opencode/packages/let-my-agent-sleep/package.json" <<'JSON'
{"name":"let-my-agent-sleep","version":"0.1.0"}
JSON
cat > "$TMP_HOME/.cache/opencode/packages/let-my-agent-sleep@latest/package.json" <<'JSON'
{"name":"let-my-agent-sleep","version":"0.1.0"}
JSON
cat > "$TMP_HOME/.cache/opencode/node_modules/let-my-agent-sleep/package.json" <<'JSON'
{"name":"let-my-agent-sleep","version":"0.1.0"}
JSON
printf '{"name":"let-my-agent-sleep","version":"%s"}\n' "$PACKAGE_VERSION" > "$CURRENT_CACHE_PACKAGE"

CURRENT_CACHE_DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --yes)
printf '%s\n' "$CURRENT_CACHE_DOCTOR_OUTPUT" | grep -q "OpenCode resolved package matches this LMAS version: let-my-agent-sleep@$PACKAGE_VERSION" || {
  printf 'doctor did not recognize the current versioned OpenCode package cache\n%s\n' "$CURRENT_CACHE_DOCTOR_OUTPUT" >&2
  exit 1
}

printf '{"name":"let-my-agent-sleep","version":"0.1.5"}\n' > "$CURRENT_CACHE_PACKAGE"
STALE_CACHE_FAIL_OUTPUT="$SERVER_DIR/stale-cache-fail.out"
if cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --yes >"$STALE_CACHE_FAIL_OUTPUT" 2>&1; then
  printf 'doctor should fail when every recognized resolved package is stale\n' >&2
  cat "$STALE_CACHE_FAIL_OUTPUT" >&2
  exit 1
fi
grep -q 'OpenCode resolved package version is stale' "$STALE_CACHE_FAIL_OUTPUT" || {
  printf 'doctor stale cache failure did not explain resolved package mismatch\n' >&2
  cat "$STALE_CACHE_FAIL_OUTPUT" >&2
  exit 1
}
printf '{"name":"let-my-agent-sleep","version":"%s"}\n' "$PACKAGE_VERSION" > "$CURRENT_CACHE_PACKAGE"

CODEX_INSTALL_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent codex --yes)
printf '%s\n' "$CODEX_INSTALL_OUTPUT" | grep -q 'Codex install configured' || {
  printf 'codex install did not complete before doctor test\n' >&2
  exit 1
}
CODEX_DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent codex --yes)
printf '%s\n' "$CODEX_DOCTOR_OUTPUT" | grep -q 'Codex LMAS binary is executable' || {
  printf 'codex doctor did not verify executable binary\n%s\n' "$CODEX_DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$CODEX_DOCTOR_OUTPUT" | grep -q 'Codex live wake helper is executable' || {
  printf 'codex doctor did not verify the live wake helper\n%s\n' "$CODEX_DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$CODEX_DOCTOR_OUTPUT" | grep -q 'Codex LMAS wrapper is executable' || {
  printf 'codex doctor did not verify executable wrapper\n%s\n' "$CODEX_DOCTOR_OUTPUT" >&2
  exit 1
}
chmod 0644 "$TMP_HOME/.codex/skills/let-my-agent-sleep/scripts/lmas.sh"
CODEX_DOCTOR_FAIL_OUTPUT="$SERVER_DIR/codex-doctor-fail.out"
if cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent codex --yes >"$CODEX_DOCTOR_FAIL_OUTPUT" 2>&1; then
  printf 'codex doctor should fail when wrapper is not executable\n' >&2
  cat "$CODEX_DOCTOR_FAIL_OUTPUT" >&2
  exit 1
fi
grep -q 'Codex LMAS wrapper is missing or not executable' "$CODEX_DOCTOR_FAIL_OUTPUT" || {
  printf 'codex doctor failure did not explain non-executable wrapper\n' >&2
  cat "$CODEX_DOCTOR_FAIL_OUTPUT" >&2
  exit 1
}

CLAUDE_INSTALL_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js install --agent claude --yes)
printf '%s\n' "$CLAUDE_INSTALL_OUTPUT" | grep -q 'Claude Code install configured' || {
  printf 'claude install did not complete before doctor test\n' >&2
  exit 1
}
CLAUDE_DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent claude --yes)
printf '%s\n' "$CLAUDE_DOCTOR_OUTPUT" | grep -q 'Claude Code LMAS binary asset is executable' || {
  printf 'claude doctor did not verify executable binary asset\n%s\n' "$CLAUDE_DOCTOR_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$CLAUDE_DOCTOR_OUTPUT" | grep -q 'Claude Code LMAS wrapper asset is executable' || {
  printf 'claude doctor did not verify executable wrapper asset\n%s\n' "$CLAUDE_DOCTOR_OUTPUT" >&2
  exit 1
}
chmod 0644 "$TMP_HOME/.claude/lmas/let-my-agent-sleep/bin/lmas.sh"
CLAUDE_DOCTOR_FAIL_OUTPUT="$SERVER_DIR/claude-doctor-fail.out"
if cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent claude --yes >"$CLAUDE_DOCTOR_FAIL_OUTPUT" 2>&1; then
  printf 'claude doctor should fail when binary asset is not executable\n' >&2
  cat "$CLAUDE_DOCTOR_FAIL_OUTPUT" >&2
  exit 1
fi
grep -q 'Claude Code LMAS binary asset is missing or not executable' "$CLAUDE_DOCTOR_FAIL_OUTPUT" || {
  printf 'claude doctor failure did not explain non-executable binary asset\n' >&2
  cat "$CLAUDE_DOCTOR_FAIL_OUTPUT" >&2
  exit 1
}

cat > "$SERVER_DIR/server.mjs" <<'JS'
import http from "node:http"

const mode = process.argv[2]
const expectedDirectory = process.argv[3] || ""
const expectedWorkspace = process.argv[4] || ""
const expectedAuth = `Basic ${Buffer.from("opencode:s3cr3t").toString("base64")}`
const server = http.createServer((request, response) => {
  const url = new URL(request.url, "http://127.0.0.1")
  if (url.pathname !== "/experimental/tool/ids") {
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
      response.end(JSON.stringify(["bash", "lmas_start", "lmas_status", "lmas_cancel", "lmas_info"]))
    }, 3000)
    return
  }

  if (mode === "directory-ok" && url.searchParams.get("directory") !== expectedDirectory) {
    response.writeHead(200, { "content-type": "application/json" })
    response.end(JSON.stringify(["bash"]))
    return
  }

  if (mode === "workspace-ok" && url.searchParams.get("workspace") !== expectedWorkspace) {
    response.writeHead(200, { "content-type": "application/json" })
    response.end(JSON.stringify(["bash"]))
    return
  }

  const tools = mode === "ok"
    || mode === "auth-ok"
    || mode === "directory-ok"
    || mode === "workspace-ok"
    ? ["bash", "lmas_start", "lmas_status", "lmas_cancel", "lmas_info"]
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

WORKSPACE_DIR="$TMP_HOME/workspace with spaces"
mkdir -p "$WORKSPACE_DIR"
node "$SERVER_DIR/server.mjs" directory-ok "$WORKSPACE_DIR" > "$SERVER_DIR/port" &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$SERVER_DIR/port" ] && break
  sleep 0.1
done
DIRECTORY_SERVER_URL="http://127.0.0.1:$(cat "$SERVER_DIR/port")"

DIRECTORY_DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --server-url "$DIRECTORY_SERVER_URL" --directory "$WORKSPACE_DIR" --yes)
printf '%s\n' "$DIRECTORY_DOCTOR_OUTPUT" | grep -q 'OpenCode live server exposes LMAS tools' || {
  printf 'doctor did not pass workspace directory to live OpenCode tool check\n%s\n' "$DIRECTORY_DOCTOR_OUTPUT" >&2
  exit 1
}

kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" >/dev/null 2>&1 || true
SERVER_PID=""
rm -f "$SERVER_DIR/port"

WORKSPACE_ID="workspace-id-with-spaces"
node "$SERVER_DIR/server.mjs" workspace-ok "" "$WORKSPACE_ID" > "$SERVER_DIR/port" &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$SERVER_DIR/port" ] && break
  sleep 0.1
done
WORKSPACE_SERVER_URL="http://127.0.0.1:$(cat "$SERVER_DIR/port")"

WORKSPACE_DOCTOR_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --server-url "$WORKSPACE_SERVER_URL" --workspace "$WORKSPACE_ID" --yes)
printf '%s\n' "$WORKSPACE_DOCTOR_OUTPUT" | grep -q 'OpenCode live server exposes LMAS tools' || {
  printf 'doctor did not pass workspace id to live OpenCode tool check\n%s\n' "$WORKSPACE_DOCTOR_OUTPUT" >&2
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

cat > "$TMP_HOME/.config/opencode/oh-my-openagent.json" <<'JSON'
{
  "disabled_hooks": ["todo-continuation-enforcer", "user-custom-hook"],
  "disabled_skills": ["user-custom-skill"]
}
JSON
OMO_RESIDUE_BEFORE=$(shasum "$TMP_HOME/.config/opencode/oh-my-openagent.json")
OMO_RESIDUE_OUTPUT=$(cd "$ROOT" && HOME="$TMP_HOME" node packages/let-my-agent-sleep/bin/lmas-install.js doctor --agent opencode --yes)
printf '%s\n' "$OMO_RESIDUE_OUTPUT" | grep -q 'may be LMAS 0.3.0 residue: todo-continuation-enforcer' || {
  printf 'doctor did not warn about possible 0.3.0 OMO residue\n%s\n' "$OMO_RESIDUE_OUTPUT" >&2
  exit 1
}
OMO_RESIDUE_AFTER=$(shasum "$TMP_HOME/.config/opencode/oh-my-openagent.json")
[ "$OMO_RESIDUE_BEFORE" = "$OMO_RESIDUE_AFTER" ] || { printf 'doctor modified OMO config while reporting residue\n' >&2; exit 1; }

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
