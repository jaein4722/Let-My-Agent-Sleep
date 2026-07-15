#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-plugin-guard.XXXXXX")
export TMPDIR_ROOT
STUB_DIR="$ROOT/packages/let-my-agent-sleep/node_modules/@opencode-ai/plugin"
STUB_CREATED=0

cd "$ROOT" || exit 1

cleanup() {
  if [ "$STUB_CREATED" -eq 1 ]; then
    rm -rf "$STUB_DIR"
    rmdir "$ROOT/packages/let-my-agent-sleep/node_modules/@opencode-ai" 2>/dev/null || true
    rmdir "$ROOT/packages/let-my-agent-sleep/node_modules" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

if [ ! -d "$STUB_DIR" ]; then
  STUB_CREATED=1
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/package.json" <<'JSON'
{
  "name": "@opencode-ai/plugin",
  "type": "module",
  "exports": {
    ".": "./index.js"
  }
}
JSON
  cat > "$STUB_DIR/index.js" <<'JS'
export function tool(definition) {
  return definition
}

function schema(kind) {
  return {
    optional() { return this },
    describe() { return this },
    safeParse(value) {
      if (kind === "string") {
        return { success: typeof value === "string" }
      }
      return { success: true }
    },
    parse(value) {
      const result = this.safeParse(value)
      if (!result.success) {
        throw new Error(`invalid ${kind}`)
      }
      return value
    },
  }
}

tool.schema = {
  string() {
    return schema("string")
  },
  record() {
    return schema("record")
  },
}
JS
fi

node --input-type=module - <<'JS'
import { chmodSync, mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { createOpencodeClient } from "@opencode-ai/sdk"
import { LetMyAgentSleepPlugin } from "./packages/let-my-agent-sleep/src/index.js"
import { findLmasScript } from "./packages/let-my-agent-sleep/src/find-lmas-script.js"
import { omoContinuationHooks } from "./packages/let-my-agent-sleep/src/omo-constants.js"

function message(role, text, id, sessionID = "plugin_guard_session") {
  return {
    info: {
      id,
      sessionID,
      role,
      time: { created: Date.now() },
      ...(role === "user" ? { agent: "test", model: { providerID: "test", modelID: "test" } } : {}),
    },
    parts: [{
      id: `${id}_part`,
      sessionID,
      messageID: id,
      type: "text",
      text,
    }],
  }
}

let fetchCalls = 0
let lastFetchBodyText = ""
globalThis.fetch = async (input, init) => {
  fetchCalls += 1
  if (typeof init?.body === "string") {
    lastFetchBodyText = init.body
  } else if (init?.body && typeof init.body.text === "function") {
    lastFetchBodyText = await init.body.text()
  } else if (input && typeof input === "object" && typeof input.clone === "function") {
    lastFetchBodyText = await input.clone().text()
  } else {
    lastFetchBodyText = ""
  }
  return new Response(JSON.stringify({ ok: true, input: String(input), method: init?.method || "GET" }), {
    status: 200,
    headers: { "content-type": "application/json" },
  })
}

async function expectGuardedFetchResponse(response, label) {
  if (response.status === 204) {
    if (response.headers.get("x-lmas-guard") !== "active") {
      throw new Error(`expected ${label} to return an LMAS guard header`)
    }
    return { info: { lmas_guard: true } }
  }
  const body = await response.json()
  if (response.status !== 200 || response.headers.get("x-lmas-guard") !== "active" || body?.info?.lmas_guard !== true) {
    throw new Error(`expected ${label} to return an LMAS guard response`)
  }
  return body
}

const plugin = await LetMyAgentSleepPlugin({ serverUrl: new URL("http://127.0.0.1:4096") })
const sessionID = "plugin_guard_session"
const fakeWorkspace = process.env.TMPDIR_ROOT
const fakeWorkspaceScript = join(fakeWorkspace, "bin", "lmas.sh")

mkdirSync(join(fakeWorkspace, "bin"), { recursive: true })
writeFileSync(fakeWorkspaceScript, "#!/usr/bin/env sh\nexit 77\n")
chmodSync(fakeWorkspaceScript, 0o755)

const resolvedScript = findLmasScript(fakeWorkspace, { directory: fakeWorkspace, worktree: fakeWorkspace })
if (resolvedScript === fakeWorkspaceScript || !resolvedScript.endsWith("packages/let-my-agent-sleep/bin/lmas.sh")) {
  throw new Error(`expected packaged lmas.sh to win over workspace bin/lmas.sh, got ${resolvedScript}`)
}

process.env.LMAS_ROOT = fakeWorkspace
const overrideScript = findLmasScript("/does/not/matter", { directory: "/does/not/matter", worktree: "/does/not/matter" })
delete process.env.LMAS_ROOT
if (overrideScript !== fakeWorkspaceScript) {
  throw new Error(`expected LMAS_ROOT to override packaged lmas.sh, got ${overrideScript}`)
}

const promptGuardSessionID = "plugin_prompt_guard_session"
let promptAsyncCalls = 0
let promptCalls = 0
const guardedClient = {
  session: {
    async promptAsync(input) {
      promptAsyncCalls += 1
      return { data: { id: "real_prompt_async", input } }
    },
    async prompt(input) {
      promptCalls += 1
      return { data: { id: "real_prompt", input } }
    },
  },
}
const promptGuardPlugin = await LetMyAgentSleepPlugin({
  serverUrl: new URL("http://127.0.0.1:4096"),
  client: guardedClient,
})
const firstGuardedPromptAsync = guardedClient.session.promptAsync
const firstGuardedPrompt = guardedClient.session.prompt
await LetMyAgentSleepPlugin({
  serverUrl: new URL("http://127.0.0.1:4096"),
  client: guardedClient,
})
if (guardedClient.session.promptAsync !== firstGuardedPromptAsync || guardedClient.session.prompt !== firstGuardedPrompt) {
  throw new Error("expected prompt injection guard installation to be idempotent for the same client session object")
}
await promptGuardPlugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: promptGuardSessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_prompt_guard\nstatus: STARTED",
    },
  },
})
const blockedPromptAsync = await guardedClient.session.promptAsync({
  path: { id: promptGuardSessionID },
  body: {
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  },
})
if (promptAsyncCalls !== 0 || blockedPromptAsync?.data?.lmas_guard !== true) {
  throw new Error("expected active LMAS handoff to no-op reply-expecting internal promptAsync before injection")
}
const blockedPromptAsyncSessionIDPath = await guardedClient.session.promptAsync({
  path: { sessionID: promptGuardSessionID },
  body: {
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  },
})
if (promptAsyncCalls !== 0 || blockedPromptAsyncSessionIDPath?.data?.lmas_guard !== true) {
  throw new Error("expected path.sessionID promptAsync input to be no-oped by prompt injection guard")
}
const blockedPrompt = await guardedClient.session.prompt({
  path: promptGuardSessionID,
  body: {
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  },
})
if (promptCalls !== 0 || blockedPrompt?.data?.lmas_guard !== true) {
  throw new Error("expected active LMAS handoff to no-op reply-expecting internal prompt before injection")
}
await guardedClient.session.promptAsync({
  path: { id: promptGuardSessionID },
  body: {
    noReply: true,
    parts: [{ type: "text", text: "notification\n<!-- OMO_INTERNAL_INITIATOR -->\n<!-- OMO_INTERNAL_NOREPLY -->" }],
  },
})
if (promptAsyncCalls !== 1) {
  throw new Error("expected no-reply internal promptAsync to pass through prompt injection guard")
}
await guardedClient.session.promptAsync({
  path: { id: promptGuardSessionID },
  body: {
    agent: "sisyphus",
    model: { providerID: "test", modelID: "test" },
    parts: [{ type: "text", text: "background wake notification\n<!-- OMO_INTERNAL_INITIATOR -->\n<!-- OMO_INTERNAL_NOREPLY -->" }],
  },
})
if (promptAsyncCalls !== 2) {
  throw new Error("expected no-reply marker promptAsync to pass through prompt injection guard even without a noReply flag")
}
const blockedModelFallbackShapePromptAsync = await guardedClient.session.promptAsync({
  path: { id: promptGuardSessionID },
  body: {
    agent: "sisyphus",
    model: { providerID: "test", modelID: "fallback" },
    parts: [{ type: "text", text: "continue" }],
  },
})
if (promptAsyncCalls !== 2 || blockedModelFallbackShapePromptAsync?.data?.lmas_guard !== true) {
  throw new Error("expected active LMAS handoff to no-op OMO model-fallback shaped promptAsync")
}
const blockedRuntimeFallbackShapePromptAsync = await guardedClient.session.promptAsync({
  path: { id: promptGuardSessionID },
  body: {
    messageID: "retry_message",
    system: "retry with another model",
    tools: { bash: true },
    parts: [{ type: "text", text: "Retry the previous user request." }],
  },
})
if (promptAsyncCalls !== 2 || blockedRuntimeFallbackShapePromptAsync?.data?.lmas_guard !== true) {
  throw new Error("expected active LMAS handoff to no-op OMO runtime-fallback shaped promptAsync")
}
const blockedMarkerlessPromptAsync = await guardedClient.session.promptAsync({
  path: { id: promptGuardSessionID },
  body: {
    parts: [{ type: "text", text: "ordinary user prompt" }],
  },
})
if (promptAsyncCalls !== 2 || blockedMarkerlessPromptAsync?.data?.lmas_guard !== true) {
  throw new Error("expected active LMAS handoff to no-op markerless reply-expecting promptAsync before injection")
}
await guardedClient.session.promptAsync({
  path: { id: promptGuardSessionID },
  body: {
    parts: [{
      type: "text",
      text: "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_prompt_guard\nstatus: SUCCEEDED",
    }],
  },
})
if (promptAsyncCalls !== 3) {
  throw new Error("expected plain LMAS completion promptAsync to pass through prompt injection guard")
}
const blockedBodyShapedPrompt = await guardedClient.session.promptAsync({
  sessionID: promptGuardSessionID,
  parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
})
if (promptAsyncCalls !== 3 || blockedBodyShapedPrompt?.data?.lmas_guard !== true) {
  throw new Error("expected body-shaped internal prompt input to be no-oped by prompt injection guard")
}
const reusedPromptGuardModule = await import(`./packages/let-my-agent-sleep/src/index.js?reused-prompt-guard=${Date.now()}`)
const reusedPromptGuardPlugin = await reusedPromptGuardModule.LetMyAgentSleepPlugin({
  serverUrl: new URL("http://127.0.0.1:4096"),
  client: guardedClient,
})
if (guardedClient.session.promptAsync !== firstGuardedPromptAsync || guardedClient.session.prompt !== firstGuardedPrompt) {
  throw new Error("expected reloaded plugin module not to double-wrap prompt methods")
}
const reusedPromptGuardSessionID = "plugin_reused_prompt_guard_session"
await reusedPromptGuardPlugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: reusedPromptGuardSessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_reused_prompt_guard\nstatus: STARTED",
    },
  },
})
const blockedThroughExistingPromptWrapper = await guardedClient.session.promptAsync({
  path: { id: reusedPromptGuardSessionID },
  body: {
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  },
})
if (promptAsyncCalls !== 3 || blockedThroughExistingPromptWrapper?.data?.lmas_guard !== true) {
  throw new Error("expected a reloaded plugin module to share an already-installed LMAS prompt guard")
}
await promptGuardPlugin.event({
  event: {
    type: "session.deleted",
    properties: { sessionID: reusedPromptGuardSessionID },
  },
})
await reusedPromptGuardPlugin["tool.execute.before"](
  { tool: "todowrite", sessionID: reusedPromptGuardSessionID, callID: "call_after_cross_reload_delete" },
  { args: { todos: [] } },
)
const blockedLiveRoutePrompt = await fetch(`http://127.0.0.1:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
await expectGuardedFetchResponse(blockedLiveRoutePrompt, "live-route prompt_async internal prompt")
if (blockedLiveRoutePrompt.status !== 204) {
  throw new Error("expected live-route prompt_async guard to preserve OpenCode SDK 204 response contract")
}
if (fetchCalls !== 0) {
  throw new Error("expected live-route prompt_async internal prompt to be no-oped before fetch")
}
const blockedLiveRouteSyncPrompt = await fetch(`http://127.0.0.1:4096/session/${promptGuardSessionID}/message`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
await expectGuardedFetchResponse(blockedLiveRouteSyncPrompt, "live-route sync internal prompt")
if (blockedLiveRouteSyncPrompt.status !== 200) {
  throw new Error("expected live-route sync message guard to preserve OpenCode SDK 200 response contract")
}
if (fetchCalls !== 0) {
  throw new Error("expected live-route sync prompt internal prompt to be no-oped before fetch")
}
const blockedLiveRouteMarkerlessPrompt = await fetch(`http://127.0.0.1:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "ordinary retry prompt without internal marker" }],
  }),
})
await expectGuardedFetchResponse(blockedLiveRouteMarkerlessPrompt, "live-route markerless reply-expecting prompt")
if (fetchCalls !== 0) {
  throw new Error("expected live-route markerless reply-expecting prompt to be no-oped before fetch")
}
const blockedLiveRouteModelFallbackPrompt = await fetch(`http://127.0.0.1:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    agent: "sisyphus",
    model: { providerID: "test", modelID: "fallback" },
    parts: [{ type: "text", text: "continue" }],
  }),
})
await expectGuardedFetchResponse(blockedLiveRouteModelFallbackPrompt, "live-route OMO model-fallback shaped prompt")
if (fetchCalls !== 0) {
  throw new Error("expected live-route OMO model-fallback shaped prompt to be no-oped before fetch")
}
const blockedLiveRouteRuntimeFallbackPrompt = await fetch(`http://127.0.0.1:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    messageID: "retry_message",
    system: "retry with another model",
    tools: { bash: true },
    parts: [{ type: "text", text: "Retry the previous user request." }],
  }),
})
await expectGuardedFetchResponse(blockedLiveRouteRuntimeFallbackPrompt, "live-route OMO runtime-fallback shaped prompt")
if (fetchCalls !== 0) {
  throw new Error("expected live-route OMO runtime-fallback shaped prompt to be no-oped before fetch")
}
for (const hookName of ["experimental.compaction.autocontinue", "experimental.session.compacting"]) {
  if (hookName in promptGuardPlugin) {
    throw new Error(`LMAS guard must not install compaction hook: ${hookName}`)
  }
}
const systemTransformOutput = { system: [] }
await promptGuardPlugin["experimental.chat.system.transform"](
  { sessionID: promptGuardSessionID, model: {} },
  systemTransformOutput,
)
if (
  systemTransformOutput.system.length !== 1
  || !systemTransformOutput.system[0].includes("live turn only")
) {
  throw new Error("expected active LMAS handoff to add live-turn-only system context")
}
const blockedLiveRouteRequestObject = await fetch(new Request(`http://127.0.0.1:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
}))
await expectGuardedFetchResponse(blockedLiveRouteRequestObject, "live-route Request-object prompt_async internal prompt")
if (fetchCalls !== 0) {
  throw new Error("expected live-route Request-object prompt_async internal prompt to be no-oped before fetch")
}
const blockedLiveRouteLoopbackAlias = await fetch(`http://localhost:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
await expectGuardedFetchResponse(blockedLiveRouteLoopbackAlias, "live-route loopback alias prompt_async internal prompt")
if (fetchCalls !== 0) {
  throw new Error("expected live-route loopback alias prompt_async internal prompt to be no-oped before fetch")
}
const blockedLiveRouteRelativeUrl = await fetch(`/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
await expectGuardedFetchResponse(blockedLiveRouteRelativeUrl, "live-route relative URL prompt_async internal prompt")
if (fetchCalls !== 0) {
  throw new Error("expected live-route relative URL prompt_async internal prompt to be no-oped before fetch")
}
const sdkClient = createOpencodeClient({
  baseUrl: "http://127.0.0.1:4096",
})
const sdkPromptAsyncResult = await sdkClient.session.promptAsync({
  path: { id: promptGuardSessionID },
  body: {
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  },
})
if (sdkPromptAsyncResult?.response?.status !== 204 || sdkPromptAsyncResult?.data === undefined || fetchCalls !== 0) {
  throw new Error("expected OpenCode SDK client to accept guarded prompt_async as a 204 no-op response")
}
const wildcardServerSessionID = "plugin_wildcard_server_session"
const wildcardServerPlugin = await LetMyAgentSleepPlugin({ serverUrl: new URL("http://0.0.0.0:45137") })
await wildcardServerPlugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: wildcardServerSessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_wildcard_server_guard\nstatus: STARTED",
    },
  },
})
const blockedWildcardAlias = await fetch(`http://127.0.0.1:45137/session/${wildcardServerSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
await expectGuardedFetchResponse(blockedWildcardAlias, "wildcard OpenCode server origin loopback alias prompt_async")
if (fetchCalls !== 0) {
  throw new Error("expected wildcard OpenCode server origin to guard loopback alias prompt_async before fetch")
}
let delegatingFetchWrapperCalls = 0
const lmasGuardedFetch = globalThis.fetch
globalThis.fetch = async function laterDelegatingFetchWrapper(input, init) {
  delegatingFetchWrapperCalls += 1
  return lmasGuardedFetch(input, init)
}
const blockedAfterDelegatingWrapper = await fetch(`http://127.0.0.1:45137/session/${wildcardServerSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
if (
  delegatingFetchWrapperCalls !== 1
  || fetchCalls !== 0
) {
  throw new Error("expected LMAS fetch guard to remain effective through later delegating fetch wrappers")
}
await expectGuardedFetchResponse(blockedAfterDelegatingWrapper, "delegating wrapper prompt_async internal prompt")
globalThis.fetch = lmasGuardedFetch
const reusedGuardModule = await import(`./packages/let-my-agent-sleep/src/index.js?reused-guard=${Date.now()}`)
const reusedGuardPlugin = await reusedGuardModule.LetMyAgentSleepPlugin({
  serverUrl: new URL("http://127.0.0.1:45199"),
})
const reusedGuardSessionID = "plugin_reused_fetch_guard_session"
await reusedGuardPlugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: reusedGuardSessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_reused_fetch_guard\nstatus: STARTED",
    },
  },
})
const blockedThroughExistingMarkedGuard = await fetch(`http://127.0.0.1:45199/session/${reusedGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
if (
  fetchCalls !== 0
) {
  throw new Error("expected a reloaded plugin module to share an already-installed LMAS fetch guard")
}
await expectGuardedFetchResponse(blockedThroughExistingMarkedGuard, "reloaded plugin module prompt_async internal prompt")
let preexistingFetchWrapperCalls = 0
globalThis.fetch = async function preexistingDelegatingFetchWrapper(input, init) {
  preexistingFetchWrapperCalls += 1
  return lmasGuardedFetch(input, init)
}
const preexistingWrapperModule = await import(`./packages/let-my-agent-sleep/src/index.js?preexisting-wrapper=${Date.now()}`)
const preexistingWrapperPlugin = await preexistingWrapperModule.LetMyAgentSleepPlugin({
  serverUrl: new URL("http://127.0.0.1:45222"),
})
const preexistingWrapperSessionID = "plugin_preexisting_fetch_wrapper_session"
await preexistingWrapperPlugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: preexistingWrapperSessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_preexisting_fetch_wrapper\nstatus: STARTED",
    },
  },
})
const blockedThroughPreexistingWrapper = await fetch(`http://127.0.0.1:45222/session/${preexistingWrapperSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
if (
  preexistingFetchWrapperCalls !== 0
  || fetchCalls !== 0
) {
  throw new Error("expected LMAS fetch guard to block before a preexisting delegating fetch wrapper")
}
await expectGuardedFetchResponse(blockedThroughPreexistingWrapper, "preexisting delegating wrapper prompt_async internal prompt")
globalThis.fetch = lmasGuardedFetch
let replacementFetchCalls = 0
globalThis.fetch = async function replacementFetchWithoutDelegation() {
  replacementFetchCalls += 1
  return new Response(JSON.stringify({ replaced: true }), { status: 418 })
}
const replacementFetchSessionID = "plugin_replacement_fetch_session"
await promptGuardPlugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: replacementFetchSessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_replacement_fetch\nstatus: STARTED",
    },
  },
})
const blockedAfterFetchReplacement = await fetch(`http://127.0.0.1:4096/session/${replacementFetchSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
if (
  replacementFetchCalls !== 0
) {
  throw new Error("expected LMAS event hook to reinstall fetch guard after global fetch replacement")
}
await expectGuardedFetchResponse(blockedAfterFetchReplacement, "fetch replacement prompt_async internal prompt")
globalThis.fetch = lmasGuardedFetch
await fetch(`https://example.com/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->" }],
  }),
})
if (fetchCalls !== 1) {
  throw new Error("expected fetch guard to ignore matching paths on non-OpenCode origins")
}
await fetch(`http://127.0.0.1:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    noReply: true,
    parts: [{ type: "text", text: "notification\n<!-- OMO_INTERNAL_INITIATOR -->\n<!-- OMO_INTERNAL_NOREPLY -->" }],
  }),
})
if (fetchCalls !== 2) {
  throw new Error("expected live-route no-reply internal prompt to pass through fetch guard")
}
const requestObjectNoReplyBody = JSON.stringify({
  noReply: true,
  parts: [{ type: "text", text: "request object notification\n<!-- OMO_INTERNAL_INITIATOR -->\n<!-- OMO_INTERNAL_NOREPLY -->" }],
})
await fetch(new Request(`http://127.0.0.1:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: requestObjectNoReplyBody,
}))
if (fetchCalls !== 3 || lastFetchBodyText !== requestObjectNoReplyBody) {
  throw new Error("expected live-route Request-object no-reply prompt to pass through fetch guard with body intact")
}
await fetch(`http://127.0.0.1:4096/session/${promptGuardSessionID}/prompt_async`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    parts: [{ type: "text", text: "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_prompt_guard\nstatus: SUCCEEDED" }],
  }),
})
if (fetchCalls !== 4) {
  throw new Error("expected live-route LMAS completion prompt to pass through fetch guard")
}
await promptGuardPlugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: promptGuardSessionID,
      delta: "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_prompt_guard\nstatus: SUCCEEDED",
    },
  },
})
const systemTransformAfterCompletionOutput = { system: [] }
await promptGuardPlugin["experimental.chat.system.transform"](
  { sessionID: promptGuardSessionID, model: {} },
  systemTransformAfterCompletionOutput,
)
if (systemTransformAfterCompletionOutput.system.length !== 0) {
  throw new Error("did not expect OpenCode system context to be modified after LMAS completion")
}

const originalBun = globalThis.Bun
let spawnedCommand
function restoreBun() {
  if (originalBun === undefined) {
    delete globalThis.Bun
  } else {
    globalThis.Bun = originalBun
  }
}

globalThis.Bun = {
  spawn(command) {
    spawnedCommand = command
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_HANDOFF v1\nrun_id: lmas_immediate_guard\nstatus: STARTED\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
process.env.LMAS_ROOT = fakeWorkspace
const immediateGuardSessionID = "plugin_immediate_guard_session"
try {
  await plugin.tool.lmas_start.execute(
    { command: "sleep 60" },
    { sessionId: immediateGuardSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  delete process.env.LMAS_ROOT
  restoreBun()
}
if (!spawnedCommand?.includes(fakeWorkspaceScript)) {
  throw new Error(`expected lmas_start to use LMAS_ROOT script in immediate guard test, got ${spawnedCommand}`)
}
const immediateGuardOutput = { args: { command: "cat stdout.log", timeout: 60000 } }
await plugin["tool.execute.before"](
  { tool: "bash", sessionID: immediateGuardSessionID, callID: "call_immediate_guard_bash" },
  immediateGuardOutput,
)
if (immediateGuardOutput.args.command !== "printf '%s\\n' 'LMAS handoff is active; tool execution was blocked by LMAS guard.'") {
  throw new Error("expected lmas_start to activate same-turn tool guard immediately after handoff")
}
await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message("user", "Thanks. Leave the LMAS job running.", "immediate_guard_real_user_no_status", immediateGuardSessionID),
    },
  },
})
let nonStatusSpawned = false
globalThis.Bun = {
  spawn() {
    nonStatusSpawned = true
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_STATUS v1\nrun_id: lmas_immediate_guard\nstatus: RUNNING\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
let nonStatusResult = ""
try {
  nonStatusResult = await plugin.tool.lmas_status.execute(
    { run_id: "lmas_immediate_guard" },
    { sessionID: immediateGuardSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
if (nonStatusSpawned || !nonStatusResult.includes("LMAS handoff is active")) {
  throw new Error("expected lmas_status to be blocked after non-status real user follow-up")
}
await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message("user", "Please check the LMAS status now.", "immediate_guard_real_user_status", immediateGuardSessionID),
    },
  },
})
let statusSpawned = false
globalThis.Bun = {
  spawn() {
    statusSpawned = true
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_STATUS v1\nrun_id: lmas_immediate_guard\nstatus: RUNNING\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
let immediateStatus = ""
try {
  immediateStatus = await plugin.tool.lmas_status.execute(
    { run_id: "lmas_immediate_guard" },
    { sessionID: immediateGuardSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
if (!statusSpawned || !immediateStatus.includes("LMAS_STATUS v1")) {
  throw new Error("expected direct user status request to clear same-turn guard and allow lmas_status")
}
const repeatedStatusOutput = { args: { command: "cat stdout.log", timeout: 60000 } }
await plugin["tool.execute.before"](
  { tool: "bash", sessionID: immediateGuardSessionID, callID: "call_repeated_status_bash" },
  repeatedStatusOutput,
)
if (repeatedStatusOutput.args.command !== "printf '%s\\n' 'LMAS handoff is active; tool execution was blocked by LMAS guard.'") {
  throw new Error("expected RUNNING lmas_status result to reactivate same-turn guard")
}
await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message("user", "Check status again now.", "immediate_guard_second_real_user_status", immediateGuardSessionID),
    },
  },
})
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID: immediateGuardSessionID, callID: "call_second_real_user_todowrite" },
  { args: { todos: [] } },
)

const cancelIntentSessionID = "plugin_cancel_intent_session"
globalThis.Bun = {
  spawn() {
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_HANDOFF v1\nrun_id: lmas_cancel_intent\nstatus: STARTED\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
try {
  await plugin.tool.lmas_start.execute(
    { command: "sleep 60" },
    { sessionID: cancelIntentSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message("user", "Check status and cancel it if it is still running.", "cancel_intent_user", cancelIntentSessionID),
    },
  },
})
globalThis.Bun = {
  spawn() {
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_STATUS v1\nrun_id: lmas_cancel_intent\nstatus: RUNNING\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
try {
  await plugin.tool.lmas_status.execute(
    { run_id: "lmas_cancel_intent" },
    { sessionID: cancelIntentSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
const cancelPermissionFirstOutput = {}
await plugin["permission.ask"](
  {
    type: "tool",
    title: "Run lmas_cancel",
    metadata: { tool: "lmas_cancel" },
    sessionID: cancelIntentSessionID,
    callID: "call_cancel_permission_first",
  },
  cancelPermissionFirstOutput,
)
if (cancelPermissionFirstOutput.status !== undefined) {
  throw new Error("expected LMAS not to override the user's permission decision for lmas_cancel")
}
let cancelSpawned = false
let cancelOutput = ""
const cancelBeforeOutput = { args: { run_id: "lmas_cancel_intent" } }
await plugin["tool.execute.before"](
  { tool: "lmas_cancel", sessionID: cancelIntentSessionID, callID: "call_cancel_intent_before" },
  cancelBeforeOutput,
)
const cancelPermissionOutput = {}
await plugin["permission.ask"](
  { tool: "lmas_cancel", sessionID: cancelIntentSessionID, callID: "call_cancel_intent_before" },
  cancelPermissionOutput,
)
if (cancelPermissionOutput.status !== undefined) {
  throw new Error("expected allowed lmas_cancel call to preserve permission.ask status")
}
const cancelCamelCallBeforeOutput = { args: { run_id: "lmas_cancel_intent" } }
await plugin["tool.execute.before"](
  { tool: "lmas_cancel", sessionID: cancelIntentSessionID, callId: "call_cancel_intent_camel" },
  cancelCamelCallBeforeOutput,
)
const cancelCamelCallPermissionOutput = {}
await plugin["permission.ask"](
  { tool: "lmas_cancel", sessionID: cancelIntentSessionID, callId: "call_cancel_intent_camel" },
  cancelCamelCallPermissionOutput,
)
if (cancelCamelCallPermissionOutput.status !== undefined) {
  throw new Error("expected allowed lmas_cancel callId alias to preserve permission.ask status")
}
const cancelObjectToolBeforeOutput = { args: { run_id: "lmas_cancel_intent" } }
await plugin["tool.execute.before"](
  { tool: { name: "lmas_cancel" }, sessionID: cancelIntentSessionID, callID: "call_cancel_object_tool" },
  cancelObjectToolBeforeOutput,
)
const cancelObjectToolPermissionOutput = {}
await plugin["permission.ask"](
  { tool: { name: "lmas_cancel" }, sessionID: cancelIntentSessionID, callID: "call_cancel_object_tool" },
  cancelObjectToolPermissionOutput,
)
if (cancelObjectToolPermissionOutput.status !== undefined) {
  throw new Error("expected object-shaped lmas_cancel tool to preserve permission.ask status")
}
globalThis.Bun = {
  spawn() {
    cancelSpawned = true
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_CANCEL v1\nrun_id: lmas_cancel_intent\nstatus: CANCELLED\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
try {
  cancelOutput = await plugin.tool.lmas_cancel.execute(
    { run_id: "lmas_cancel_intent" },
    { sessionID: cancelIntentSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
if (!cancelSpawned) {
  throw new Error(`expected explicit user cancel intent to allow lmas_cancel after RUNNING status, got: ${cancelOutput}`)
}
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID: cancelIntentSessionID, callID: "call_after_cancel_todowrite" },
  { args: { todos: [] } },
)

const pathCancelSessionID = "plugin_path_cancel_session"
const pathCancelRunID = "lmas_cancel_path"
const pathCancelRunDir = `${fakeWorkspace}/.lmas/runs/${pathCancelRunID}`
await plugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: pathCancelSessionID,
      delta: `LMAS_HANDOFF v1\nrun_id: ${pathCancelRunID}\nstatus: STARTED`,
    },
  },
})
await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message("user", "Cancel that LMAS run now.", "path_cancel_user", pathCancelSessionID),
    },
  },
})
globalThis.Bun = {
  spawn() {
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(`LMAS_STATUS v1\nrun_id: ${pathCancelRunID}\nstatus: RUNNING\n`))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
try {
  await plugin.tool.lmas_status.execute(
    { run_id: pathCancelRunID },
    { sessionID: pathCancelSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
const pathCancelBeforeOutput = { args: { run_id: pathCancelRunDir } }
await plugin["tool.execute.before"](
  { tool: "lmas_cancel", sessionID: pathCancelSessionID, callID: "call_path_cancel_before" },
  pathCancelBeforeOutput,
)
const pathCancelPermissionOutput = {}
await plugin["permission.ask"](
  { tool: "lmas_cancel", sessionID: pathCancelSessionID, callID: "call_path_cancel_before" },
  pathCancelPermissionOutput,
)
if (pathCancelPermissionOutput.status !== undefined) {
  throw new Error("expected allowed lmas_cancel run directory path to preserve permission.ask status")
}
let pathCancelSpawnedCommand
globalThis.Bun = {
  spawn(command) {
    pathCancelSpawnedCommand = command
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(`LMAS_CANCEL v1\nrun_id: ${pathCancelRunID}\nstatus: CANCELLED\n`))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
try {
  await plugin.tool.lmas_cancel.execute(
    { run_id: pathCancelRunDir },
    { sessionID: pathCancelSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
if (!Array.isArray(pathCancelSpawnedCommand) || pathCancelSpawnedCommand.at(-1) !== pathCancelRunDir) {
  throw new Error("expected lmas_cancel run directory path to be passed through to the CLI")
}

const omoCancelSessionID = "plugin_omo_cancel_session"
await plugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: omoCancelSessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_omo_cancel\nstatus: STARTED",
    },
  },
})
const omoCancelOutput = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_cancel_continue",
      omoCancelSessionID,
    ),
  ],
}
omoCancelOutput.messages[0].parts[0].synthetic = true
omoCancelOutput.messages[0].parts[0].metadata = { compaction_continue: true }
await plugin["experimental.chat.messages.transform"]({}, omoCancelOutput)
let blockedOmoCancel = false
try {
  await plugin["tool.execute.before"](
    { tool: "lmas_cancel", sessionID: omoCancelSessionID, callID: "call_omo_cancel_before" },
    { args: { run_id: "lmas_omo_cancel" } },
  )
} catch (error) {
  blockedOmoCancel = String(error?.message || "").includes("LMAS handoff is active")
}
if (!blockedOmoCancel) {
  throw new Error("expected OMO continuation to be blocked from cancelling active LMAS run before tool execution")
}
const omoCancelPermissionOutput = {}
await plugin["permission.ask"](
  { tool: "lmas_cancel", sessionID: omoCancelSessionID, callID: "call_omo_cancel_before" },
  omoCancelPermissionOutput,
)
if (omoCancelPermissionOutput.status !== "deny") {
  throw new Error("expected blocked OMO lmas_cancel call to be denied by permission.ask")
}

await plugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_plugin_guard\nstatus: STARTED",
    },
  },
})

const chatMessageSessionID = "plugin_chat_message_session"
await plugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID: chatMessageSessionID,
      delta: "LMAS_HANDOFF v1\nrun_id: lmas_chat_message\nstatus: STARTED",
    },
  },
})
await plugin["chat.message"](
  { sessionID: chatMessageSessionID, agent: "sisyphus" },
  {
    message: {
      id: "chat_message_omo_continue",
      sessionID: chatMessageSessionID,
      role: "user",
      time: { created: Date.now() },
      agent: "test",
      model: { providerID: "test", modelID: "test" },
    },
    parts: [{
      id: "chat_message_omo_continue_part",
      type: "text",
      text: "Continue working on the remaining task.",
      synthetic: true,
    }],
  },
)
let chatMessageBlocked = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID: chatMessageSessionID, callID: "call_chat_message_omo_todowrite" },
    { args: { todos: [] } },
  )
} catch (error) {
  chatMessageBlocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!chatMessageBlocked) {
  throw new Error("expected chat.message OMO continuation to activate tool guard")
}
await plugin["chat.message"](
  { sessionID: chatMessageSessionID, agent: "sisyphus" },
  {
    message: {
      id: "chat_message_cancel",
      sessionID: chatMessageSessionID,
      role: "user",
      time: { created: Date.now() },
      agent: "test",
      model: { providerID: "test", modelID: "test" },
    },
    parts: [{
      id: "chat_message_cancel_part",
      type: "text",
      text: "Cancel the LMAS run now.",
    }],
  },
)
const chatMessageCancelPermissionOutput = {}
await plugin["permission.ask"](
  { tool: "lmas_cancel", sessionID: chatMessageSessionID, callID: "call_chat_message_cancel_permission" },
  chatMessageCancelPermissionOutput,
)
if (chatMessageCancelPermissionOutput.status !== undefined) {
  throw new Error("expected chat.message explicit user cancel request to preserve permission.ask status")
}

const fallbackCliSessionID = "plugin_fallback_cli_session"
const untrustedToolOutputSessionID = "plugin_untrusted_tool_output_session"
await plugin["tool.execute.after"](
  {
    tool: "bash",
    sessionID: untrustedToolOutputSessionID,
    callID: "call_untrusted_tool_output",
    args: { command: "rg lmas start README.md" },
  },
  {
    title: "bash",
    output: "documentation example:\nLMAS_HANDOFF v1\nrun_id: lmas_untrusted_output\nstatus: STARTED\n",
    metadata: {},
  },
)
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID: untrustedToolOutputSessionID, callID: "call_after_untrusted_output" },
  { args: { todos: [] } },
)
const fallbackCliEnvOutput = { env: {} }
await plugin["shell.env"](
  { cwd: fakeWorkspace, sessionID: fallbackCliSessionID, callID: "call_fallback_cli_shell_env" },
  fallbackCliEnvOutput,
)
if (
  fallbackCliEnvOutput.env.LMAS_OPENCODE_SESSION_ID !== fallbackCliSessionID
  || fallbackCliEnvOutput.env.LMAS_OPENCODE_SERVER_URL !== "http://127.0.0.1:4096"
) {
  throw new Error("expected shell.env to inject OpenCode session/server env for LMAS CLI fallback")
}
const fallbackCliExistingEnvOutput = { env: { LMAS_OPENCODE_SERVER_URL: "http://127.0.0.1:4999" } }
await plugin["shell.env"](
  { cwd: fakeWorkspace, sessionID: fallbackCliSessionID, callID: "call_fallback_cli_shell_existing_env" },
  fallbackCliExistingEnvOutput,
)
if (
  fallbackCliExistingEnvOutput.env.LMAS_OPENCODE_SESSION_ID !== fallbackCliSessionID
  || fallbackCliExistingEnvOutput.env.LMAS_OPENCODE_SERVER_URL !== "http://127.0.0.1:4999"
) {
  throw new Error("expected shell.env to preserve explicit OpenCode server env while setting session id")
}
await plugin["tool.execute.after"](
  {
    tool: "bash",
    sessionID: fallbackCliSessionID,
    callID: "call_fallback_cli_start",
    args: { command: "lmas start --adapter opencode -- sleep 60" },
  },
  {
    title: "bash",
    output: "LMAS_HANDOFF v1\nrun_id: lmas_fallback_cli\nstatus: STARTED\n",
    metadata: {},
  },
)
let fallbackCliBlocked = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID: fallbackCliSessionID, callID: "call_fallback_cli_todowrite" },
    { args: { todos: [] } },
  )
} catch (error) {
  fallbackCliBlocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!fallbackCliBlocked) {
  throw new Error("expected tool.execute.after LMAS_HANDOFF output to activate guard for CLI fallback")
}
await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message("user", "Please check status once.", "fallback_cli_real_user_status", fallbackCliSessionID),
    },
  },
})
await plugin["tool.execute.after"](
  {
    tool: "bash",
    sessionID: fallbackCliSessionID,
    callID: "call_fallback_cli_status",
    args: { command: "lmas status lmas_fallback_cli" },
  },
  {
    title: "bash",
    output: "LMAS_STATUS v1\nrun_id: lmas_fallback_cli\nstatus: RUNNING\n",
    metadata: {},
  },
)
let fallbackCliStatusBlocked = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID: fallbackCliSessionID, callID: "call_fallback_cli_after_status" },
    { args: { todos: [] } },
  )
} catch (error) {
  fallbackCliStatusBlocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!fallbackCliStatusBlocked) {
  throw new Error("expected tool.execute.after LMAS_STATUS RUNNING output to reactivate guard for CLI fallback")
}
await plugin["tool.execute.after"](
  {
    tool: "bash",
    sessionID: fallbackCliSessionID,
    callID: "call_fallback_cli_completion",
    args: { command: "cat .lmas/runs/lmas_fallback_cli/resume_prompt.txt" },
  },
  {
    title: "bash",
    output: "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_fallback_cli\nstatus: SUCCEEDED\n",
    metadata: {},
  },
)
let untrustedCompletionBlocked = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID: fallbackCliSessionID, callID: "call_fallback_cli_after_completion" },
    { args: { todos: [] } },
  )
} catch (error) {
  untrustedCompletionBlocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!untrustedCompletionBlocked) {
  throw new Error("expected arbitrary command output containing an LMAS completion record not to change guard state")
}
await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message(
        "assistant",
        "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_fallback_cli\nstatus: SUCCEEDED",
        "fallback_cli_trusted_completion",
        fallbackCliSessionID,
      ),
    },
  },
})
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID: fallbackCliSessionID, callID: "call_fallback_cli_after_trusted_completion" },
  { args: { todos: [] } },
)

const fallbackCliFinalizingCancelSessionID = "plugin_fallback_cli_finalizing_cancel_session"
await plugin["tool.execute.after"](
  {
    tool: "bash",
    sessionID: fallbackCliFinalizingCancelSessionID,
    callID: "call_fallback_cli_finalizing_cancel",
    args: { command: "lmas cancel lmas_fallback_finalizing_cancel" },
  },
  {
    title: "bash",
    output: [
      "LMAS_CANCEL v1",
      "run_id: lmas_fallback_finalizing_cancel",
      "status: ALREADY_COMPLETED",
      "existing_status: SUCCEEDED",
      "run_dir: .lmas/runs/lmas_fallback_finalizing_cancel",
      "message: job has already exited; completion event is finalizing",
    ].join("\n"),
    metadata: {},
  },
)
let fallbackCliFinalizingCancelBlocked = false
try {
  await plugin["tool.execute.before"](
    {
      tool: "todowrite",
      sessionID: fallbackCliFinalizingCancelSessionID,
      callID: "call_fallback_cli_finalizing_cancel_todowrite",
    },
    { args: { todos: [] } },
  )
} catch (error) {
  fallbackCliFinalizingCancelBlocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!fallbackCliFinalizingCancelBlocked) {
  throw new Error("expected finalizing LMAS_CANCEL output to activate guard for CLI fallback")
}

const output = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_continue",
      sessionID,
    ),
  ],
}
output.messages[0].parts[0].synthetic = true
output.messages[0].parts[0].metadata = { compaction_continue: true }

await plugin["experimental.chat.messages.transform"]({}, output)
if (!output.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected plugin transform hook to neutralize OMO continuation")
}

const markerOnlyOutput = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_marker_only_continue",
      sessionID,
    ),
  ],
}
await plugin["experimental.chat.messages.transform"]({}, markerOnlyOutput)
if (!markerOnlyOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected plugin transform hook to neutralize marker-only OMO continuation")
}

const markerlessDirectiveOutput = {
  messages: [
    message(
      "user",
      [
        "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]",
        "",
        "Incomplete tasks remain in your todo list. Continue working on the next pending task.",
        "",
        "- Proceed without asking for permission",
        "- Mark each task complete when finished",
        "- Do not stop until all tasks are done",
      ].join("\n"),
      "omo_markerless_directive_continue",
      sessionID,
    ),
  ],
}
await plugin["experimental.chat.messages.transform"]({}, markerlessDirectiveOutput)
if (!markerlessDirectiveOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected plugin transform hook to neutralize markerless OMO directive continuation")
}

const markerlessSyntheticOutput = {
  messages: [
    message(
      "user",
      "Continue working on the remaining task.",
      "omo_markerless_synthetic_continue",
      sessionID,
    ),
  ],
}
markerlessSyntheticOutput.messages[0].parts[0].synthetic = true
await plugin["experimental.chat.messages.transform"]({}, markerlessSyntheticOutput)
if (!markerlessSyntheticOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected plugin transform hook to neutralize markerless synthetic continuation")
}

const markerlessNoReplyOutput = {
  messages: [
    message(
      "user",
      "Internal notification only.\n<!-- OMO_INTERNAL_NOREPLY -->",
      "omo_markerless_noreply",
      sessionID,
    ),
  ],
}
markerlessNoReplyOutput.messages[0].parts[0].synthetic = true
await plugin["experimental.chat.messages.transform"]({}, markerlessNoReplyOutput)
if (markerlessNoReplyOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect plugin transform hook to neutralize no-reply synthetic notification")
}

const noSessionOutput = {
  messages: [{
    info: { id: "omo_no_session_id", role: "user" },
    parts: [{
      id: "omo_no_session_id_part",
      type: "text",
      text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      synthetic: true,
      metadata: { compaction_continue: true },
    }],
  }],
}
await plugin["experimental.chat.messages.transform"]({ sessionID }, noSessionOutput)
if (!noSessionOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected plugin transform hook to use input.sessionID fallback")
}

const camelSessionNoSessionOutput = {
  messages: [{
    info: { id: "omo_camel_session_no_session_id", role: "user" },
    parts: [{
      id: "omo_camel_session_no_session_id_part",
      type: "text",
      text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      synthetic: true,
      metadata: { compaction_continue: true },
    }],
  }],
}
await plugin["experimental.chat.messages.transform"]({ sessionId: sessionID }, camelSessionNoSessionOutput)
if (!camelSessionNoSessionOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected plugin transform hook to use input.sessionId fallback")
}

const bashArgs = { command: "cat stdout.log", timeout: 60000 }
const bashOutput = { args: bashArgs }
await plugin["tool.execute.before"](
  { tool: "bash", sessionID, callID: "call_bash" },
  bashOutput,
)
if (!bashOutput.args.command.includes("LMAS handoff is active")) {
  throw new Error("expected plugin tool hook to no-op bash while guard is active")
}
if (!bashArgs.command.includes("LMAS handoff is active")) {
  throw new Error("expected plugin tool hook to mutate original bash args object in place")
}
if (bashOutput.args !== bashArgs) {
  throw new Error("expected plugin tool hook to preserve original bash args object reference")
}

const capitalBashOutput = { args: { command: "cat stdout.log", timeout: 60000 } }
await plugin["tool.execute.before"](
  { tool: "Bash", sessionID, callID: "call_capital_bash" },
  capitalBashOutput,
)
if (!capitalBashOutput.args.command.includes("LMAS handoff is active")) {
  throw new Error("expected plugin tool hook to no-op capitalized Bash while guard is active")
}

const mcpBashOutput = { args: { command: "cat stdout.log", timeout: 60000 } }
await plugin["tool.execute.before"](
  { tool: "mcp_bash", sessionID, callID: "call_mcp_bash" },
  mcpBashOutput,
)
if (!mcpBashOutput.args.command.includes("LMAS handoff is active")) {
  throw new Error("expected plugin tool hook to no-op mcp_bash while guard is active")
}

const objectBashOutput = { args: { command: "cat stdout.log", timeout: 60000 } }
await plugin["tool.execute.before"](
  { tool: { name: "bash" }, sessionID, callID: "call_object_bash" },
  objectBashOutput,
)
if (!objectBashOutput.args.command.includes("LMAS handoff is active")) {
  throw new Error("expected plugin tool hook to no-op object-shaped bash while guard is active")
}

const camelSessionBashOutput = { args: { command: "cat stdout.log", timeout: 60000 } }
await plugin["tool.execute.before"](
  { tool: "bash", sessionId: sessionID, callID: "call_camel_session_bash" },
  camelSessionBashOutput,
)
if (!camelSessionBashOutput.args.command.includes("LMAS handoff is active")) {
  throw new Error("expected plugin tool hook to no-op bash with camelCase session id")
}

let blocked = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID, callID: "call_todowrite" },
    { args: { todos: [] } },
  )
} catch (error) {
  blocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!blocked) {
  throw new Error("expected plugin tool hook to block non-noop tools while guard is active")
}

const permissionOutput = {}
await plugin["permission.ask"](
  { tool: "bash", sessionID, callID: "call_permission" },
  permissionOutput,
)
if (permissionOutput.status !== "deny") {
  throw new Error("expected plugin permission hook to deny while guard is active")
}

const camelSessionPermissionOutput = {}
await plugin["permission.ask"](
  { tool: "bash", sessionId: sessionID, callID: "call_camel_session_permission" },
  camelSessionPermissionOutput,
)
if (camelSessionPermissionOutput.status !== "deny") {
  throw new Error("expected plugin permission hook to deny with camelCase session id")
}

const commandOutput = {
  parts: [{
    type: "text",
    text: "/start-work should not execute during LMAS handoff",
  }],
}
await plugin["command.execute.before"](
  { command: "start-work", arguments: "", sessionID },
  commandOutput,
)
if (
  commandOutput.parts.length !== 1
  || !commandOutput.parts[0].text.includes("LMAS handoff is active")
  || commandOutput.parts[0].metadata?.lmas_guard !== true
) {
  throw new Error("expected plugin command hook to neutralize slash commands while guard is active")
}

const camelSessionCommandOutput = {
  parts: [{
    type: "text",
    text: "/start-work should not execute during LMAS handoff",
  }],
}
await plugin["command.execute.before"](
  { command: "start-work", arguments: "", sessionId: sessionID },
  camelSessionCommandOutput,
)
if (
  camelSessionCommandOutput.parts.length !== 1
  || !camelSessionCommandOutput.parts[0].text.includes("LMAS handoff is active")
  || camelSessionCommandOutput.parts[0].metadata?.lmas_guard !== true
) {
  throw new Error("expected plugin command hook to neutralize slash commands with camelCase session id")
}

await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message("user", "Cancel the LMAS run now.", "event_real_user_cancel", sessionID),
    },
  },
})
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID, callID: "call_event_real_user_todowrite" },
  { args: { todos: [] } },
)

await plugin.event({
  event: {
    type: "message.updated",
    properties: {
      message: message(
        "user",
        "I pasted this old log:\nLMAS_HANDOFF v1\nrun_id: lmas_plugin_user_paste\nstatus: STARTED",
        "event_user_handoff_paste",
        sessionID,
      ),
    },
  },
})
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID, callID: "call_event_user_handoff_paste_todowrite" },
  { args: { todos: [] } },
)

await plugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID,
      role: "user",
      delta: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
    },
  },
})
let eventDeltaBlocked = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID, callID: "call_event_delta_omo_todowrite" },
    { args: { todos: [] } },
  )
} catch (error) {
  eventDeltaBlocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!eventDeltaBlocked) {
  throw new Error("expected plugin event hook marker-only OMO delta to activate tool guard")
}
await plugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID,
      role: "user",
      synthetic: true,
      delta: "Continue working on the remaining task.",
    },
  },
})
let eventMarkerlessSyntheticBlocked = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID, callID: "call_event_markerless_synthetic_todowrite" },
    { args: { todos: [] } },
  )
} catch (error) {
  eventMarkerlessSyntheticBlocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!eventMarkerlessSyntheticBlocked) {
  throw new Error("expected plugin event hook markerless synthetic delta to activate tool guard")
}
await plugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID,
      role: "user",
      delta: "Cancel the LMAS run now.",
    },
  },
})
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID, callID: "call_event_delta_real_user_todowrite" },
  { args: { todos: [] } },
)

const eventOmoMessage = message(
  "user",
  "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
  "event_omo_continue",
  sessionID,
)
eventOmoMessage.parts[0].synthetic = true
eventOmoMessage.parts[0].metadata = { compaction_continue: true }
await plugin.event({
  event: {
    type: "message.updated",
    properties: { message: eventOmoMessage },
  },
})
let eventBlocked = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID, callID: "call_event_omo_todowrite" },
    { args: { todos: [] } },
  )
} catch (error) {
  eventBlocked = String(error?.message || "").includes("LMAS handoff is active")
}
if (!eventBlocked) {
  throw new Error("expected plugin event hook OMO continuation to activate tool guard")
}

const realUserOutput = {
  messages: [
    message(
      "assistant",
      "LMAS_HANDOFF v1\nrun_id: lmas_plugin_guard\nstatus: STARTED",
      "assistant_handoff",
      sessionID,
    ),
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "stale_omo_continue",
      sessionID,
    ),
    message("user", "Cancel the LMAS run now.", "real_user_cancel", sessionID),
  ],
}
realUserOutput.messages[1].parts[0].synthetic = true
realUserOutput.messages[1].parts[0].metadata = { compaction_continue: true }
await plugin["experimental.chat.messages.transform"]({}, realUserOutput)
if (!realUserOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected plugin transform hook to neutralize stale OMO continuation before real user follow-up")
}
if (realUserOutput.messages[2].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect plugin transform hook to neutralize real user follow-up")
}
const realUserToolOutput = { args: { todos: [] } }
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID, callID: "call_real_user_todowrite" },
  realUserToolOutput,
)

const realUserCommandOutput = {
  parts: [{
    type: "text",
    text: "/help",
  }],
}
await plugin["command.execute.before"](
  { command: "help", arguments: "", sessionID },
  realUserCommandOutput,
)
if (realUserCommandOutput.parts[0].metadata?.lmas_guard === true) {
  throw new Error("did not expect a real user slash command to be neutralized after real user follow-up")
}

const knownOmoCommandOutput = {
  parts: [{
    type: "text",
    text: "You are starting a Sisyphus work session.",
  }],
}
await plugin["command.execute.before"](
  { command: "start-work", arguments: "", sessionID },
  knownOmoCommandOutput,
)
if (
  knownOmoCommandOutput.parts.length !== 1
  || !knownOmoCommandOutput.parts[0].text.includes("LMAS handoff is active")
  || knownOmoCommandOutput.parts[0].metadata?.lmas_guard !== true
) {
  throw new Error("expected command hook to neutralize known OMO start-work command during active LMAS handoff")
}

const ralphLoopCommandOutput = {
  parts: [{
    type: "text",
    text: "You are starting a Ralph Loop.",
  }],
}
await plugin["command.execute.before"](
  { command: "ralph-loop", arguments: "continue", sessionID },
  ralphLoopCommandOutput,
)
if (
  ralphLoopCommandOutput.parts.length !== 1
  || !ralphLoopCommandOutput.parts[0].text.includes("LMAS handoff is active")
  || ralphLoopCommandOutput.parts[0].metadata?.lmas_guard !== true
) {
  throw new Error("expected command hook to neutralize known OMO ralph-loop command during active LMAS handoff")
}

for (const command of omoContinuationHooks.filter((hook) => hook !== "ralph-loop")) {
  const knownContinuationCommandOutput = {
    parts: [{
      type: "text",
      text: `You are starting ${command}.`,
    }],
  }
  await plugin["command.execute.before"](
    { command, arguments: "continue", sessionID },
    knownContinuationCommandOutput,
  )
  if (
    knownContinuationCommandOutput.parts.length !== 1
    || !knownContinuationCommandOutput.parts[0].text.includes("LMAS handoff is active")
    || knownContinuationCommandOutput.parts[0].metadata?.lmas_guard !== true
  ) {
    throw new Error(`expected command hook to neutralize known OMO ${command} command during active LMAS handoff`)
  }
}

const lateOmoCommandOutput = {
  parts: [{
    type: "text",
    text: "Continue working on the remaining task.",
    synthetic: true,
    metadata: { compaction_continue: true },
  }],
}
await plugin["command.execute.before"](
  { command: "start-work", arguments: "", sessionID },
  lateOmoCommandOutput,
)
if (
  lateOmoCommandOutput.parts.length !== 1
  || !lateOmoCommandOutput.parts[0].text.includes("LMAS handoff is active")
  || lateOmoCommandOutput.parts[0].metadata?.lmas_guard !== true
) {
  throw new Error("expected command hook to neutralize synthetic OMO command even after real user follow-up")
}

globalThis.Bun = {
  spawn() {
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_STATUS v1\nrun_id: lmas_plugin_guard\nstatus: RUNNING\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
try {
  await plugin.tool.lmas_status.execute(
    { run_id: "lmas_plugin_guard" },
    { sessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
const transformCancelPermissionOutput = {}
await plugin["permission.ask"](
  {
    type: "tool",
    title: "Run lmas_cancel",
    metadata: { tool: "lmas_cancel" },
    sessionID,
    callID: "call_transform_cancel_permission_first",
  },
  transformCancelPermissionOutput,
)
if (transformCancelPermissionOutput.status !== undefined) {
  throw new Error("expected transform-only explicit user cancel intent to preserve permission.ask status")
}

const revokedCancelOutput = {
  messages: [
    message(
      "assistant",
      "LMAS_HANDOFF v1\nrun_id: lmas_plugin_guard\nstatus: STARTED",
      "revoked_cancel_handoff",
      sessionID,
    ),
    message("user", "Do not cancel the LMAS run after all.", "revoked_cancel_user", sessionID),
  ],
}
await plugin["experimental.chat.messages.transform"]({}, revokedCancelOutput)
globalThis.Bun = {
  spawn() {
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_STATUS v1\nrun_id: lmas_plugin_guard\nstatus: RUNNING\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
try {
  await plugin.tool.lmas_status.execute(
    { run_id: "lmas_plugin_guard" },
    { sessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
const revokedCancelPermissionOutput = {}
await plugin["permission.ask"](
  {
    type: "tool",
    title: "Run lmas_cancel",
    metadata: { tool: "lmas_cancel" },
    sessionID,
    callID: "call_revoked_cancel_permission_first",
  },
  revokedCancelPermissionOutput,
)
if (revokedCancelPermissionOutput.status !== "deny") {
  throw new Error("expected later negated user cancel text to revoke lmas_cancel permission")
}

const negatedCancelSessionID = "plugin_negated_cancel_session"
const negatedCancelOutput = {
  messages: [
    message(
      "assistant",
      "LMAS_HANDOFF v1\nrun_id: lmas_plugin_negated_cancel\nstatus: STARTED",
      "negated_cancel_handoff",
      negatedCancelSessionID,
    ),
    message("user", "Do not cancel the LMAS run. Wait for completion.", "negated_cancel_user", negatedCancelSessionID),
  ],
}
await plugin["experimental.chat.messages.transform"]({}, negatedCancelOutput)
globalThis.Bun = {
  spawn() {
    return {
      stdout: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode("LMAS_STATUS v1\nrun_id: lmas_plugin_negated_cancel\nstatus: RUNNING\n"))
          controller.close()
        },
      }),
      stderr: new ReadableStream({
        start(controller) {
          controller.close()
        },
      }),
      exited: Promise.resolve(0),
    }
  },
}
try {
  await plugin.tool.lmas_status.execute(
    { run_id: "lmas_plugin_negated_cancel" },
    { sessionID: negatedCancelSessionID, directory: fakeWorkspace, worktree: fakeWorkspace },
  )
} finally {
  restoreBun()
}
const negatedCancelPermissionOutput = {}
await plugin["permission.ask"](
  {
    type: "tool",
    title: "Run lmas_cancel",
    metadata: { tool: "lmas_cancel" },
    sessionID: negatedCancelSessionID,
    callID: "call_negated_cancel_permission_first",
  },
  negatedCancelPermissionOutput,
)
if (negatedCancelPermissionOutput.status !== "deny") {
  throw new Error("expected negated cancel text not to allow lmas_cancel after RUNNING status")
}

const secondOmoOutput = {
  messages: [
    message(
      "assistant",
      "LMAS_HANDOFF v1\nrun_id: lmas_plugin_guard\nstatus: STARTED",
      "assistant_handoff_again",
      sessionID,
    ),
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "second_omo_continue",
      sessionID,
    ),
  ],
}
secondOmoOutput.messages[1].parts[0].synthetic = true
secondOmoOutput.messages[1].parts[0].metadata = { compaction_continue: true }
await plugin["experimental.chat.messages.transform"]({}, secondOmoOutput)
let blockedAgain = false
try {
  await plugin["tool.execute.before"](
    { tool: "todowrite", sessionID, callID: "call_second_omo_todowrite" },
    { args: { todos: [] } },
  )
} catch (error) {
  blockedAgain = String(error?.message || "").includes("LMAS handoff is active")
}
if (!blockedAgain) {
  throw new Error("expected later OMO continuation to reactivate plugin tool guard")
}

await plugin.event({
  event: {
    type: "message.part.delta",
    properties: {
      sessionID,
      delta: "\nLMAS_COMPLETION_EVENT v1\nrun_id: lmas_plugin_guard\nstatus: SUCCEEDED",
    },
  },
})

const postCompletionOutput = { args: { todos: [] } }
await plugin["tool.execute.before"](
  { tool: "todowrite", sessionID, callID: "call_after_completion" },
  postCompletionOutput,
)

console.log("ok opencode plugin guard")
JS
