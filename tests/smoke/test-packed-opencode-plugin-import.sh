#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-packed-plugin-import.XXXXXX")
PACK_DIR="$TMPDIR_ROOT/pack"
mkdir -p "$PACK_DIR"

cd "$ROOT" || exit 1

if ! node --input-type=module -e 'await import("@opencode-ai/plugin")' >/dev/null 2>&1; then
  printf 'skip packed opencode plugin import: npm dependencies are not installed\n'
  exit 0
fi

PLUGIN_ROOT=$(node --input-type=module -e '
import { dirname } from "node:path"
import { fileURLToPath } from "node:url"
console.log(dirname(fileURLToPath(import.meta.resolve("@opencode-ai/plugin"))))
')

PACK_OUTPUT=$(npm_config_cache="$TMPDIR_ROOT/npm-cache" npm pack --workspace let-my-agent-sleep --pack-destination "$PACK_DIR" --silent)
TARBALL=$(find "$PACK_DIR" -maxdepth 1 -type f -name 'let-my-agent-sleep-*.tgz' -print | head -n 1)

[ -n "$TARBALL" ] || {
  printf 'npm pack did not produce let-my-agent-sleep tarball\n' >&2
  printf '%s\n' "$PACK_OUTPUT" >&2
  exit 1
}

tar -xzf "$TARBALL" -C "$TMPDIR_ROOT"
mkdir -p "$TMPDIR_ROOT/package/node_modules/@opencode-ai"
ln -s "$PLUGIN_ROOT" "$TMPDIR_ROOT/package/node_modules/@opencode-ai/plugin"

if ! node --input-type=module - "$TMPDIR_ROOT/package/src/index.js" <<'JS'
const pluginPath = process.argv[2]
const module = await import(pluginPath)
const plugin = module.default
const { LetMyAgentSleepPlugin } = module

let fetchCalls = 0
globalThis.fetch = async () => {
  fetchCalls += 1
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "content-type": "application/json" },
  })
}

const hooks = await LetMyAgentSleepPlugin({ serverUrl: new URL("http://127.0.0.1:4096") })

if (typeof plugin !== "function") {
  throw new Error("default export is not a plugin function")
}

for (const hookName of [
  "event",
  "chat.message",
  "experimental.chat.messages.transform",
  "experimental.chat.system.transform",
  "experimental.compaction.autocontinue",
  "experimental.session.compacting",
  "tool.execute.before",
  "tool.execute.after",
  "shell.env",
  "command.execute.before",
  "permission.ask",
]) {
  if (typeof hooks[hookName] !== "function") {
    throw new Error(`missing hook: ${hookName}`)
  }
}

for (const toolName of ["lmas_start", "lmas_status", "lmas_cancel", "lmas_info"]) {
  const definition = hooks.tool?.[toolName]
  if (!definition || typeof definition.execute !== "function") {
    throw new Error(`missing tool definition: ${toolName}`)
  }
}

if (!hooks.tool.lmas_start.args.command.safeParse("echo ok").success) {
  throw new Error("lmas_start command schema did not accept a string")
}

if (!hooks.tool.lmas_status.args.run_id.safeParse("lmas_test").success) {
  throw new Error("lmas_status run_id schema did not accept a string")
}
if (!hooks.tool.lmas_status.description.includes("FINALIZING")) {
  throw new Error("packed lmas_status description does not mention FINALIZING stop behavior")
}

if (!hooks.tool.lmas_cancel.args.run_id.safeParse("lmas_test").success) {
  throw new Error("lmas_cancel run_id schema did not accept a string")
}

const info = await hooks.tool.lmas_info.execute({}, { sessionID: "ses_packed_info" })
if (!info.includes("LMAS_INFO v1") || !info.includes("version:")) {
  throw new Error("packed lmas_info did not return diagnostic info")
}

const messages = [
  {
    info: { role: "assistant", sessionID: "ses_packed_import", id: "assistant_handoff" },
    parts: [{ type: "text", text: "LMAS_HANDOFF v1\nrun_id: lmas_packed_import\nstatus: STARTED" }],
  },
  {
    info: { role: "user", sessionID: "ses_packed_import", id: "synthetic_continue" },
    parts: [{ type: "text", text: "Continue working on the remaining task.", synthetic: true }],
  },
]
hooks["experimental.chat.messages.transform"]({}, { messages })

await hooks.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: "ses_packed_import",
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_packed_import\nstatus: STARTED",
    },
  },
})

const blockedMarkerlessPrompt = await fetch("http://127.0.0.1:4096/session/ses_packed_import/prompt_async", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "ordinary retry prompt without internal marker" }],
  }),
})

if (blockedMarkerlessPrompt.status !== 204 || blockedMarkerlessPrompt.headers.get("x-lmas-guard") !== "active") {
  throw new Error("packed plugin did not no-op markerless prompt injection during active handoff")
}

if (fetchCalls !== 0) {
  throw new Error("packed plugin markerless prompt injection reached underlying fetch")
}

const compactionAutocontinueOutput = { enabled: true }
await hooks["experimental.compaction.autocontinue"](
  { sessionID: "ses_packed_import", agent: "sisyphus" },
  compactionAutocontinueOutput,
)

if (compactionAutocontinueOutput.enabled !== false) {
  throw new Error("packed plugin did not disable compaction autocontinue during active handoff")
}

const sessionCompactingOutput = { context: [] }
await hooks["experimental.session.compacting"](
  { sessionID: "ses_packed_import" },
  sessionCompactingOutput,
)
if (
  sessionCompactingOutput.context.length !== 1
  || !sessionCompactingOutput.context[0].includes("LMAS handoff is active")
  || !sessionCompactingOutput.context[0].includes("lmas_packed_import")
) {
  throw new Error("packed plugin did not preserve LMAS handoff state in compaction context")
}

const systemTransformOutput = { system: [] }
await hooks["experimental.chat.system.transform"](
  { sessionID: "ses_packed_import", model: {} },
  systemTransformOutput,
)
if (
  systemTransformOutput.system.length !== 1
  || !systemTransformOutput.system[0].includes("LMAS handoff is active")
  || !systemTransformOutput.system[0].includes("lmas_packed_import")
) {
  throw new Error("packed plugin did not preserve LMAS handoff state in system context")
}

const args = { command: "cat stdout.log", timeout: 60000 }
const output = { args }
await hooks["tool.execute.before"](
  { tool: "bash", sessionID: "ses_packed_import", callID: "call_packed_import" },
  output,
)

if (output.args !== args) {
  throw new Error("tool.execute.before replaced the original args object")
}

if (!args.command.includes("LMAS handoff is active")) {
  throw new Error("tool.execute.before did not mutate original args object in place")
}

const commandOutput = {
  parts: [{
    type: "text",
    text: "Continue working on the remaining task.",
    synthetic: true,
    metadata: { compaction_continue: true },
  }],
}
await hooks["command.execute.before"](
  { command: "start-work", arguments: "", sessionID: "ses_packed_import" },
  commandOutput,
)
if (
  commandOutput.parts.length !== 1
  || !commandOutput.parts[0].text.includes("LMAS handoff is active")
  || commandOutput.parts[0].metadata?.lmas_guard !== true
) {
  throw new Error("packed command.execute.before did not neutralize OMO command during active handoff")
}
JS
then
  exit 1
fi

printf 'ok packed opencode plugin import\n'
