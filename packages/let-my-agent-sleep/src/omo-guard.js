const OMO_TODO_CONTINUATION = "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]"
const OMO_DIRECTIVE_PREFIX = "[SYSTEM DIRECTIVE: OH-MY-OPENCODE"
const OMO_INTERNAL_INITIATOR = "<!-- OMO_INTERNAL_INITIATOR -->"
const OMO_INTERNAL_NOREPLY = "<!-- OMO_INTERNAL_NOREPLY -->"
const LMAS_HANDOFF = "LMAS_HANDOFF v1"
const LMAS_STATUS = "LMAS_STATUS v1"
const LMAS_CANCEL = "LMAS_CANCEL v1"
const LMAS_COMPLETION = "LMAS_COMPLETION_EVENT v1"
export const GUARD_TTL_MS = 10 * 60 * 1000
export const MAX_EVENT_TEXT_BUFFER = 16384

export function collectTextFromPart(part) {
  const chunks = []
  if (typeof part?.text === "string") chunks.push(part.text)
  if (typeof part?.state?.output === "string") chunks.push(part.state.output)
  return chunks.join("\n")
}

export function collectTextFromMessage(message) {
  return (message?.parts || []).map(collectTextFromPart).filter(Boolean).join("\n")
}

function getSessionIDFromMessage(message) {
  return message?.info?.sessionID
    || (message?.parts || []).find((part) => part?.sessionID)?.sessionID
}

export function getSessionIDFromEvent(event) {
  return event?.properties?.sessionID
    || event?.properties?.part?.sessionID
    || event?.properties?.info?.sessionID
    || event?.properties?.info?.id
    || event?.properties?.message?.info?.sessionID
    || (event?.properties?.message?.parts || []).find((part) => part?.sessionID)?.sessionID
}

export function getSessionIDFromPromptInput(input) {
  if (typeof input?.path === "string") return input.path
  if (typeof input?.path?.id === "string") return input.path.id
  if (typeof input?.path?.sessionID === "string") return input.path.sessionID
  if (typeof input?.path?.sessionId === "string") return input.path.sessionId
  if (typeof input?.sessionID === "string") return input.sessionID
  if (typeof input?.sessionId === "string") return input.sessionId
  return undefined
}

export function getTextFromEvent(event) {
  const part = event?.properties?.part
  if (typeof part?.text === "string") return part.text
  if (typeof part?.state?.output === "string") return part.state.output
  if (event?.properties?.message) return collectTextFromMessage(event.properties.message)
  if (event?.properties?.info?.parts) return collectTextFromMessage(event.properties.info)
  if (typeof event?.properties?.delta === "string") return event.properties.delta
  return ""
}

export function isReplyExpectingInternalPromptInput(input) {
  const body = input?.body || input
  if (body?.noReply === true) return false

  const parts = Array.isArray(body?.parts) ? body.parts : []
  if (parts.length === 0) return false

  const text = parts.map(collectTextFromPart).filter(Boolean).join("\n")
  if (text.includes(OMO_INTERNAL_NOREPLY)) return false
  if (stripOmoInternalMarkers(text).length === 0) return false

  return parts.some(partIsSyntheticOrInternal)
}

export function shouldBlockPromptInputDuringActiveHandoff(input) {
  const body = input?.body || input
  if (body?.noReply === true) return false

  const parts = Array.isArray(body?.parts) ? body.parts : []
  if (parts.length === 0) return false

  const text = parts.map(collectTextFromPart).filter(Boolean).join("\n")
  if (text.includes(LMAS_COMPLETION)) return false
  if (text.includes(OMO_INTERNAL_NOREPLY)) return false

  return stripOmoInternalMarkers(text).length > 0
}

export function getRoleFromEvent(event) {
  return event?.properties?.message?.info?.role
    || event?.properties?.part?.role
    || event?.properties?.part?.info?.role
    || event?.properties?.role
    || event?.properties?.info?.role
}

function getEventTextBufferKey(event, sessionID) {
  const messageID = event?.properties?.message?.info?.id
    || event?.properties?.messageID
    || event?.properties?.messageId
    || event?.properties?.part?.messageID
    || event?.properties?.part?.messageId
    || event?.properties?.part?.message?.id
    || event?.properties?.info?.messageID
    || event?.properties?.info?.messageId
  if (messageID) return `${sessionID}:message:${messageID}`

  const partID = event?.properties?.part?.id
    || event?.properties?.partID
    || event?.properties?.partId
  if (partID) return `${sessionID}:part:${partID}`

  return `${sessionID}:role:${getRoleFromEvent(event) || "unknown"}`
}

export function appendEventTextBuffer(eventTextBuffers, bufferKey, text) {
  const existing = eventTextBuffers.get(bufferKey) || ""
  const next = `${existing}${text}`.slice(-MAX_EVENT_TEXT_BUFFER)
  eventTextBuffers.set(bufferKey, next)
  return next
}

function extractRunIds(text) {
  const runIds = []
  const pattern = /^run_id:\s*(\S+)/gm
  let match
  while ((match = pattern.exec(text)) !== null) {
    runIds.push(match[1])
  }
  return runIds
}

function isFinalizingCancelText(text) {
  return typeof text === "string"
    && text.includes(LMAS_CANCEL)
    && /^status:\s*ALREADY_COMPLETED$/m.test(text)
    && /^message:\s*job has already exited; completion event is finalizing$/m.test(text)
}

function unique(values) {
  return [...new Set(values)]
}

function stripOmoInternalMarkers(text) {
  return text
    .replace(/<!--\s*OMO_INTERNAL_INITIATOR\s*-->/g, "")
    .replace(/<!--\s*OMO_INTERNAL_NOREPLY\s*-->/g, "")
    .trim()
}

function hasOmoInternalInitiatorMarker(text) {
  return typeof text === "string" && /<!--\s*OMO_INTERNAL_INITIATOR\s*-->/.test(text)
}

function isOmoReplyExpectingInternalText(text) {
  if (!text.includes(OMO_INTERNAL_INITIATOR)) return false
  if (text.includes(OMO_INTERNAL_NOREPLY)) return false
  return stripOmoInternalMarkers(text).length > 0
}

function looksLikeOmoContinuationDirectiveText(text) {
  if (typeof text !== "string" || text.includes(OMO_INTERNAL_NOREPLY)) return false
  const stripped = stripOmoInternalMarkers(text)
  if (stripped.length === 0) return false
  if (!stripped.startsWith(OMO_DIRECTIVE_PREFIX)) return false

  return stripped.includes("TODO CONTINUATION")
    || stripped.includes("RALPH LOOP")
    || stripped.includes("BOULDER CONTINUATION")
    || (
      stripped.includes("Incomplete tasks remain in your todo list")
      && stripped.includes("Continue working on the next pending task")
    )
}

function partIsSyntheticOrInternal(part) {
  return part?.synthetic === true
    || part?.metadata?.compaction_continue === true
    || hasOmoInternalInitiatorMarker(part?.text)
    || hasOmoInternalInitiatorMarker(part?.state?.output)
}

function messageHasSyntheticOrInternalPart(message) {
  return (message?.parts || []).some(partIsSyntheticOrInternal)
}

function isReplyExpectingSyntheticUserMessage(message, text) {
  if (!messageHasSyntheticOrInternalPart(message)) return false
  if (text.includes(OMO_INTERNAL_NOREPLY)) return false
  return stripOmoInternalMarkers(text).length > 0
}

function eventHasSyntheticOrInternalPart(event, text) {
  const part = event?.properties?.part
  const messageParts = event?.properties?.message?.parts || []
  return event?.properties?.synthetic === true
    || event?.properties?.metadata?.compaction_continue === true
    || hasOmoInternalInitiatorMarker(text)
    || partIsSyntheticOrInternal(part)
    || messageParts.some(partIsSyntheticOrInternal)
}

function isOmoContinuationEvent(event, text) {
  const role = getRoleFromEvent(event)
  if (role && role !== "user") return false
  const eventText = getTextFromEvent(event)
  if (!eventHasSyntheticOrInternalPart(event, eventText) && !looksLikeOmoContinuationDirectiveText(text)) return false
  return isOmoTodoContinuationMessage({
    info: { role: "user" },
    parts: [{
      type: "text",
      text,
      synthetic: true,
      metadata: { compaction_continue: true },
    }],
  })
}

function hasExplicitCancelIntent(text) {
  if (typeof text !== "string" || text.trim().length === 0) return false
  const normalized = text.toLowerCase()
  const englishCancelWord = "(?:cancel|abort|terminate|kill)"
  const englishNegation = new RegExp(
    `\\b(?:do\\s+not|don't|dont|never|not|no\\s+need\\s+to|without)\\s+(?:\\w+\\s+){0,4}${englishCancelWord}\\b`,
    "i",
  )
  const koreanNegation = /(취소|중단|종료)하지\s*(마|말|마세요|말아|않)|안\s*(취소|중단|종료)|취소\s*(금지|하지\s*마)/

  if (englishNegation.test(normalized) || koreanNegation.test(text)) return false
  return new RegExp(`\\b${englishCancelWord}\\b`, "i").test(text)
    || /취소|중단|종료/.test(text)
}

export function updateSessionGuardFromText(sessionGuards, sessionID, text, now = Date.now(), options = {}) {
  if (!sessionID || typeof text !== "string" || text.length === 0) return undefined
  const allowHandoff = options.allowHandoff ?? true
  const allowCompletion = options.allowCompletion ?? true
  const allowCancel = options.allowCancel ?? true
  const hasAllowedHandoff = allowHandoff && text.includes(LMAS_HANDOFF)
  const hasAllowedCompletion = allowCompletion && text.includes(LMAS_COMPLETION)
  const hasAllowedCancel = allowCancel && text.includes(LMAS_CANCEL)

  if (!hasAllowedHandoff && !hasAllowedCompletion && !hasAllowedCancel) {
    return sessionGuards.get(sessionID)
  }

  const existing = sessionGuards.get(sessionID) || {
    active: false,
    omoTurn: false,
    runIds: [],
    updatedAt: now,
  }
  let runIds = Array.isArray(existing.runIds) ? [...existing.runIds] : []

  if (hasAllowedHandoff) {
    runIds = unique([...runIds, ...extractRunIds(text)])
  }
  if (hasAllowedCompletion) {
    const completedRunIds = new Set(extractRunIds(text))
    runIds = runIds.filter((runId) => !completedRunIds.has(runId))
  }
  if (hasAllowedCancel && !isFinalizingCancelText(text)) {
    const cancelRunIds = new Set(extractRunIds(text))
    runIds = runIds.filter((runId) => !cancelRunIds.has(runId))
  }

  const next = {
    active: runIds.length > 0,
    omoTurn: options.omoTurn ?? existing.omoTurn,
    allowCancel: runIds.length > 0 ? existing.allowCancel === true : false,
    runIds,
    updatedAt: now,
  }
  sessionGuards.set(sessionID, next)
  return next
}

export function updateSessionGuardFromStatusText(sessionGuards, sessionID, text, now = Date.now()) {
  if (!sessionID || typeof text !== "string" || !text.includes(LMAS_STATUS)) {
    return sessionGuards.get(sessionID)
  }

  const status = text.match(/^status:\s*(\S+)/m)?.[1]
  const statusRunIds = extractRunIds(text)
  const existing = sessionGuards.get(sessionID) || {
    active: false,
    omoTurn: false,
    runIds: [],
    updatedAt: now,
  }
  const existingRunIds = Array.isArray(existing.runIds) ? existing.runIds : []

  if (status === "RUNNING" || status === "FINALIZING") {
    const runIds = unique([...existingRunIds, ...statusRunIds])
    const next = {
      active: runIds.length > 0,
      omoTurn: runIds.length > 0,
      allowCancel: existing.allowCancel === true,
      runIds,
      updatedAt: now,
    }
    sessionGuards.set(sessionID, next)
    return next
  }

  if (statusRunIds.length === 0) return existing

  const finished = new Set(statusRunIds)
  const runIds = existingRunIds.filter((runId) => !finished.has(runId))
  const next = {
    active: runIds.length > 0,
    omoTurn: runIds.length > 0 ? existing.omoTurn : false,
    allowCancel: runIds.length > 0 ? existing.allowCancel === true : false,
    runIds,
    updatedAt: now,
  }
  sessionGuards.set(sessionID, next)
  return next
}

export function updateSessionGuardFromCancelText(sessionGuards, sessionID, text, now = Date.now()) {
  if (!sessionID || typeof text !== "string" || !text.includes(LMAS_CANCEL)) {
    return sessionGuards.get(sessionID)
  }

  const cancelRunIds = extractRunIds(text)
  if (cancelRunIds.length === 0) return sessionGuards.get(sessionID)

  const existing = sessionGuards.get(sessionID) || {
    active: false,
    omoTurn: false,
    allowCancel: false,
    runIds: [],
    updatedAt: now,
  }
  if (isFinalizingCancelText(text)) {
    const runIds = unique([...(Array.isArray(existing.runIds) ? existing.runIds : []), ...cancelRunIds])
    const next = {
      active: runIds.length > 0,
      omoTurn: runIds.length > 0,
      allowCancel: runIds.length > 0 ? existing.allowCancel === true : false,
      runIds,
      updatedAt: now,
    }
    sessionGuards.set(sessionID, next)
    return next
  }
  const cancelled = new Set(cancelRunIds)
  const runIds = (Array.isArray(existing.runIds) ? existing.runIds : []).filter((runId) => !cancelled.has(runId))
  const next = {
    active: runIds.length > 0,
    omoTurn: runIds.length > 0 ? existing.omoTurn : false,
    allowCancel: runIds.length > 0 ? existing.allowCancel === true : false,
    runIds,
    updatedAt: now,
  }
  sessionGuards.set(sessionID, next)
  return next
}

export function updateSessionGuardFromEvent(sessionGuards, eventTextBuffers, event, now = Date.now()) {
  const sessionID = getSessionIDFromEvent(event)
  if (event?.type === "session.deleted") {
    clearSessionGuard(sessionGuards, sessionID)
    for (const key of eventTextBuffers.keys()) {
      if (String(key).startsWith(`${sessionID}:`)) eventTextBuffers.delete(key)
    }
    eventTextBuffers.delete(sessionID)
    return undefined
  }

  const text = getTextFromEvent(event)
  if (!sessionID || !text) return undefined

  const role = getRoleFromEvent(event)
  const allowHandoff = role !== "user"

  if (event?.type === "message.part.delta") {
    const bufferKey = getEventTextBufferKey(event, sessionID)
    const bufferedText = appendEventTextBuffer(eventTextBuffers, bufferKey, text)
    const next = updateSessionGuardFromText(
      sessionGuards,
      sessionID,
      bufferedText,
      now,
      { allowHandoff },
    )
    if (
      bufferedText.includes(LMAS_HANDOFF)
      || bufferedText.includes(LMAS_STATUS)
      || bufferedText.includes(LMAS_COMPLETION)
      || bufferedText.includes(LMAS_CANCEL)
    ) {
      eventTextBuffers.delete(bufferKey)
    }
    const existing = sessionGuards.get(sessionID)
    if (existing?.active && isOmoContinuationEvent(event, bufferedText)) {
      const guarded = {
        ...existing,
        omoTurn: true,
        updatedAt: now,
      }
      sessionGuards.set(sessionID, guarded)
      return guarded
    }
    if (existing?.active && role === "user") {
      const unguarded = {
        ...existing,
        omoTurn: false,
        allowCancel: hasExplicitCancelIntent(bufferedText),
        updatedAt: now,
      }
      sessionGuards.set(sessionID, unguarded)
      return unguarded
    }
    if (role === "user" && hasExplicitCancelIntent(bufferedText)) {
      const cancelIntent = {
        ...(existing || {
          active: false,
          omoTurn: false,
          runIds: [],
        }),
        allowCancel: true,
        updatedAt: now,
      }
      sessionGuards.set(sessionID, cancelIntent)
      return cancelIntent
    }
    return next
  }

  eventTextBuffers.set(sessionID, text.slice(-MAX_EVENT_TEXT_BUFFER))
  const message = event?.properties?.message
  const lmasState = updateSessionGuardFromText(sessionGuards, sessionID, text, now, { allowHandoff })
  if (text.includes(LMAS_COMPLETION) || text.includes(LMAS_CANCEL)) {
    eventTextBuffers.delete(sessionID)
  }
  if ((allowHandoff && text.includes(LMAS_HANDOFF)) || text.includes(LMAS_COMPLETION) || text.includes(LMAS_CANCEL)) return lmasState

  const existing = sessionGuards.get(sessionID)
  if (!existing?.active) {
    if (role === "user" && hasExplicitCancelIntent(text)) {
      const cancelIntent = {
        ...(existing || {
          active: false,
          omoTurn: false,
          runIds: [],
        }),
        allowCancel: true,
        updatedAt: now,
      }
      sessionGuards.set(sessionID, cancelIntent)
      return cancelIntent
    }
    return existing
  }

  if (isOmoContinuationEvent(event, text)) {
    const next = {
      ...existing,
      omoTurn: true,
      updatedAt: now,
    }
    sessionGuards.set(sessionID, next)
    return next
  }

  if (role === "user") {
    const next = {
      ...existing,
      omoTurn: false,
      allowCancel: hasExplicitCancelIntent(text),
      updatedAt: now,
    }
    sessionGuards.set(sessionID, next)
    return next
  }

  return lmasState
}

export function isOmoTodoContinuationMessage(message) {
  if (message?.info?.role !== "user") return false
  const hasInternalPart = messageHasSyntheticOrInternalPart(message)
  const text = collectTextFromMessage(message)
  if (!hasInternalPart) return looksLikeOmoContinuationDirectiveText(text)

  return text.includes(OMO_TODO_CONTINUATION) || (
    text.includes(OMO_DIRECTIVE_PREFIX)
    && (
      text.includes("TODO CONTINUATION")
      || text.includes("RALPH LOOP")
      || text.includes("BOULDER CONTINUATION")
      || text.includes("continue")
      || text.includes("Continue")
    )
  ) || (
    text.includes(OMO_INTERNAL_INITIATOR)
    && text.includes("Incomplete tasks remain in your todo list")
  ) || (
    isOmoReplyExpectingInternalText(text)
  ) || (
    isReplyExpectingSyntheticUserMessage(message, text)
  )
}

export function analyzeLmasHandoffState(messages, fallbackSessionID) {
  const activeRuns = new Map()
  const completedRunIds = []
  const cancelledRunIds = []

  messages.forEach((message, index) => {
    const text = collectTextFromMessage(message)
    if (message?.info?.role !== "user" && text.includes(LMAS_HANDOFF)) {
      for (const runId of extractRunIds(text)) {
        activeRuns.set(runId, index)
      }
    }
    if (text.includes(LMAS_COMPLETION)) {
      for (const runId of extractRunIds(text)) {
        completedRunIds.push(runId)
        activeRuns.delete(runId)
      }
    }
    if (text.includes(LMAS_CANCEL)) {
      for (const runId of extractRunIds(text)) {
        cancelledRunIds.push(runId)
        activeRuns.delete(runId)
      }
    }
  })

  const activeRunIds = [...activeRuns.keys()]
  const firstActiveIndex = activeRuns.size > 0
    ? Math.min(...activeRuns.values())
    : -1
  const latestUserMessage = [...messages].reverse().find((message) => message?.info?.role === "user")
  const latestUserIsOmoContinuation = isOmoTodoContinuationMessage(latestUserMessage)

  return {
    active: activeRunIds.length > 0,
    activeRunIds,
    completedRunIds: unique(completedRunIds),
    cancelledRunIds: unique(cancelledRunIds),
    firstActiveIndex,
    latestUserHasCancelIntent: hasExplicitCancelIntent(collectTextFromMessage(latestUserMessage)),
    latestUserIsOmoContinuation,
    latestUserIsRealUser: Boolean(latestUserMessage) && !latestUserIsOmoContinuation,
    sessionID: getSessionIDFromMessage(latestUserMessage)
      || getSessionIDFromMessage(messages.at(-1))
      || fallbackSessionID,
  }
}

export function createGuardText(runIds) {
  const runList = runIds.length > 0 ? runIds.join(", ") : "unknown"
  return [
    "[LMAS GUARD: ACTIVE HANDOFF]",
    `Active LMAS run(s): ${runList}`,
    "",
    "An LMAS_HANDOFF is active. This OMO internal prompt is intentionally neutralized.",
    "Do not call tools. Do not check status. Do not read logs. Do not continue the TODO loop.",
    "End this turn and wait for LMAS_COMPLETION_EVENT v1 or a direct user status request.",
  ].join("\n")
}

export function applyOmoContinuationGuard(output, sessionGuards, now = Date.now(), fallbackSessionID) {
  const messages = Array.isArray(output?.messages) ? output.messages : []
  const state = analyzeLmasHandoffState(messages, fallbackSessionID)
  const existingGuard = state.sessionID ? sessionGuards.get(state.sessionID) : undefined
  const completed = new Set([...(state.completedRunIds || []), ...(state.cancelledRunIds || [])])
  const existingRunIds = (existingGuard?.runIds || []).filter((runId) => !completed.has(runId))
  const effectiveRunIds = unique([...existingRunIds, ...state.activeRunIds])
  const effectiveActive = effectiveRunIds.length > 0

  if (!state.sessionID) return state
  const allowCancel = state.latestUserIsRealUser
    ? state.latestUserHasCancelIntent
    : existingGuard?.allowCancel === true
  sessionGuards.set(state.sessionID, {
    active: effectiveActive,
    omoTurn: effectiveActive && state.latestUserIsOmoContinuation,
    allowCancel: effectiveActive && allowCancel,
    runIds: effectiveRunIds,
    updatedAt: now,
  })

  if (!effectiveActive) {
    return {
      ...state,
      active: effectiveActive,
      activeRunIds: effectiveRunIds,
    }
  }

  const guardText = createGuardText(effectiveRunIds)
  for (let index = Math.max(state.firstActiveIndex, 0); index < messages.length; index += 1) {
    const message = messages[index]
    if (!isOmoTodoContinuationMessage(message)) continue
    for (const part of message.parts || []) {
      if (typeof part.text === "string") {
        part.text = guardText
        part.synthetic = true
        part.metadata = {
          ...(part.metadata || {}),
          lmas_guard: true,
        }
      }
    }
  }

  return {
    ...state,
    active: effectiveActive,
    activeRunIds: effectiveRunIds,
  }
}

export function getActiveOmoGuard(sessionGuards, sessionID, now = Date.now()) {
  if (!sessionID) return undefined
  const guard = sessionGuards.get(sessionID)
  if (!guard) return undefined
  if (!guard.active && now - guard.updatedAt > GUARD_TTL_MS) {
    sessionGuards.delete(sessionID)
    return undefined
  }
  return guard.active && guard.omoTurn ? guard : undefined
}

export function clearSessionGuard(sessionGuards, sessionID) {
  if (!sessionID) return false
  return sessionGuards.delete(sessionID)
}

export function createBlockedToolMessage(runIds) {
  const runList = runIds?.length > 0 ? runIds.join(", ") : "unknown"
  return `LMAS handoff is active (${runList}); tool execution was blocked by LMAS guard. Stop this turn and wait for LMAS_COMPLETION_EVENT v1.`
}

function normalizeToolName(toolName) {
  return String(toolName || "").trim().replace(/^mcp_/i, "").toLowerCase()
}

export function createGuardedToolArgs(toolName, existingArgs, runIds) {
  const message = createBlockedToolMessage(runIds)
  const normalizedToolName = normalizeToolName(toolName)

  if (normalizedToolName === "bash") {
    return {
      ...(existingArgs || {}),
      command: `printf '%s\\n' ${JSON.stringify(message)}`,
      description: "LMAS guard no-op while handoff is active",
      timeout: 10000,
    }
  }

  if (normalizedToolName === "read") {
    return {
      filePath: "/dev/null",
      offset: 0,
      limit: 1,
    }
  }

  if (normalizedToolName === "grep") {
    return {
      pattern: "__LMAS_GUARD_NO_MATCH__",
      path: "/dev/null",
      output_mode: "content",
      head_limit: 1,
    }
  }

  if (normalizedToolName === "glob") {
    return {
      pattern: "__LMAS_GUARD_NO_MATCH__",
    }
  }

  return undefined
}

export function createGuardedToolAction(toolName, existingArgs, runIds) {
  const args = createGuardedToolArgs(toolName, existingArgs, runIds)
  if (args) return { type: "args", args }

  return {
    type: "block",
    message: createBlockedToolMessage(runIds),
  }
}
