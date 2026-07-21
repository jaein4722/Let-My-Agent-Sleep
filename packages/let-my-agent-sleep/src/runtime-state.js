import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs"
import { createHash, randomUUID } from "node:crypto"
import { dirname, join, resolve } from "node:path"
import { spawnSync } from "node:child_process"

export const sessionGuardsSymbol = Symbol.for("let-my-agent-sleep.opencode.session-guards")
export const eventTextBuffersSymbol = Symbol.for("let-my-agent-sleep.opencode.event-text-buffers")
export const guardStateBridgesSymbol = Symbol.for("let-my-agent-sleep.opencode.guard-state-bridges")
export const GUARD_STATE_VERSION = 1
export const GUARD_STATE_HEARTBEAT_MS = 5000
export const GUARD_STATE_STALE_MS = 15000

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

export function resolveGuardStateDir(cwd) {
  return join(dirname(resolveRunsDir(cwd)), "opencode-guard-state")
}

function guardStateKey(sessionID) {
  return createHash("sha256").update(String(sessionID || "")).digest("hex")
}

export function resolveGuardStateFile(cwd, sessionID) {
  return join(resolveGuardStateDir(cwd), `${guardStateKey(sessionID)}.json`)
}

export function readSessionGuardState({ cwd, sessionID, now = Date.now(), staleAfterMs = GUARD_STATE_STALE_MS } = {}) {
  if (!sessionID) {
    return {
      active: false,
      available: false,
      observed: false,
      stale: false,
      reason: "missing_session_id",
      runIds: [],
    }
  }

  const file = resolveGuardStateFile(cwd, sessionID)
  if (!existsSync(file)) {
    return {
      active: false,
      available: false,
      observed: false,
      stale: false,
      reason: "missing_state",
      runIds: [],
      file,
    }
  }

  try {
    const value = JSON.parse(readFileSync(file, "utf8"))
    if (
      value?.version !== GUARD_STATE_VERSION
      || value?.sessionId !== sessionID
      || typeof value?.active !== "boolean"
      || !Number.isFinite(value?.updatedAt)
    ) {
      throw new Error("invalid guard state")
    }

    const ageMs = Math.max(0, now - value.updatedAt)
    const stale = ageMs > staleAfterMs
    return {
      active: !stale && value.active === true,
      available: !stale,
      observed: true,
      stale,
      reason: stale ? "stale_state" : undefined,
      runIds: Array.isArray(value.runIds) ? value.runIds.filter((runId) => typeof runId === "string") : [],
      source: value.source === "recovered" ? "recovered" : "runtime",
      updatedAt: value.updatedAt,
      ageMs,
      writerId: typeof value.writerId === "string" ? value.writerId : "",
      file,
    }
  } catch {
    return {
      active: false,
      available: false,
      observed: true,
      stale: false,
      reason: "invalid_state",
      runIds: [],
      file,
    }
  }
}

export function writeSessionGuardState({ cwd, sessionID, guard, writerId = "", now = Date.now() } = {}) {
  if (!sessionID) return false
  const stateDir = resolveGuardStateDir(cwd)
  const file = resolveGuardStateFile(cwd, sessionID)
  const temp = `${file}.${process.pid}.${randomUUID()}.tmp`
  const value = {
    version: GUARD_STATE_VERSION,
    sessionId: sessionID,
    active: guard?.active === true,
    runIds: Array.isArray(guard?.runIds) ? guard.runIds.filter((runId) => typeof runId === "string") : [],
    source: guard?.recovered === true ? "recovered" : "runtime",
    updatedAt: now,
    writerId,
  }

  try {
    mkdirSync(stateDir, { recursive: true, mode: 0o700 })
    writeFileSync(temp, `${JSON.stringify(value)}\n`, { mode: 0o600 })
    renameSync(temp, file)
    chmodSync(file, 0o600)
    return true
  } catch {
    try {
      unlinkSync(temp)
    } catch {
      // Ignore cleanup failures; the next atomic write uses a unique path.
    }
    return false
  }
}

export function removeSessionGuardState({ cwd, sessionID } = {}) {
  if (!sessionID) return false
  try {
    unlinkSync(resolveGuardStateFile(cwd, sessionID))
    return true
  } catch {
    return false
  }
}

export function listRunsForSession({ cwd, sessionID, runIds = [], limit = 5 } = {}) {
  const runsDir = resolveRunsDir(cwd)
  if (!existsSync(runsDir)) return []

  const wanted = new Set((runIds || []).filter(Boolean))
  const runs = []
  for (const entry of readdirSync(runsDir, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith("lmas_")) continue
    const runDir = join(runsDir, entry.name)
    if (sessionID || wanted.size > 0) {
      const metadata = join(runDir, "metadata.txt")
      const metadataRunID = readMetadataField(metadata, "run_id")
      const metadataSessionID = readMetadataField(metadata, "opencode_session_id")
      if (
        !wanted.has(entry.name)
        && !wanted.has(metadataRunID)
        && !(sessionID && metadataSessionID === sessionID)
      ) continue
    }

    const run = summarizeRunDir(runDir)
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

export function rehydrateSessionGuardsFromRuns({ sessionGuards, cwd, now = Date.now() } = {}) {
  if (!sessionGuards?.set) return []
  const runs = listRunsForSession({ cwd, limit: Number.MAX_SAFE_INTEGER })
    .filter((run) => run.opencodeSessionId && ["RUNNING", "FINALIZING"].includes(run.status))
  const grouped = new Map()

  for (const run of runs) {
    const values = grouped.get(run.opencodeSessionId) || []
    values.push(run.runId)
    grouped.set(run.opencodeSessionId, values)
  }

  for (const [sessionID, recoveredRunIds] of grouped) {
    const existing = sessionGuards.get(sessionID)
    const runIds = [...new Set([
      ...(existing?.active && Array.isArray(existing.runIds) ? existing.runIds : []),
      ...recoveredRunIds,
    ])]
    if (existing?.active) {
      sessionGuards.set(sessionID, {
        ...existing,
        runIds,
      })
      continue
    }
    sessionGuards.set(sessionID, {
      active: runIds.length > 0,
      omoTurn: runIds.length > 0,
      allowCancel: false,
      allowStatus: false,
      runIds,
      updatedAt: now,
      recovered: true,
    })
  }

  return [...grouped.keys()]
}

function getGlobalGuardStateBridges() {
  const existing = globalThis[guardStateBridgesSymbol]
  if (existing instanceof Map) return existing
  const bridges = new Map()
  globalThis[guardStateBridgesSymbol] = bridges
  return bridges
}

export function getOrCreateSessionGuardBridge({
  cwd,
  sessionGuards,
  heartbeatMs = GUARD_STATE_HEARTBEAT_MS,
} = {}) {
  const root = resolveGuardStateDir(cwd)
  const bridges = getGlobalGuardStateBridges()
  const existing = bridges.get(root)
  if (existing) return existing

  const trackedSessionIds = new Set()
  const writerId = `${process.pid}:${randomUUID()}`

  const bridge = {
    root,
    writerId,
    track(sessionID) {
      if (!sessionID) return false
      const guard = sessionGuards?.get?.(sessionID)
      if (!guard?.active) {
        const wasTracked = trackedSessionIds.delete(sessionID)
        const stateFileExists = existsSync(resolveGuardStateFile(cwd, sessionID))
        return wasTracked || stateFileExists
          ? removeSessionGuardState({ cwd, sessionID })
          : false
      }
      trackedSessionIds.add(sessionID)
      return bridge.flush(sessionID)
    },
    clear(sessionID) {
      if (!sessionID) return false
      trackedSessionIds.delete(sessionID)
      return removeSessionGuardState({ cwd, sessionID })
    },
    flush(sessionID) {
      if (!sessionID) return false
      return writeSessionGuardState({
        cwd,
        sessionID,
        guard: sessionGuards?.get?.(sessionID),
        writerId,
      })
    },
    flushAll() {
      for (const sessionID of trackedSessionIds) bridge.flush(sessionID)
    },
    stop() {
      clearInterval(bridge.timer)
      bridges.delete(root)
    },
    trackedSessionIds,
  }

  bridge.timer = setInterval(() => bridge.flushAll(), heartbeatMs)
  bridge.timer.unref?.()
  bridges.set(root, bridge)
  return bridge
}
