import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { tool } from "@opencode-ai/plugin"
import {
  applyOmoContinuationGuard as applyOmoContinuationGuardToOutput,
  createBlockedToolMessage,
  createGuardedToolAction,
  getActiveOmoGuard,
  getSessionIDFromPromptInput,
  isReplyExpectingInternalPromptInput,
  shouldBlockPromptInputDuringActiveHandoff,
  updateSessionGuardFromCancelText,
  updateSessionGuardFromEvent,
  updateSessionGuardFromStatusText,
  updateSessionGuardFromText,
} from "./omo-guard.js"
import { omoContinuationHooks } from "./omo-constants.js"
import { findLmasScript } from "./find-lmas-script.js"
import {
  describeSessionState,
  getGlobalEventTextBuffers,
  getGlobalSessionGuards,
} from "./runtime-state.js"

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const packageJson = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"))
const sessionGuards = getGlobalSessionGuards()
const eventTextBuffers = getGlobalEventTextBuffers()
const promptGuardSymbol = Symbol.for("let-my-agent-sleep.opencode.prompt-guard")
const promptGuardSessions = new WeakSet()
const injectionGuardSymbol = Symbol.for("let-my-agent-sleep.opencode.injection-guard")
const injectionGuardRegistrySymbol = Symbol.for("let-my-agent-sleep.opencode.injection-guard.registry")
let injectionGuardGeneration

const injectionGuardHandler = {
  get(sessionID) {
    return getSessionActiveHandoff(sessionID)
  },
  mark(sessionID, guard) {
    sessionGuards.set(sessionID, {
      ...guard,
      omoTurn: true,
      updatedAt: Date.now(),
    })
  },
  entries() {
    return sessionGuards.entries()
  },
}

function applyOmoContinuationGuard(output, sessionID) {
  return applyOmoContinuationGuardToOutput(output, sessionGuards, Date.now(), sessionID)
}

function getSessionOmoGuard(sessionID) {
  return getActiveOmoGuard(sessionGuards, sessionID)
}

function getSessionActiveHandoff(sessionID) {
  if (!sessionID) return undefined
  const guard = sessionGuards.get(sessionID)
  return guard?.active ? guard : undefined
}

function markGuardedPollingAttempt(sessionID, guard) {
  if (!sessionID || !guard) return
  sessionGuards.set(sessionID, {
    ...guard,
    omoTurn: true,
    allowStatus: false,
    updatedAt: Date.now(),
  })
}

function getRuntimeSessionID(input) {
  return input?.sessionID
    || input?.sessionId
    || input?.session?.id
    || input?.context?.sessionID
    || input?.context?.sessionId
}

function createPromptGuardResponse(sessionID, runIds) {
  return {
    data: {
      id: `lmas_guard_${Date.now()}`,
      sessionID,
      lmas_guard: true,
      skipped: true,
      runIds,
    },
  }
}

function createCommandGuardPart(sessionID, runIds) {
  return {
    type: "text",
    text: createBlockedToolMessage(runIds),
    synthetic: true,
    metadata: {
      lmas_guard: true,
      sessionID,
      runIds,
    },
  }
}

function createFetchPromptGuardResponse(sessionID, runIds, pathname) {
  if (pathname?.endsWith("/prompt_async")) {
    return new Response(null, {
      status: 204,
      headers: {
        "x-lmas-guard": "active",
        "x-lmas-session-id": sessionID || "",
        "x-lmas-run-ids": (runIds || []).join(","),
      },
    })
  }

  return new Response(JSON.stringify({
    info: {
      id: `lmas_guard_${Date.now()}`,
      sessionID,
      path: pathname,
      role: "assistant",
      lmas_guard: true,
      skipped: true,
      runIds,
    },
    parts: [],
  }), {
    status: 200,
    headers: {
      "content-type": "application/json",
      "x-lmas-guard": "active",
    },
  })
}

function getFetchRequestMethod(input, init) {
  return String(init?.method || input?.method || "GET").toUpperCase()
}

function getFetchRequestUrl(input) {
  const raw = typeof input === "string" || input instanceof URL
    ? input
    : input?.url
  if (!raw) return undefined
  try {
    return new URL(raw)
  } catch {
    if (typeof raw !== "string" || !raw.startsWith("/")) return undefined
    const registry = getInjectionGuardRegistry()
    const base = registry.origins.values().next().value || "http://localhost:4096"
    try {
      return new URL(raw, base)
    } catch {
      return undefined
    }
  }
}

function getInjectionGuardRegistry() {
  const existing = globalThis[injectionGuardRegistrySymbol]
  if (existing?.origins instanceof Set) {
    if (typeof existing.nextGeneration !== "number") existing.nextGeneration = 0
    return existing
  }

  const registry = {
    origins: new Set(),
    currentHandler: undefined,
    nextGeneration: 0,
  }
  try {
    Object.defineProperty(globalThis, injectionGuardRegistrySymbol, {
      value: registry,
      enumerable: false,
      configurable: false,
    })
  } catch {
    try {
      globalThis[injectionGuardRegistrySymbol] = registry
    } catch {
      // If the global slot is unavailable, fall back to a per-module registry.
    }
  }
  return registry
}

function registerInjectionGuardHandler() {
  const registry = getInjectionGuardRegistry()
  if (injectionGuardGeneration === undefined) {
    injectionGuardGeneration = ++registry.nextGeneration
  }
  if (!registry.currentHandler || injectionGuardGeneration >= registry.currentHandler.generation) {
    const previousHandler = registry.currentHandler?.handler
    if (previousHandler && previousHandler !== injectionGuardHandler) {
      for (const [sessionID, guard] of previousHandler.entries?.() || []) {
        if (!sessionGuards.has(sessionID)) sessionGuards.set(sessionID, { ...guard })
      }
    }
    registry.currentHandler = {
      generation: injectionGuardGeneration,
      handler: injectionGuardHandler,
    }
  }
}

function rememberFetchGuardOrigin(serverUrl) {
  if (!serverUrl) return
  try {
    const url = new URL(String(serverUrl))
    getInjectionGuardRegistry().origins.add(url.origin)
    rememberLoopbackFetchGuardOrigins(url)
  } catch {
    // Invalid server URLs are handled by the caller paths that use them.
  }
}

function rememberLoopbackFetchGuardOrigins(url) {
  if (url.protocol !== "http:" && url.protocol !== "https:") return
  const hostname = url.hostname.replace(/^\[|\]$/g, "")
  if (!["localhost", "127.0.0.1", "::1", "0.0.0.0"].includes(hostname)) return

  const port = url.port ? `:${url.port}` : ""
  const hosts = ["localhost", "127.0.0.1", "[::1]"]
  if (hostname === "0.0.0.0") hosts.push("0.0.0.0")

  for (const host of hosts) {
    getInjectionGuardRegistry().origins.add(`${url.protocol}//${host}${port}`)
  }
}

function getPromptSessionIDFromUrl(url) {
  if (!url) return undefined
  const { origins } = getInjectionGuardRegistry()
  if (origins.size > 0 && !origins.has(url.origin)) return undefined
  const match = url?.pathname?.match(/\/session\/([^/]+)\/(prompt_async|message)$/)
  return match ? decodeURIComponent(match[1]) : undefined
}

function getInjectionGuardForSession(sessionID) {
  if (!sessionID) return undefined
  const registry = getInjectionGuardRegistry()
  const handler = registry.currentHandler?.handler
  const guard = handler?.get?.(sessionID)
  return guard ? { handler, guard } : undefined
}

async function readFetchBodyText(input, init) {
  const body = init?.body
  if (typeof body === "string") return body
  if (body instanceof Uint8Array) return new TextDecoder().decode(body)
  if (body && typeof body === "object" && typeof body.text === "function") {
    return body.text()
  }
  if (input && typeof input === "object" && typeof input.clone === "function") {
    return input.clone().text()
  }
  return ""
}

function installFetchPromptInjectionGuard(serverUrl) {
  rememberFetchGuardOrigin(serverUrl)
  registerInjectionGuardHandler()
  const fetchImpl = globalThis.fetch
  if (typeof fetchImpl !== "function" || fetchImpl[injectionGuardSymbol]) return false

  const guardedFetch = async function guardedFetch(input, init) {
    const method = getFetchRequestMethod(input, init)
    const url = getFetchRequestUrl(input)
    const sessionID = method === "POST" ? getPromptSessionIDFromUrl(url) : undefined
    const activeGuard = getInjectionGuardForSession(sessionID)

    if (activeGuard) {
      try {
        const bodyText = await readFetchBodyText(input, init)
        const body = bodyText ? JSON.parse(bodyText) : undefined
        if (shouldBlockPromptInputDuringActiveHandoff({ path: { id: sessionID }, body })) {
          activeGuard.handler.mark?.(sessionID, activeGuard.guard)
          return createFetchPromptGuardResponse(sessionID, activeGuard.guard.runIds || [], url.pathname)
        }
      } catch {
        // Malformed or unreadable bodies are passed through unchanged.
      }
    }

    return fetchImpl.call(this, input, init)
  }

  try {
    Object.defineProperty(guardedFetch, injectionGuardSymbol, {
      value: true,
      enumerable: false,
      configurable: false,
    })
  } catch {
    // The function marker is only an idempotency hint.
  }

  try {
    globalThis.fetch = guardedFetch
  } catch {
    return false
  }
  return true
}

function installPromptInjectionGuard(client) {
  const session = client?.session
  registerInjectionGuardHandler()
  if (!session || session[promptGuardSymbol] || promptGuardSessions.has(session)) return false

  let installed = false
  for (const method of ["promptAsync", "prompt"]) {
    const original = session[method]
    if (typeof original !== "function") continue

    try {
      session[method] = async function guardedPrompt(input, ...rest) {
        const sessionID = getSessionIDFromPromptInput(input)
        const activeGuard = getInjectionGuardForSession(sessionID)
        if (activeGuard && shouldBlockPromptInputDuringActiveHandoff(input)) {
          activeGuard.handler.mark?.(sessionID, activeGuard.guard)
          return createPromptGuardResponse(sessionID, activeGuard.guard.runIds || [])
        }
        return original.call(this, input, ...rest)
      }
      installed = true
    } catch {
      // Some future SDK clients may expose read-only methods; tool/transform hooks still guard the session.
    }
  }

  if (installed) {
    promptGuardSessions.add(session)
    try {
      Object.defineProperty(session, promptGuardSymbol, {
        value: true,
        enumerable: false,
        configurable: false,
      })
    } catch {
      try {
        session[promptGuardSymbol] = true
      } catch {
        // The wrapper is already installed; the marker is only an idempotency hint.
      }
    }
  }
  return installed
}

function guardAllowsCancel(guard, runRef) {
  if (!guard?.allowCancel) return false
  const value = String(runRef || "")
  return (guard.runIds || []).some((runId) => value === runId || value.endsWith(`/${runId}`))
}

function getToolName(toolRef) {
  if (typeof toolRef === "string") return toolRef
  if (!toolRef || typeof toolRef !== "object") return ""
  return toolRef.name
    || toolRef.id
    || toolRef.tool
    || toolRef.toolName
    || toolRef.command
    || toolRef.metadata?.name
    || toolRef.metadata?.tool
    || ""
}

function normalizeToolName(toolName) {
  return String(getToolName(toolName) || "").trim().replace(/^mcp_/i, "").toLowerCase()
}

function isCancelTool(toolName) {
  const normalized = normalizeToolName(toolName)
  return normalized === "lmas_cancel" || normalized.endsWith(".lmas_cancel")
}

function isStatusTool(toolName) {
  const normalized = normalizeToolName(toolName)
  return normalized === "lmas_status" || normalized.endsWith(".lmas_status")
}

function isOmoContinuationCommand(command) {
  const normalized = normalizeToolName(command)
  return normalized === "start-work" || omoContinuationHooks.includes(normalized)
}

function argsLookLikeLmasStatus(existingArgs) {
  const command = String(existingArgs?.command || existingArgs?.cmd || existingArgs?.script || "")
  if (!command) return false
  return /\b(lmas|let-my-agent-sleep)\s+status\b/.test(command)
    || /\blmas\.sh\s+status\b/.test(command)
}

function argsLookLikeLmasCommand(existingArgs, subcommand) {
  const command = String(existingArgs?.command || existingArgs?.cmd || existingArgs?.script || "").trim()
  if (!command) return false
  const escaped = subcommand.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  return new RegExp(`^(?:lmas|let-my-agent-sleep|(?:bash\\s+)?(?:\\S*/)?lmas\\.sh)\\s+${escaped}(?:\\s|$)`).test(command)
}

function collectPermissionText(value, chunks = []) {
  if (value === undefined || value === null) return chunks
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    chunks.push(String(value))
    return chunks
  }
  if (Array.isArray(value)) {
    for (const item of value) collectPermissionText(item, chunks)
    return chunks
  }
  if (typeof value === "object") {
    for (const item of Object.values(value)) collectPermissionText(item, chunks)
  }
  return chunks
}

function permissionLooksLikeCancelTool(input) {
  const text = collectPermissionText([
    input?.tool,
    input?.type,
    input?.title,
    input?.pattern,
    input?.metadata,
  ]).join(" ")
  return isCancelTool(text) || /\blmas_cancel\b/i.test(text)
}

function replaceArgsInPlace(output, args) {
  if (output.args && typeof output.args === "object" && !Array.isArray(output.args)) {
    for (const key of Object.keys(output.args)) {
      delete output.args[key]
    }
    Object.assign(output.args, args)
    return
  }
  output.args = args
}

function updateSessionGuardFromChatMessage(input, output) {
  const sessionID = getRuntimeSessionID(input) || getRuntimeSessionID(output?.message)
  const message = {
    info: {
      ...(output?.message || {}),
      ...(sessionID ? { sessionID } : {}),
    },
    parts: Array.isArray(output?.parts) ? output.parts : [],
  }
  updateSessionGuardFromEvent(sessionGuards, eventTextBuffers, {
    type: "message.updated",
    properties: { message },
  })
}

function updateSessionGuardFromToolOutput(input, output) {
  const sessionID = getRuntimeSessionID(input)
  const text = typeof output?.output === "string" ? output.output : ""
  if (!sessionID || text.length === 0) return
  const toolName = normalizeToolName(input?.tool)
  const args = input?.args || input?.arguments || input?.metadata?.args
  const isStart = toolName === "lmas_start" || toolName.endsWith(".lmas_start") || argsLookLikeLmasCommand(args, "start")
  const isStatus = toolName === "lmas_status" || toolName.endsWith(".lmas_status") || argsLookLikeLmasCommand(args, "status")
  const isCancel = toolName === "lmas_cancel" || toolName.endsWith(".lmas_cancel") || argsLookLikeLmasCommand(args, "cancel")

  if (isStart) {
    updateSessionGuardFromText(sessionGuards, sessionID, text, Date.now(), {
      allowHandoff: true,
      allowCompletion: false,
      allowCancel: false,
      omoTurn: text.includes("LMAS_HANDOFF v1") ? true : undefined,
    })
  }
  if (isStatus) updateSessionGuardFromStatusText(sessionGuards, sessionID, text)
  if (isCancel) updateSessionGuardFromCancelText(sessionGuards, sessionID, text)
}

function createStartTool(defaultServerUrl) {
  return tool({
    description:
      "Start a long-running training, evaluation, preprocessing, benchmark, or batch job through Let My Agent Sleep. Returns LMAS_HANDOFF v1 immediately and injects a completion prompt into this OpenCode session when the job finishes.",
    args: {
      command: tool.schema.string().describe("Shell command to run, for example: python train.py --config configs/exp.yaml"),
      cwd: tool.schema.string().optional().describe("Working directory. Defaults to the current session directory."),
      artifacts_dir: tool.schema.string().optional().describe("Artifact directory to report in LMAS events."),
      metadata: tool.schema.record(tool.schema.string(), tool.schema.string()).optional().describe("Additional metadata to persist with this run."),
    },
    async execute(args, context) {
      const sessionID = getRuntimeSessionID(context)
      const guard = getSessionOmoGuard(sessionID)
      if (guard) return createBlockedToolMessage(guard.runIds)

      const cwd = args.cwd || context.directory || context.worktree || process.cwd()
      const script = findLmasScript(cwd, context)
      const serverUrl = process.env.LMAS_OPENCODE_SERVER_URL || defaultServerUrl
      const env = {
        ...process.env,
        LMAS_OPENCODE_SESSION_ID: sessionID,
        LMAS_OPENCODE_SERVER_URL: serverUrl,
      }

      const command = [
        "bash",
        script,
        "start",
        "--adapter",
        "opencode",
        "--cwd",
        cwd,
        "--metadata",
        `requested_command=${args.command}`,
      ]

      if (args.artifacts_dir) {
        command.push("--artifacts-dir", args.artifacts_dir)
      }

      if (args.metadata) {
        for (const [key, value] of Object.entries(args.metadata)) {
          command.push("--metadata", `${key}=${value}`)
        }
      }

      command.push("--", "bash", "-lc", args.command)

      const proc = Bun.spawn(command, {
        cwd,
        env,
        stdin: "ignore",
        stdout: "pipe",
        stderr: "pipe",
        detached: true,
      })
      const stdout = await new Response(proc.stdout).text()
      const stderr = await new Response(proc.stderr).text()
      const code = await proc.exited

      if (code !== 0) {
        throw new Error(`lmas_start failed with exit code ${code}\n${stderr}`)
      }

      const result = stderr.trim().length > 0 ? `${stdout}\n${stderr}` : stdout
      updateSessionGuardFromText(sessionGuards, sessionID, result, Date.now(), {
        allowHandoff: true,
        omoTurn: true,
      })
      return result
    },
  })
}

function createStatusTool() {
  return tool({
    description:
      "Inspect an LMAS run only when the user explicitly asks for status or after an LMAS_COMPLETION_EVENT. If LMAS_STATUS v1 reports RUNNING or FINALIZING, stop immediately; do not poll, tail logs, inspect artifacts, or continue checking until a completion event arrives or the user explicitly asks again.",
    args: {
      run_id: tool.schema.string().describe("LMAS run id, for example lmas_20260701T134510+0900_61653_17555, or a run directory path."),
      runs_dir: tool.schema.string().optional().describe("Run directory root. Defaults to LMAS_RUNS_DIR or .lmas/runs."),
      cwd: tool.schema.string().optional().describe("Working directory. Defaults to the current session directory."),
    },
    async execute(args, context) {
      const sessionID = getRuntimeSessionID(context)
      const activeGuard = getSessionActiveHandoff(sessionID)
      if (activeGuard && !activeGuard.allowStatus) {
        markGuardedPollingAttempt(sessionID, activeGuard)
        return createBlockedToolMessage(activeGuard.runIds)
      }
      const guard = getSessionOmoGuard(sessionID)
      if (guard) return createBlockedToolMessage(guard.runIds)

      const cwd = args.cwd || context.directory || context.worktree || process.cwd()
      const script = findLmasScript(cwd, context)
      const command = ["bash", script, "status"]

      if (args.runs_dir) {
        command.push("--runs-dir", args.runs_dir)
      }

      command.push(args.run_id)

      const proc = Bun.spawn(command, {
        cwd,
        env: { ...process.env },
        stdin: "ignore",
        stdout: "pipe",
        stderr: "pipe",
      })
      const stdout = await new Response(proc.stdout).text()
      const stderr = await new Response(proc.stderr).text()
      const code = await proc.exited

      if (code !== 0) {
        throw new Error(`lmas_status failed with exit code ${code}\n${stderr}`)
      }

      const result = stderr.trim().length > 0 ? `${stdout}\n${stderr}` : stdout
      updateSessionGuardFromStatusText(sessionGuards, sessionID, result)
      return result
    },
  })
}

function createCancelTool(defaultServerUrl) {
  return tool({
    description:
      "Cancel a running Let My Agent Sleep job. If the watcher is still alive, writes a CANCELLED completion event and injects the cancellation completion prompt into this OpenCode session.",
    args: {
      run_id: tool.schema.string().describe("LMAS run id, for example lmas_20260701T134510+0900_61653_17555, or a run directory path."),
      runs_dir: tool.schema.string().optional().describe("Run directory root. Defaults to LMAS_RUNS_DIR or .lmas/runs."),
      cwd: tool.schema.string().optional().describe("Working directory. Defaults to the current session directory."),
      reason: tool.schema.string().optional().describe("Cancellation reason to persist in metadata."),
    },
    async execute(args, context) {
      const sessionID = getRuntimeSessionID(context)
      const guard = getSessionActiveHandoff(sessionID)
      if (guard && !guardAllowsCancel(guard, args.run_id)) return createBlockedToolMessage(guard.runIds)

      const cwd = args.cwd || context.directory || context.worktree || process.cwd()
      const script = findLmasScript(cwd, context)
      const serverUrl = process.env.LMAS_OPENCODE_SERVER_URL || defaultServerUrl
      const env = {
        ...process.env,
        LMAS_OPENCODE_SESSION_ID: sessionID,
        LMAS_OPENCODE_SERVER_URL: serverUrl,
      }
      const command = ["bash", script, "cancel"]

      if (args.runs_dir) {
        command.push("--runs-dir", args.runs_dir)
      }

      if (args.reason) {
        command.push("--reason", args.reason)
      }

      command.push(args.run_id)

      const proc = Bun.spawn(command, {
        cwd,
        env,
        stdin: "ignore",
        stdout: "pipe",
        stderr: "pipe",
      })
      const stdout = await new Response(proc.stdout).text()
      const stderr = await new Response(proc.stderr).text()
      const code = await proc.exited

      if (code !== 0) {
        throw new Error(`lmas_cancel failed with exit code ${code}\n${stderr}`)
      }

      const result = stderr.trim().length > 0 ? `${stdout}\n${stderr}` : stdout
      updateSessionGuardFromCancelText(sessionGuards, sessionID, result)
      return result
    },
  })
}

function createInfoTool(defaultServerUrl) {
  return tool({
    description:
      "Return Let My Agent Sleep OpenCode plugin diagnostic information. Use for install/debug checks, not for polling active runs.",
    args: {},
    async execute(_args, context) {
      const sessionID = getRuntimeSessionID(context)
      const cwd = context.directory || context.worktree || process.cwd()
      const state = describeSessionState({ sessionGuards, sessionID, cwd })
      const guard = state.guard
      const runLines = state.runs.length > 0
        ? state.runs.flatMap((run, index) => [
          `current_session_run_${index + 1}: ${run.runId}`,
          `current_session_run_${index + 1}_status: ${run.status}`,
          `current_session_run_${index + 1}_elapsed_seconds: ${run.elapsedSeconds || ""}`,
          `current_session_run_${index + 1}_command: ${run.commandSummary || ""}`,
          `current_session_run_${index + 1}_run_dir: ${run.runDir}`,
        ])
        : ["current_session_runs: none"]
      return [
        "LMAS_INFO v1",
        `name: ${packageJson.name}`,
        `version: ${packageJson.version}`,
        "adapter: opencode",
        `server_url: ${process.env.LMAS_OPENCODE_SERVER_URL || defaultServerUrl}`,
        `session_id: ${sessionID || ""}`,
        `guarded_sessions: ${sessionGuards.size}`,
        `current_session_guard_available: ${guard.available === true ? "true" : "false"}`,
        `current_session_guard_active: ${guard.active === true ? "true" : "false"}`,
        `current_session_guard_omo_turn: ${guard.omoTurn === true ? "true" : "false"}`,
        `current_session_guard_allow_status: ${guard.allowStatus === true ? "true" : "false"}`,
        `current_session_guard_allow_cancel: ${guard.allowCancel === true ? "true" : "false"}`,
        `current_session_guard_run_ids: ${(guard.runIds || []).join(",")}`,
        `current_session_guard_updated_at: ${guard.updatedAt ? new Date(guard.updatedAt).toISOString() : ""}`,
        ...runLines,
      ].join("\n")
    },
  })
}

export const LetMyAgentSleepPlugin = async (input = {}) => {
  const { serverUrl } = input
  const defaultServerUrl = serverUrl?.toString?.().replace(/\/$/, "") || "http://127.0.0.1:4096"
  const ensureFetchGuard = () => installFetchPromptInjectionGuard(defaultServerUrl)
  installPromptInjectionGuard(input.client)
  ensureFetchGuard()

  return {
    event: ({ event }) => {
      ensureFetchGuard()
      if (event?.type === "session.deleted") {
        updateSessionGuardFromEvent(sessionGuards, eventTextBuffers, event)
        return
      }
      if (
        event?.type !== "message.part.delta"
        && event?.type !== "message.part.updated"
        && event?.type !== "message.updated"
      ) return
      updateSessionGuardFromEvent(sessionGuards, eventTextBuffers, event)
    },
    "chat.message": async (input, output) => {
      ensureFetchGuard()
      updateSessionGuardFromChatMessage(input, output)
    },
    "experimental.chat.messages.transform": (input, output) => {
      ensureFetchGuard()
      applyOmoContinuationGuard(output, getRuntimeSessionID(input))
    },
    "experimental.chat.system.transform": async (input, output) => {
      ensureFetchGuard()
      const guard = getSessionActiveHandoff(getRuntimeSessionID(input))
      if (!guard) return
      if (!Array.isArray(output.system)) output.system = []
      output.system.push("LMAS handoff guard is active for this live turn only. Do not poll active LMAS runs unless the user explicitly asks.")
    },
    "tool.execute.before": async (input, output) => {
      ensureFetchGuard()
      const sessionID = getRuntimeSessionID(input)
      const activeGuard = getSessionActiveHandoff(sessionID)
      if (activeGuard && !activeGuard.allowStatus && (isStatusTool(input.tool) || argsLookLikeLmasStatus(output.args))) {
        markGuardedPollingAttempt(sessionID, activeGuard)
        const action = createGuardedToolAction(input.tool, output.args, activeGuard.runIds)
        if (action.type === "args") {
          replaceArgsInPlace(output, action.args)
          return
        }
        throw new Error(action.message)
      }
      if (activeGuard && isCancelTool(input.tool)) {
        if (guardAllowsCancel(activeGuard, output.args?.run_id)) return
        throw new Error(createBlockedToolMessage(activeGuard.runIds))
      }
      const guard = getSessionOmoGuard(sessionID)
      if (!guard) return

      const action = createGuardedToolAction(input.tool, output.args, guard.runIds)
      if (action.type === "args") {
        replaceArgsInPlace(output, action.args)
        return
      }
      throw new Error(action.message)
    },
    "tool.execute.after": async (input, output) => {
      ensureFetchGuard()
      updateSessionGuardFromToolOutput(input, output)
    },
    "shell.env": async (input, output) => {
      ensureFetchGuard()
      const sessionID = getRuntimeSessionID(input)
      if (!sessionID) return
      if (!output.env || typeof output.env !== "object" || Array.isArray(output.env)) output.env = {}
      output.env.LMAS_OPENCODE_SESSION_ID = sessionID
      if (!output.env.LMAS_OPENCODE_SERVER_URL) {
        output.env.LMAS_OPENCODE_SERVER_URL = process.env.LMAS_OPENCODE_SERVER_URL || defaultServerUrl
      }
    },
    "command.execute.before": async (input, output) => {
      ensureFetchGuard()
      const sessionID = getRuntimeSessionID(input)
      let guard = getSessionOmoGuard(sessionID)
      if (!guard) {
        const activeGuard = getSessionActiveHandoff(sessionID)
        const internalCommand = isReplyExpectingInternalPromptInput({
          body: { parts: output.parts || [] },
        })
        if (!activeGuard || (!internalCommand && !isOmoContinuationCommand(input.command))) return
        guard = activeGuard
      }
      output.parts = [createCommandGuardPart(sessionID, guard.runIds)]
    },
    "permission.ask": async (input, output) => {
      ensureFetchGuard()
      const sessionID = getRuntimeSessionID(input)
      const guard = getSessionOmoGuard(sessionID)
      if (!guard) return
      if (guard.allowCancel && permissionLooksLikeCancelTool(input)) return

      output.status = "deny"
    },
    tool: {
      lmas_start: createStartTool(defaultServerUrl),
      lmas_status: createStatusTool(),
      lmas_cancel: createCancelTool(defaultServerUrl),
      lmas_info: createInfoTool(defaultServerUrl),
    },
  }
}

export const server = LetMyAgentSleepPlugin
export default { server }
