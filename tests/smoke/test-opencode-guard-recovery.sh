#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-opencode-guard-recovery.XXXXXX")

cleanup() {
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

cd "$ROOT"

node --input-type=module - "$TMPDIR_ROOT" <<'JS'
import { mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { LetMyAgentSleepPlugin } from "./packages/let-my-agent-sleep/src/index.js"
import {
  getGlobalSessionGuards,
  readSessionGuardState,
} from "./packages/let-my-agent-sleep/src/runtime-state.js"

const root = process.argv[2]
const recoveredSessionID = "ses_guard_recovery"
const recoveredRunID = "lmas_guard_recovery"
const lostSessionID = "ses_guard_recovery_lost"
const lostRunID = "lmas_guard_recovery_lost"

function writeRun({ runID, sessionID, finalizing }) {
  const runDir = join(root, ".lmas", "runs", runID)
  mkdirSync(runDir, { recursive: true })
  writeFileSync(join(runDir, "metadata.txt"), [
    `run_id=${runID}`,
    "adapter=opencode",
    `opencode_session_id=${sessionID}`,
    `cwd=${root}`,
    "command='bash' '-lc' 'sleep 600'",
    "started_at=2026-07-20T00:00:00+0900",
    "started_epoch=1784473200",
    `artifacts_dir=${runDir}`,
    "",
  ].join("\n"))
  writeFileSync(join(runDir, "handoff.txt"), [
    "LMAS_HANDOFF v1",
    `run_id: ${runID}`,
    "status: STARTED",
    `cwd: ${root}`,
    "command: 'bash' '-lc' 'sleep 600'",
    `pid_or_job_id: ${finalizing ? "tmux:guard_recovery_finalizing" : "missing-watcher"}`,
    "",
  ].join("\n"))
  if (finalizing) writeFileSync(join(runDir, "exit_code"), "0\n")
  return runDir
}

const recoveredRunDir = writeRun({
  runID: recoveredRunID,
  sessionID: recoveredSessionID,
  finalizing: true,
})
writeRun({
  runID: lostRunID,
  sessionID: lostSessionID,
  finalizing: false,
})

const sessionGuards = getGlobalSessionGuards()
sessionGuards.delete(recoveredSessionID)
sessionGuards.delete(lostSessionID)

const originalFetch = globalThis.fetch
globalThis.fetch = async () => new Response(JSON.stringify({ ok: true }), {
  status: 200,
  headers: { "content-type": "application/json" },
})

try {
  const hooks = await LetMyAgentSleepPlugin({
    directory: root,
    worktree: root,
    serverUrl: new URL("http://127.0.0.1:4096"),
  })

  const recoveredInfo = await hooks.tool.lmas_info.execute({}, {
    sessionID: recoveredSessionID,
    directory: root,
    worktree: root,
  })
  if (
    !recoveredInfo.includes("current_session_guard_active: true")
    || !recoveredInfo.includes(`current_session_guard_run_ids: ${recoveredRunID}`)
    || !recoveredInfo.includes(`current_session_run_1_status: FINALIZING`)
  ) {
    throw new Error(`restart recovery did not arm the matching session guard:\n${recoveredInfo}`)
  }

  const bridgeState = readSessionGuardState({ cwd: root, sessionID: recoveredSessionID })
  if (!bridgeState.available || !bridgeState.active || bridgeState.source !== "recovered") {
    throw new Error(`recovered guard was not published to the TUI bridge: ${JSON.stringify(bridgeState)}`)
  }

  const systemOutput = { system: [] }
  await hooks["experimental.chat.system.transform"](
    { sessionID: recoveredSessionID },
    systemOutput,
  )
  if (systemOutput.system.length !== 1 || !systemOutput.system[0].includes("handoff guard is active")) {
    throw new Error("recovered guard did not protect the next live model turn")
  }

  const lostInfo = await hooks.tool.lmas_info.execute({}, {
    sessionID: lostSessionID,
    directory: root,
    worktree: root,
  })
  if (
    !lostInfo.includes("current_session_guard_active: false")
    || !lostInfo.includes(`current_session_run_1_status: LOST`)
  ) {
    throw new Error(`LOST run should remain visible without arming a guard:\n${lostInfo}`)
  }

  const completionText = [
    "LMAS_COMPLETION_EVENT v1",
    `run_id: ${recoveredRunID}`,
    "status: SUCCEEDED",
    "exit_code: 0",
  ].join("\n")
  await hooks.event({
    event: {
      type: "message.updated",
      properties: {
        message: {
          id: "msg_guard_recovery_completion",
          sessionID: recoveredSessionID,
          role: "assistant",
          parts: [{ type: "text", text: completionText }],
        },
      },
    },
  })

  const completedInfo = await hooks.tool.lmas_info.execute({}, {
    sessionID: recoveredSessionID,
    directory: root,
    worktree: root,
  })
  if (!completedInfo.includes("current_session_guard_active: false")) {
    throw new Error(`completion did not clear a recovered guard:\n${completedInfo}`)
  }
  const completedBridgeState = readSessionGuardState({ cwd: root, sessionID: recoveredSessionID })
  if (completedBridgeState.observed || completedBridgeState.active) {
    throw new Error(`completion did not remove the cleared guard state: ${JSON.stringify(completedBridgeState)}`)
  }

  writeFileSync(join(recoveredRunDir, "completion_event.txt"), `${completionText}\n`)
  sessionGuards.delete(recoveredSessionID)
  await LetMyAgentSleepPlugin({
    directory: root,
    worktree: root,
    serverUrl: new URL("http://127.0.0.1:4096"),
  })
  if (sessionGuards.get(recoveredSessionID)?.active) {
    throw new Error("completed run was re-armed during a later plugin initialization")
  }
} finally {
  globalThis.fetch = originalFetch
}

console.log("ok opencode guard recovery")
JS
