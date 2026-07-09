import { existsSync } from "node:fs"
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

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const sessionGuards = new Map()
const eventTextBuffers = new Map()
const allowedCancelCallIds = new Set()
const promptGuardSymbol = Symbol.for("let-my-agent-sleep.opencode.prompt-guard")
const promptGuardSessions = new WeakSet()
const injectionGuardSymbol = Symbol.for("let-my-agent-sleep.opencode.injection-guard")
const injectionGuardRegistrySymbol = Symbol.for("let-my-agent-sleep.opencode.injection-guard.registry")

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
}

export function applyOmoContinuationGuard(output, sessionID) {
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
  if (existing?.origins instanceof Set && existing?.handlers instanceof Set) {
    return existing
  }

  const registry = {
    origins: new Set(),
    handlers: new Set(),
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
  for (const handler of registry.handlers) {
    const guard = handler.get?.(sessionID)
    if (guard) return { handler, guard }
  }
  return undefined
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

export function installFetchPromptInjectionGuard(serverUrl) {
  rememberFetchGuardOrigin(serverUrl)
  getInjectionGuardRegistry().handlers.add(injectionGuardHandler)
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

export function installPromptInjectionGuard(client) {
  const session = client?.session
  getInjectionGuardRegistry().handlers.add(injectionGuardHandler)
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

function normalizeToolName(toolName) {
  return String(toolName || "").trim().replace(/^mcp_/i, "").toLowerCase()
}

function isCancelTool(toolName) {
  const normalized = normalizeToolName(toolName)
  return normalized === "lmas_cancel" || normalized.endsWith(".lmas_cancel")
}

function isOmoContinuationCommand(command) {
  const normalized = normalizeToolName(command)
  return normalized === "start-work"
    || normalized === "ralph-loop"
    || normalized === "ulw-loop"
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

function callKey(sessionID, callID) {
  if (!sessionID || !callID) return undefined
  return `${sessionID}:${callID}`
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

export function findLmasScript(cwd, context) {
  const roots = [
    process.env.LMAS_ROOT,
    packageRoot,
    context.directory,
    context.worktree,
    cwd,
  ].filter((value) => value && value !== "/")

  for (const root of roots) {
    const candidate = join(root, "bin", "lmas.sh")
    if (existsSync(candidate)) return candidate
  }

  throw new Error(`could not locate bin/lmas.sh; checked roots: ${roots.join(", ")}`)
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
      server_url: tool.schema.string().optional().describe("OpenCode server URL. Defaults to this plugin's current OpenCode server URL."),
      notify_url: tool.schema.string().optional().describe("Optional URL that receives the completion resume prompt as a secondary notification."),
    },
    async execute(args, context) {
      const guard = getSessionOmoGuard(context.sessionID)
      if (guard) return createBlockedToolMessage(guard.runIds)

      const cwd = args.cwd || context.directory || context.worktree || process.cwd()
      const script = findLmasScript(cwd, context)
      const serverUrl = args.server_url || process.env.LMAS_OPENCODE_SERVER_URL || defaultServerUrl
      const env = {
        ...process.env,
        LMAS_OPENCODE_SESSION_ID: context.sessionID,
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

      if (args.notify_url) {
        command.push("--notify", args.notify_url)
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
      updateSessionGuardFromText(sessionGuards, context.sessionID, result, Date.now(), {
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
      "Inspect an LMAS run only when the user explicitly asks for status or after an LMAS_COMPLETION_EVENT. If LMAS_STATUS v1 reports RUNNING, stop immediately; do not poll, tail logs, inspect artifacts, or continue checking until a completion event arrives or the user explicitly asks again.",
    args: {
      run_id: tool.schema.string().describe("LMAS run id, for example lmas_20260701T134510+0900_61653_17555, or a run directory path."),
      runs_dir: tool.schema.string().optional().describe("Run directory root. Defaults to LMAS_RUNS_DIR or .lmas/runs."),
      cwd: tool.schema.string().optional().describe("Working directory. Defaults to the current session directory."),
    },
    async execute(args, context) {
      const guard = getSessionOmoGuard(context.sessionID)
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
      updateSessionGuardFromStatusText(sessionGuards, context.sessionID, result)
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
      server_url: tool.schema.string().optional().describe("OpenCode server URL. Defaults to this plugin's current OpenCode server URL."),
    },
    async execute(args, context) {
      const guard = getSessionOmoGuard(context.sessionID)
      if (guard && !guardAllowsCancel(guard, args.run_id)) return createBlockedToolMessage(guard.runIds)

      const cwd = args.cwd || context.directory || context.worktree || process.cwd()
      const script = findLmasScript(cwd, context)
      const serverUrl = args.server_url || process.env.LMAS_OPENCODE_SERVER_URL || defaultServerUrl
      const env = {
        ...process.env,
        LMAS_OPENCODE_SESSION_ID: context.sessionID,
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
      updateSessionGuardFromCancelText(sessionGuards, context.sessionID, result)
      return result
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
    "experimental.chat.messages.transform": (input, output) => {
      ensureFetchGuard()
      applyOmoContinuationGuard(output, input?.sessionID)
    },
    "tool.execute.before": async (input, output) => {
      ensureFetchGuard()
      const guard = getSessionOmoGuard(input.sessionID)
      if (!guard) return
      if (isCancelTool(input.tool) && guardAllowsCancel(guard, output.args?.run_id)) {
        const key = callKey(input.sessionID, input.callID)
        if (key) allowedCancelCallIds.add(key)
        return
      }

      const action = createGuardedToolAction(input.tool, output.args, guard.runIds)
      if (action.type === "args") {
        replaceArgsInPlace(output, action.args)
        return
      }
      throw new Error(action.message)
    },
    "command.execute.before": async (input, output) => {
      ensureFetchGuard()
      let guard = getSessionOmoGuard(input.sessionID)
      if (!guard) {
        const activeGuard = getSessionActiveHandoff(input.sessionID)
        const internalCommand = isReplyExpectingInternalPromptInput({
          body: { parts: output.parts || [] },
        })
        if (!activeGuard || (!internalCommand && !isOmoContinuationCommand(input.command))) return
        guard = activeGuard
      }
      output.parts = [createCommandGuardPart(input.sessionID, guard.runIds)]
    },
    "permission.ask": async (input, output) => {
      ensureFetchGuard()
      const guard = getSessionOmoGuard(input.sessionID)
      if (!guard) return
      const key = callKey(input.sessionID, input.callID || input.tool?.callID)
      if (key && allowedCancelCallIds.has(key)) {
        allowedCancelCallIds.delete(key)
        output.status = "allow"
        return
      }
      if (guard.allowCancel && permissionLooksLikeCancelTool(input)) {
        output.status = "allow"
        return
      }

      output.status = "deny"
    },
    tool: {
      lmas_start: createStartTool(defaultServerUrl),
      lmas_status: createStatusTool(),
      lmas_cancel: createCancelTool(defaultServerUrl),
    },
  }
}

export default LetMyAgentSleepPlugin
