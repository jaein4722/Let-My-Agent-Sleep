import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { jsx } from "@opentui/solid/jsx-runtime"
import { createSignal, onCleanup } from "solid-js"
import { analyzeLmasHandoffState } from "./omo-guard.js"
import {
  describeSessionState,
  readSessionGuardState,
} from "./runtime-state.js"

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const packageJson = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"))
const sidebarRefreshMs = 5000

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

function formatGuardLine(guard, historyActive, activeRunCount) {
  if (guard.available && guard.active) {
    return guard.source === "recovered" ? "Guard active (recovered)" : "Guard active"
  }
  if (guard.stale && activeRunCount > 0) return "Guard stale; job running"
  if (guard.available && historyActive) return "Guard inactive; handoff visible"
  if (guard.available && activeRunCount > 0) return "Guard inactive; job running"
  if (historyActive) return "Guard unverified; handoff visible"
  if (activeRunCount > 0) return "Guard unavailable; job running"
  return "Guard inactive"
}

export function createLmasSidebarText(api, sessionID, options = {}) {
  const messages = getSessionMessages(api, sessionID)
  const history = analyzeLmasHandoffState(messages, sessionID)
  const cwd = getWorkspaceDirectory(api)
  const state = describeSessionState({
    sessionID,
    cwd,
    extraRunIds: history.activeRunIds,
  })
  const activeRuns = state.runs.filter((run) => ["RUNNING", "FINALIZING"].includes(run.status))
  const visibleRuns = activeRuns.length > 0 ? activeRuns : state.runs.slice(0, 3)
  const guard = readSessionGuardState({
    cwd,
    sessionID,
    now: options.now,
  })

  const lines = [
    "LMAS",
    formatGuardLine(guard, history.active, activeRuns.length),
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

function LmasSidebarContent(props) {
  const [revision, setRevision] = createSignal(0)
  const timer = setInterval(() => setRevision((value) => value + 1), sidebarRefreshMs)
  timer.unref?.()
  onCleanup(() => clearInterval(timer))

  return jsx("box", {
    flexDirection: "column",
    paddingLeft: 1,
    paddingRight: 1,
    children: jsx("text", {
      get children() {
        revision()
        return createLmasSidebarText(props.api, props.sessionID)
      },
    }),
  })
}

export const LetMyAgentSleepTuiPlugin = async (api) => {
  if (!api?.slots?.register) return

  const renderSidebar = (input = {}) => {
    const sessionID = input.session_id || input.sessionID
    return jsx(LmasSidebarContent, {
      api,
      sessionID,
    })
  }

  const slotId = api.slots.register({
    order: 100,
    slots: {
      sidebar_content(_context, input = {}) {
        return renderSidebar(input)
      },
    },
  })

  api.lifecycle?.onDispose?.(() => {
    // OpenCode owns slot cleanup for registered TUI plugins. Keep the generated
    // slot id referenced so plugin load diagnostics can expose registration.
    void slotId
  })
}

export const tui = LetMyAgentSleepTuiPlugin
export default { tui }
