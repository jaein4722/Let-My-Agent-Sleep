#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

cd "$ROOT" || exit 1

if ! node --input-type=module -e 'await import("@opencode-ai/plugin")' >/dev/null 2>&1; then
  printf 'skip opencode plugin real import: npm dependencies are not installed\n'
  exit 0
fi

node --input-type=module - <<'JS'
import { LetMyAgentSleepPlugin } from "./packages/let-my-agent-sleep/src/index.js"

const module = await import("./packages/let-my-agent-sleep/src/index.js")
const functionExports = Object.entries(module).filter(([, value]) => typeof value === "function")
if (functionExports.length !== 1 || functionExports[0][0] !== "LetMyAgentSleepPlugin") {
  throw new Error(`expected exactly one plugin function export, got: ${functionExports.map(([name]) => name).join(", ")}`)
}

const hooks = await LetMyAgentSleepPlugin({ serverUrl: new URL("http://127.0.0.1:4096") })

const officialGuardHooks = [
  "event",
  "chat.message",
  "experimental.chat.messages.transform",
  "experimental.chat.system.transform",
  "experimental.session.compacting",
  "tool.execute.before",
  "tool.execute.after",
  "shell.env",
  "command.execute.before",
  "permission.ask",
]
const compatibilityGuardHooks = [
  "experimental.compaction.autocontinue",
]

for (const hookName of officialGuardHooks) {
  if (typeof hooks[hookName] !== "function") {
    throw new Error(`missing official guard hook: ${hookName}`)
  }
}

for (const hookName of compatibilityGuardHooks) {
  if (typeof hooks[hookName] !== "function") {
    throw new Error(`missing compatibility guard hook: ${hookName}`)
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
  throw new Error("lmas_status description does not mention FINALIZING stop behavior")
}

if (!hooks.tool.lmas_cancel.args.run_id.safeParse("lmas_test").success) {
  throw new Error("lmas_cancel run_id schema did not accept a string")
}

const info = await hooks.tool.lmas_info.execute({}, { sessionID: "ses_info_test" })
if (!info.includes("LMAS_INFO v1") || !info.includes("version:")) {
  throw new Error("lmas_info did not return diagnostic info")
}

console.log("ok opencode plugin real import")
JS
