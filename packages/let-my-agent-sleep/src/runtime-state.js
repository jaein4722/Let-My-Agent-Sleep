import { existsSync, readFileSync, readdirSync } from "node:fs"
import { join, resolve } from "node:path"
import { spawnSync } from "node:child_process"

export const sessionGuardsSymbol = Symbol.for("let-my-agent-sleep.opencode.session-guards")
export const eventTextBuffersSymbol = Symbol.for("let-my-agent-sleep.opencode.event-text-buffers")

export function getGlobalSessionGuards() {
  const existing = globalThis[sessionGuardsSymbol]
  if (existing instanceof Map) return existing
  const sessionGuards = new Map()
  globalThis[sessionGuardsSymbol] = sessionGuards
  return sessionGuards
}

export function getGlobalEventTextBuffers() {
  const existing = globalThis[eventTextBuffersSymbol]
  if (existing instanceof Map) return existing
  const eventTextBuffers = new Map()
  globalThis[eventTextBuffersSymbol] = eventTextBuffers
  return eventTextBuffers
}

export function getSessionGuardSnapshot(sessionGuards, sessionID) {
  if (!sessionID) {
    return {
      active: false,
      available: false,
      reason: "missing_session_id",
      runIds: [],
    }
  }

  const guard = sessionGuards?.get?.(sessionID)
  if (!guard) {
    return {
      active: false,
      available: true,
      runIds: [],
    }
  }

  return {
    active: guard.active === true,
    available: true,
    omoTurn: guard.omoTurn === true,
    allowCancel: guard.allowCancel === true,
    allowStatus: guard.allowStatus === true,
    runIds: Array.isArray(guard.runIds) ? [...guard.runIds] : [],
    updatedAt: guard.updatedAt,
  }
}

function readText(file) {
  try {
    return readFileSync(file, "utf8")
  } catch {
    return ""
  }
}

function readLineField(file, field) {
  const text = readText(file)
  if (!text) return ""
  const prefix = `${field}:`
  for (const line of text.split(/\r?\n/)) {
    if (line.startsWith(prefix)) return line.slice(prefix.length).trimStart()
  }
  return ""
}

function readMetadataField(file, field) {
  const text = readText(file)
  if (!text) return ""
  const prefix = `${field}=`
  for (const line of text.split(/\r?\n/)) {
    if (line.startsWith(prefix)) return line.slice(prefix.length)
  }
  return ""
}

function isProcessAlive(pid) {
  if (!/^[0-9]+$/.test(String(pid || ""))) return false
  try {
    process.kill(Number(pid), 0)
    return true
  } catch {
    return false
  }
}

function tmuxSessionAlive(runDir, watcherID, cwd) {
  if (!watcherID?.startsWith?.("tmux:")) return false
  const session = watcherID.slice("tmux:".length)
  if (!session) return false

  const socketFile = join(runDir, "tmux_socket.txt")
  const socket = existsSync(socketFile)
    ? readText(socketFile).split(/\r?\n/)[0]
    : `.lmas/tmux/${session}.sock`
  if (!socket) return false

  const spawnCwd = socket.startsWith("/") ? undefined : (cwd || process.cwd())
  const result = spawnSync("tmux", ["-S", socket, "has-session", "-t", session], {
    cwd: spawnCwd,
    stdio: "ignore",
    timeout: 1000,
  })
  return result.status === 0
}

function runStatusFromFiles(runDir) {
  const completionEvent = join(runDir, "completion_event.txt")
  if (existsSync(completionEvent)) {
    return {
      status: readLineField(completionEvent, "status") || "COMPLETED",
      exitCode: readLineField(completionEvent, "exit_code"),
      eventFile: completionEvent,
    }
  }

  const stagedCompletion = join(runDir, ".completion_event.txt")
  const exitCodeFile = join(runDir, "exit_code")
  if (existsSync(stagedCompletion) || existsSync(exitCodeFile)) {
    return {
      status: "FINALIZING",
      exitCode: existsSync(exitCodeFile)
        ? readText(exitCodeFile).split(/\r?\n/)[0]
        : readLineField(stagedCompletion, "exit_code"),
      eventFile: join(runDir, "handoff.txt"),
    }
  }

  const handoff = join(runDir, "handoff.txt")
  const metadata = join(runDir, "metadata.txt")
  if (!existsSync(handoff)) return { status: "MISSING", exitCode: "", eventFile: "" }

  const watcherID = readLineField(handoff, "pid_or_job_id")
  const cwd = readMetadataField(metadata, "cwd")
  const alive = watcherID?.startsWith?.("tmux:")
    ? tmuxSessionAlive(runDir, watcherID, cwd)
    : isProcessAlive(watcherID)
  return {
    status: alive ? "RUNNING" : "LOST",
    exitCode: "",
    eventFile: handoff,
  }
}

function elapsedSecondsForRun(runDir, status) {
  const metadata = join(runDir, "metadata.txt")
  const startedEpoch = Number(readMetadataField(metadata, "started_epoch"))
  if (!Number.isFinite(startedEpoch) || startedEpoch <= 0) return ""

  if (["RUNNING", "FINALIZING", "LOST"].includes(status)) {
    return String(Math.max(0, Math.floor(Date.now() / 1000) - startedEpoch))
  }

  const finishedEpoch = Number(readMetadataField(metadata, "finished_epoch"))
  if (!Number.isFinite(finishedEpoch) || finishedEpoch <= 0) return ""
  return String(Math.max(0, finishedEpoch - startedEpoch))
}

function shortCommand(command) {
  return String(command || "").replace(/\s+/g, " ").trim().slice(0, 96)
}

export function summarizeRunDir(runDir) {
  const metadata = join(runDir, "metadata.txt")
  const handoff = join(runDir, "handoff.txt")
  const statusInfo = runStatusFromFiles(runDir)
  const runID = readMetadataField(metadata, "run_id")
    || readLineField(statusInfo.eventFile, "run_id")
    || readLineField(handoff, "run_id")
    || runDir.split("/").pop()
  const command = readMetadataField(metadata, "command")
    || readLineField(handoff, "command")
  const cwd = readMetadataField(metadata, "cwd")
    || readLineField(handoff, "cwd")
  return {
    runId: runID,
    status: statusInfo.status,
    exitCode: statusInfo.exitCode,
    elapsedSeconds: elapsedSecondsForRun(runDir, statusInfo.status),
    command,
    commandSummary: shortCommand(command),
    cwd,
    runDir,
    stdout: join(runDir, "stdout.log"),
    stderr: join(runDir, "stderr.log"),
    metadata,
    opencodeSessionId: readMetadataField(metadata, "opencode_session_id"),
  }
}

export function resolveRunsDir(cwd) {
  if (process.env.LMAS_RUNS_DIR) return resolve(process.env.LMAS_RUNS_DIR)
  return resolve(cwd || process.cwd(), ".lmas/runs")
}

export function listRunsForSession({ cwd, sessionID, runIds = [], limit = 5 } = {}) {
  const runsDir = resolveRunsDir(cwd)
  if (!existsSync(runsDir)) return []

  const wanted = new Set((runIds || []).filter(Boolean))
  const runs = []
  for (const entry of readdirSync(runsDir, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith("lmas_")) continue
    const run = summarizeRunDir(join(runsDir, entry.name))
    if (
      wanted.has(run.runId)
      || (sessionID && run.opencodeSessionId === sessionID)
      || (wanted.size === 0 && !sessionID && ["RUNNING", "FINALIZING"].includes(run.status))
    ) {
      runs.push(run)
    }
  }

  runs.sort((a, b) => String(b.runId).localeCompare(String(a.runId)))
  return runs.slice(0, limit)
}

export function describeSessionState({ sessionGuards, sessionID, cwd, extraRunIds = [] } = {}) {
  const guard = getSessionGuardSnapshot(sessionGuards, sessionID)
  const runIds = [...new Set([...(guard.runIds || []), ...(extraRunIds || [])])]
  const runs = listRunsForSession({ cwd, sessionID, runIds })
  return {
    sessionID,
    guard,
    runs,
  }
}
