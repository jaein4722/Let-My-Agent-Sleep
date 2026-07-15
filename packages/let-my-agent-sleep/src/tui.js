import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { analyzeLmasHandoffState } from "./omo-guard.js"
import {
  describeSessionState,
  getGlobalSessionGuards,
} from "./runtime-state.js"

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const packageJson = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"))

function getSessionMessages(api, sessionID) {
  if (!sessionID) return []
  try {
    return Array.from(api?.state?.session?.messages?.(sessionID) || [])
  } catch {
    return []
  }
}

function getWorkspaceDirectory(api) {
  return api?.state?.path?.directory || api?.state?.path?.worktree || process.cwd()
}

function compactRunId(runId) {
  const value = String(runId || "")
  if (value.length <= 32) return value
  return `${value.slice(0, 18)}...${value.slice(-8)}`
}

function formatElapsed(seconds) {
  const value = Number(seconds)
  if (!Number.isFinite(value) || value < 0) return ""
  if (value < 60) return `${Math.floor(value)}s`
  const minutes = Math.floor(value / 60)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  return rest > 0 ? `${hours}h${rest}m` : `${hours}h`
}

function formatGuardLine(guard, historyActive) {
  if (guard.available && guard.active) return "Guard active"
  if (guard.available && !guard.active && historyActive) return "Guard inactive; handoff visible"
  if (guard.available) return "Guard inactive"
  return historyActive ? "Guard unknown; handoff visible" : "Guard unknown"
}

export function createLmasSidebarText(api, sessionID) {
  const messages = getSessionMessages(api, sessionID)
  const history = analyzeLmasHandoffState(messages, sessionID)
  const sessionGuards = getGlobalSessionGuards()
  const state = describeSessionState({
    sessionGuards,
    sessionID,
    cwd: getWorkspaceDirectory(api),
    extraRunIds: history.activeRunIds,
  })
  const guard = state.guard
  const activeRuns = state.runs.filter((run) => ["RUNNING", "FINALIZING"].includes(run.status))
  const visibleRuns = activeRuns.length > 0 ? activeRuns : state.runs.slice(0, 3)

  const lines = [
    "LMAS",
    formatGuardLine(guard, history.active),
  ]

  if (history.activeRunIds.length > 0) {
    lines.push(`History active: ${history.activeRunIds.length}`)
  }

  if (visibleRuns.length === 0) {
    lines.push("No active jobs")
  } else {
    for (const run of visibleRuns.slice(0, 4)) {
      const elapsed = formatElapsed(run.elapsedSeconds)
      const suffix = elapsed ? ` ${elapsed}` : ""
      lines.push(`${compactRunId(run.runId)} ${run.status}${suffix}`)
      if (run.commandSummary) lines.push(`  ${run.commandSummary}`)
    }
  }

  lines.push(`v${packageJson.version}`)
  return lines.join("\n")
}

export const LetMyAgentSleepTuiPlugin = async (api) => {
  const renderSidebar = (input = {}) => {
    const sessionID = input.session_id || input.sessionID
    return createLmasSidebarText(api, sessionID)
  }

  const unregister = api.slots.register({
    slots: {
      sidebar_content: renderSidebar,
    },
    render(input = {}) {
      if (input.name !== "sidebar_content") return null
      return renderSidebar(input)
    },
  })

  api.lifecycle?.onDispose?.(() => {
    if (typeof unregister === "function") unregister()
  })
}

export const tui = LetMyAgentSleepTuiPlugin
export default LetMyAgentSleepTuiPlugin
