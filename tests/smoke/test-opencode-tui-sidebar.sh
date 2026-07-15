#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-tui-sidebar.XXXXXX")

cleanup() {
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

cd "$ROOT"

node --input-type=module - "$TMPDIR_ROOT" <<'JS'
import { mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import {
  LetMyAgentSleepTuiPlugin,
  createLmasSidebarText,
  tui,
} from "./packages/let-my-agent-sleep/src/tui.js"
import tuiModule from "./packages/let-my-agent-sleep/src/tui.js"

const root = process.argv[2]
const sessionID = "ses_tui_sidebar"
const runID = "lmas_tui_sidebar"
const runDir = join(root, ".lmas", "runs", runID)
mkdirSync(runDir, { recursive: true })
writeFileSync(join(runDir, "metadata.txt"), [
  `run_id=${runID}`,
  "adapter=opencode",
  `opencode_session_id=${sessionID}`,
  `cwd=${root}`,
  "command='bash' '-lc' 'echo tui'",
  "started_at=2026-07-15T00:00:00+0900",
  "started_epoch=1784041200",
  "artifacts_dir=.lmas/artifacts/tui",
  "",
].join("\n"))
writeFileSync(join(runDir, "handoff.txt"), [
  "LMAS_HANDOFF v1",
  `run_id: ${runID}`,
  "status: STARTED",
  `cwd: ${root}`,
  "command: 'bash' '-lc' 'echo tui'",
  "pid_or_job_id: tmux:lmas_tui_sidebar",
  "",
].join("\n"))
writeFileSync(join(runDir, "exit_code"), "0\n")

const messages = [
  {
    info: { role: "assistant", sessionID, id: "assistant_handoff" },
    parts: [{ type: "text", text: `LMAS_HANDOFF v1\nrun_id: ${runID}\nstatus: STARTED` }],
  },
  {
    info: { role: "user", sessionID, id: "synthetic_continue" },
    parts: [{ type: "text", text: "Continue working on the remaining task.", synthetic: true }],
  },
]

const api = {
  state: {
    path: { directory: root },
    session: {
      messages(id) {
        return id === sessionID ? messages : []
      },
    },
  },
  slots: {
    register(plugin) {
      api.registeredPlugin = plugin
      return "slot_lmas_sidebar"
    },
  },
  lifecycle: {
    onDispose(fn) {
      api.dispose = fn
    },
  },
}

const text = createLmasSidebarText(api, sessionID)
for (const expected of ["LMAS", "Guard", "History active: 1", runID, "FINALIZING", "'bash' '-lc' 'echo tui'"]) {
  if (!text.includes(expected)) {
    throw new Error(`sidebar text missing ${expected}: ${text}`)
  }
}

if (tui !== LetMyAgentSleepTuiPlugin) {
  throw new Error("tui named export does not match LetMyAgentSleepTuiPlugin")
}
if (tuiModule?.tui !== LetMyAgentSleepTuiPlugin) {
  throw new Error("default TUI plugin export must expose tui()")
}

await LetMyAgentSleepTuiPlugin(api)
if (!api.registeredPlugin || api.registeredPlugin.id !== undefined) {
  throw new Error("TUI plugin registered an unsupported explicit slot plugin id")
}

await LetMyAgentSleepTuiPlugin({})
if (!api.registeredPlugin) {
  throw new Error("server-context TUI no-op cleared the registered plugin")
}

if (typeof api.registeredPlugin.slots?.sidebar_content !== "function") {
  throw new Error("TUI plugin did not register a sidebar_content slot renderer")
}

api.dispose?.()

console.log("ok opencode tui sidebar")
JS
