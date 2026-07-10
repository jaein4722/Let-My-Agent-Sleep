#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

cd "$ROOT" || exit 1

node --input-type=module - <<'JS'
import {
  GUARD_TTL_MS,
  applyOmoContinuationGuard,
  clearSessionGuard,
  createGuardedToolAction,
  createGuardedToolArgs,
  getActiveOmoGuard,
  shouldBlockPromptInputDuringActiveHandoff,
  updateSessionGuardFromCancelText,
  updateSessionGuardFromEvent,
  updateSessionGuardFromStatusText,
  updateSessionGuardFromText,
} from "./packages/let-my-agent-sleep/src/omo-guard.js"

function message(role, text, id, sessionID = "ses_test") {
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

if (!shouldBlockPromptInputDuringActiveHandoff({
  body: {
    parts: [{ type: "text", text: "continue without an internal marker" }],
  },
})) {
  throw new Error("expected active handoff prompt guard to block markerless reply-expecting prompt")
}
if (shouldBlockPromptInputDuringActiveHandoff({
  body: {
    noReply: true,
    parts: [{ type: "text", text: "notification without reply" }],
  },
})) {
  throw new Error("did not expect active handoff prompt guard to block noReply prompt")
}
if (shouldBlockPromptInputDuringActiveHandoff({
  body: {
    parts: [{ type: "text", text: "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_done\nstatus: SUCCEEDED" }],
  },
})) {
  throw new Error("did not expect active handoff prompt guard to block LMAS completion event")
}

const activeGuards = new Map()
const activeOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_active\nstatus: STARTED", "assistant_handoff"),
    message(
      "user",
      "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]\n\nIncomplete tasks remain in your todo list. Continue working on the next pending task.\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_continue",
    ),
  ],
}
activeOutput.messages[1].parts[0].synthetic = true
activeOutput.messages[1].parts[0].metadata = { compaction_continue: true }

const activeState = applyOmoContinuationGuard(activeOutput, activeGuards, 1000)
if (!activeState.active) throw new Error("expected active LMAS handoff")
if (!activeState.latestUserIsOmoContinuation) throw new Error("expected OMO continuation as latest user")
if (!activeOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected OMO continuation to be neutralized")
}
if (!activeOutput.messages[1].parts[0].metadata?.lmas_guard) {
  throw new Error("expected guard metadata on neutralized part")
}
if (!getActiveOmoGuard(activeGuards, "ses_test", 1001)) {
  throw new Error("expected active tool guard")
}
if (!getActiveOmoGuard(activeGuards, "ses_test", 1001 + GUARD_TTL_MS + 1)) {
  throw new Error("expected active handoff guard not to expire while the LMAS run is unfinished")
}

const exactOmoContinuationPrompt = [
  "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]",
  "",
  "Incomplete tasks remain in your todo list. Continue working on the next pending task.",
  "",
  "- Proceed without asking for permission",
  "- Mark each task complete when finished",
  "- Do not stop until all tasks are done",
  "- If you believe all work is already complete, the system is questioning your completion claim. Critically re-examine each todo item from a skeptical perspective, verify the work was actually done correctly, and update the todo list accordingly.",
  "",
  "[Status: 1/2 completed, 1 remaining]",
  "",
  "Remaining tasks:",
  "- [pending] inspect stdout until training completes",
  "<!-- OMO_INTERNAL_INITIATOR -->",
].join("\n")
const exactOmoOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_exact_omo\nstatus: STARTED", "exact_omo_handoff", "ses_exact_omo"),
    message("user", exactOmoContinuationPrompt, "exact_omo_continue", "ses_exact_omo"),
  ],
}
exactOmoOutput.messages[1].parts[0].synthetic = true
exactOmoOutput.messages[1].parts[0].metadata = { compaction_continue: true }
const exactOmoState = applyOmoContinuationGuard(exactOmoOutput, new Map(), 1050)
if (!exactOmoState.latestUserIsOmoContinuation) {
  throw new Error("expected exact OMO continuation prompt shape to be recognized")
}
if (!exactOmoOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected exact OMO continuation prompt shape to be neutralized")
}

const markerlessExactOmoOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_markerless_exact_omo\nstatus: STARTED", "markerless_exact_omo_handoff", "ses_markerless_exact_omo"),
    message("user", exactOmoContinuationPrompt.replace("\n<!-- OMO_INTERNAL_INITIATOR -->", ""), "markerless_exact_omo_continue", "ses_markerless_exact_omo"),
  ],
}
const markerlessExactOmoState = applyOmoContinuationGuard(markerlessExactOmoOutput, new Map(), 1055)
if (!markerlessExactOmoState.latestUserIsOmoContinuation) {
  throw new Error("expected markerless exact OMO continuation prompt shape to be recognized")
}
if (!markerlessExactOmoOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected markerless exact OMO continuation prompt shape to be neutralized")
}

const markerlessSyntheticOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_markerless_synthetic\nstatus: STARTED", "markerless_synthetic_handoff", "ses_markerless_synthetic"),
    message("user", "Continue working on the remaining task.", "markerless_synthetic_continue", "ses_markerless_synthetic"),
  ],
}
markerlessSyntheticOutput.messages[1].parts[0].synthetic = true
const markerlessSyntheticState = applyOmoContinuationGuard(markerlessSyntheticOutput, new Map(), 1060)
if (!markerlessSyntheticState.latestUserIsOmoContinuation) {
  throw new Error("expected markerless synthetic user continuation to be recognized")
}
if (!markerlessSyntheticOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected markerless synthetic user continuation to be neutralized")
}

const markerlessNoReplyOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_markerless_noreply\nstatus: STARTED", "markerless_noreply_handoff", "ses_markerless_noreply"),
    message("user", "Internal notification only.\n<!-- OMO_INTERNAL_NOREPLY -->", "markerless_noreply", "ses_markerless_noreply"),
  ],
}
markerlessNoReplyOutput.messages[1].parts[0].synthetic = true
const markerlessNoReplyState = applyOmoContinuationGuard(markerlessNoReplyOutput, new Map(), 1070)
if (markerlessNoReplyState.latestUserIsOmoContinuation) {
  throw new Error("did not expect no-reply synthetic user notification to be treated as continuation")
}
if (markerlessNoReplyOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect no-reply synthetic user notification to be neutralized")
}

const sourceBackedContinuationFixtures = [
  {
    name: "model-fallback continue",
    text: "continue",
  },
  {
    name: "runtime-fallback continue",
    text: "continue",
  },
  {
    name: "ralph-loop continuation",
    text: "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - RALPH LOOP]\nContinue the loop.",
  },
  {
    name: "todo-continuation-enforcer continuation",
    text: exactOmoContinuationPrompt,
  },
  {
    name: "atlas boulder continuation",
    text: "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - BOULDER CONTINUATION]\nContinue the next plan step.",
  },
  {
    name: "atlas idle completion nudge",
    text: "You have unfinished Boulder work. Continue now.",
  },
]

for (const fixture of sourceBackedContinuationFixtures) {
  const sessionID = `ses_source_backed_${fixture.name.replace(/[^a-z0-9]+/gi, "_")}`
  const output = {
    messages: [
      message(
        "assistant",
        `LMAS_HANDOFF v1\nrun_id: lmas_${fixture.name.replace(/[^a-z0-9]+/gi, "_")}\nstatus: STARTED`,
        `${sessionID}_handoff`,
        sessionID,
      ),
      message(
        "user",
        `${fixture.text}\n<!-- OMO_INTERNAL_INITIATOR -->`,
        `${sessionID}_continuation`,
        sessionID,
      ),
    ],
  }
  output.messages[1].parts[0].synthetic = true
  output.messages[1].parts[0].metadata = { compaction_continue: true }

  const state = applyOmoContinuationGuard(output, new Map(), 1075)
  if (!state.latestUserIsOmoContinuation) {
    throw new Error(`expected ${fixture.name} fixture to be classified as OMO continuation`)
  }
  if (!output.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
    throw new Error(`expected ${fixture.name} fixture to be neutralized`)
  }
}

const sourceBackedNoReplyRecoveryOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_source_backed_noreply\nstatus: STARTED", "source_backed_noreply_handoff", "ses_source_backed_noreply"),
    message(
      "user",
      "Restore checkpointed session agent configuration.\n<!-- OMO_INTERNAL_INITIATOR -->\n<!-- OMO_INTERNAL_NOREPLY -->",
      "source_backed_noreply",
      "ses_source_backed_noreply",
    ),
  ],
}
sourceBackedNoReplyRecoveryOutput.messages[1].parts[0].synthetic = true
sourceBackedNoReplyRecoveryOutput.messages[1].parts[0].metadata = { compaction_continue: true }
const sourceBackedNoReplyState = applyOmoContinuationGuard(sourceBackedNoReplyRecoveryOutput, new Map(), 1076)
if (sourceBackedNoReplyState.latestUserIsOmoContinuation) {
  throw new Error("did not expect source-backed no-reply recovery fixture to be classified as OMO continuation")
}
if (sourceBackedNoReplyRecoveryOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect source-backed no-reply recovery fixture to be neutralized")
}

const realUserAfterOmoOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_active\nstatus: STARTED", "assistant_handoff"),
    message(
      "user",
      "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]\n\nIncomplete tasks remain in your todo list. Continue working on the next pending task.\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_continue",
    ),
    message("user", "Cancel the LMAS run now.", "real_user_cancel"),
  ],
}
realUserAfterOmoOutput.messages[1].parts[0].synthetic = true
const realUserAfterOmoState = applyOmoContinuationGuard(realUserAfterOmoOutput, activeGuards, 1100)
if (!realUserAfterOmoState.active) {
  throw new Error("expected active LMAS handoff to remain after real user follow-up")
}
if (realUserAfterOmoState.latestUserIsOmoContinuation) {
  throw new Error("did not expect real user follow-up to be treated as OMO continuation")
}
if (!realUserAfterOmoState.latestUserHasCancelIntent) {
  throw new Error("expected transform path to detect explicit user cancel intent")
}
if (!realUserAfterOmoOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected stale OMO continuation to stay neutralized before real user follow-up")
}
if (realUserAfterOmoOutput.messages[2].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect real user follow-up to be neutralized")
}
if (getActiveOmoGuard(activeGuards, "ses_test", 1101)) {
  throw new Error("expected real user follow-up to clear OMO tool guard while handoff remains active")
}
if (activeGuards.get("ses_test")?.allowCancel !== true) {
  throw new Error("expected real user cancel intent from transform path to allow later cancellation")
}
const cancelRevokedOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_active\nstatus: STARTED", "revoke_handoff"),
    message("user", "Do not cancel the LMAS run after all.", "revoke_cancel_user"),
  ],
}
const cancelRevokedState = applyOmoContinuationGuard(cancelRevokedOutput, activeGuards, 1105)
if (cancelRevokedState.latestUserHasCancelIntent) {
  throw new Error("did not expect later negated cancel text to count as cancel intent")
}
if (activeGuards.get("ses_test")?.allowCancel === true) {
  throw new Error("expected later real user non-cancel text to clear prior transform-path cancel permission")
}

const negatedCancelOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_negated_cancel\nstatus: STARTED", "negated_cancel_handoff", "ses_negated_cancel"),
    message("user", "Do not cancel the LMAS run. Just wait for completion.", "negated_cancel_user", "ses_negated_cancel"),
  ],
}
const negatedCancelGuards = new Map()
const negatedCancelState = applyOmoContinuationGuard(negatedCancelOutput, negatedCancelGuards, 1110)
if (negatedCancelState.latestUserHasCancelIntent) {
  throw new Error("did not expect negated cancel text to count as explicit cancel intent")
}
if (negatedCancelGuards.get("ses_negated_cancel")?.allowCancel === true) {
  throw new Error("did not expect transform path negated cancel text to allow cancellation")
}

const longAfterRealUserOmoOutput = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "long_after_real_user_omo",
    ),
  ],
}
longAfterRealUserOmoOutput.messages[0].parts[0].synthetic = true
longAfterRealUserOmoOutput.messages[0].parts[0].metadata = { compaction_continue: true }
applyOmoContinuationGuard(longAfterRealUserOmoOutput, activeGuards, 1101 + GUARD_TTL_MS + 1)
if (!getActiveOmoGuard(activeGuards, "ses_test", 1102 + GUARD_TTL_MS + 1)) {
  throw new Error("expected unfinished handoff to reactivate OMO guard after TTL-sized delay")
}

const completedGuards = new Map()
const completedOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_done\nstatus: STARTED", "assistant_handoff"),
    message("user", "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_done\nstatus: SUCCEEDED", "completion"),
    message(
      "user",
      "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]\n\nIncomplete tasks remain in your todo list. Continue working on the next pending task.\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_after_done",
    ),
  ],
}
completedOutput.messages[2].parts[0].synthetic = true
completedOutput.messages[2].parts[0].metadata = { compaction_continue: true }

const completedState = applyOmoContinuationGuard(completedOutput, completedGuards, 2000)
if (completedState.active) throw new Error("expected no active LMAS handoff after completion")
if (completedOutput.messages[2].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect guard after completion event")
}
if (getActiveOmoGuard(completedGuards, "ses_test", 2001)) {
  throw new Error("did not expect tool guard after completion event")
}

const ralphGuards = new Map()
const ralphOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_ralph\nstatus: STARTED", "assistant_handoff_ralph"),
    message(
      "user",
      "ultrawork [SYSTEM DIRECTIVE: OH-MY-OPENCODE - RALPH LOOP 2/500]\ncontinue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "ralph_continue",
    ),
  ],
}
ralphOutput.messages[1].parts[0].synthetic = true
const ralphState = applyOmoContinuationGuard(ralphOutput, ralphGuards, 3000)
if (!ralphState.active) throw new Error("expected active LMAS handoff for RALPH LOOP")
if (!ralphState.latestUserIsOmoContinuation) throw new Error("expected RALPH LOOP as OMO continuation")
if (!ralphOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected RALPH LOOP continuation to be neutralized")
}

const bareContinueGuards = new Map()
const bareContinueOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_bare_continue\nstatus: STARTED", "assistant_handoff_bare_continue"),
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "bare_continue",
    ),
  ],
}
const bareContinueState = applyOmoContinuationGuard(bareContinueOutput, bareContinueGuards, 3500)
if (!bareContinueState.latestUserIsOmoContinuation) {
  throw new Error("expected marker-only bare internal continue as OMO continuation")
}
if (!bareContinueOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected marker-only bare internal continue to be neutralized")
}

const internalPromptGuards = new Map()
const internalPromptOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_internal_prompt\nstatus: STARTED", "assistant_handoff_internal_prompt"),
    message(
      "user",
      "<system-reminder>\nBOULDER COMPLETE: plan \"demo\" is fully checked.\n</system-reminder>\n<!-- OMO_INTERNAL_INITIATOR -->",
      "internal_prompt",
    ),
  ],
}
const internalPromptState = applyOmoContinuationGuard(internalPromptOutput, internalPromptGuards, 3550)
if (!internalPromptState.latestUserIsOmoContinuation) {
  throw new Error("expected marker-only reply-expecting OMO internal prompt to be guarded")
}
if (!internalPromptOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected marker-only reply-expecting OMO internal prompt to be neutralized")
}

const noReplyGuards = new Map()
const noReplyOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_no_reply\nstatus: STARTED", "assistant_handoff_no_reply"),
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->\n<!-- OMO_INTERNAL_NOREPLY -->",
      "no_reply_continue",
    ),
  ],
}
noReplyOutput.messages[1].parts[0].synthetic = true
noReplyOutput.messages[1].parts[0].metadata = { compaction_continue: true }
const noReplyState = applyOmoContinuationGuard(noReplyOutput, noReplyGuards, 3600)
if (noReplyState.latestUserIsOmoContinuation) {
  throw new Error("did not expect no-reply internal notification to be treated as OMO continuation")
}
if (noReplyOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect no-reply internal notification to be neutralized")
}

const userGuards = new Map()
const userMentionOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_user_mention\nstatus: STARTED", "assistant_handoff_user"),
    message(
      "user",
      "Can you explain [SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION] without executing anything?",
      "real_user_mention",
    ),
  ],
}
const userMentionState = applyOmoContinuationGuard(userMentionOutput, userGuards, 4000)
if (userMentionState.latestUserIsOmoContinuation) {
  throw new Error("did not expect non-synthetic user mention to be treated as OMO continuation")
}
if (userMentionOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect real user mention to be neutralized")
}

const userMarkerPasteOutput = {
  messages: [
    message("assistant", "LMAS_HANDOFF v1\nrun_id: lmas_user_marker\nstatus: STARTED", "assistant_handoff_user_marker"),
    message(
      "user",
      "Can you explain what the OMO_INTERNAL_INITIATOR marker name means?",
      "real_user_marker_paste",
    ),
  ],
}
const userMarkerPasteState = applyOmoContinuationGuard(userMarkerPasteOutput, userGuards, 4100)
if (userMarkerPasteState.latestUserIsOmoContinuation) {
  throw new Error("did not expect ordinary user marker-name mention to be treated as OMO continuation")
}
if (userMarkerPasteOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect ordinary user marker-name mention to be neutralized")
}

const userHandoffPasteGuards = new Map()
const userHandoffPasteOutput = {
  messages: [
    message(
      "user",
      "I pasted this old log:\nLMAS_HANDOFF v1\nrun_id: lmas_user_paste\nstatus: STARTED",
      "real_user_handoff_paste",
    ),
  ],
}
const userHandoffPasteState = applyOmoContinuationGuard(userHandoffPasteOutput, userHandoffPasteGuards, 4200)
if (userHandoffPasteState.active) {
  throw new Error("did not expect user-pasted LMAS_HANDOFF to activate guard")
}
if (getActiveOmoGuard(userHandoffPasteGuards, "ses_test", 4201)) {
  throw new Error("did not expect tool guard after user-pasted LMAS_HANDOFF")
}

const eventGuards = new Map()
updateSessionGuardFromText(
  eventGuards,
  "ses_test",
  "LMAS_HANDOFF v1\nrun_id: lmas_event\nstatus: STARTED",
  5000,
)
const compactedOutput = {
  messages: [
    message(
      "user",
      "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]\n\nIncomplete tasks remain in your todo list. Continue working on the next pending task.\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_after_compaction",
    ),
  ],
}
compactedOutput.messages[0].parts[0].synthetic = true
const compactedState = applyOmoContinuationGuard(compactedOutput, eventGuards, 5001)
if (!compactedState.active) throw new Error("expected event-tracked active handoff")
if (!compactedOutput.messages[0].parts[0].text.includes("lmas_event")) {
  throw new Error("expected event-tracked run id in guard text")
}
if (!getActiveOmoGuard(eventGuards, "ses_test", 5002)) {
  throw new Error("expected active guard after event-tracked handoff")
}
updateSessionGuardFromText(
  eventGuards,
  "ses_test",
  "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_event\nstatus: SUCCEEDED",
  5003,
)
if (getActiveOmoGuard(eventGuards, "ses_test", 5004)) {
  throw new Error("expected completion event to clear event-tracked guard")
}

const eventUserTurnGuards = new Map()
const eventUserTurnBuffers = new Map()
updateSessionGuardFromText(
  eventUserTurnGuards,
  "ses_event_user_turn",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_user_turn\nstatus: STARTED",
  5100,
)
const eventUserTurnOmoOutput = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "event_user_turn_omo",
      "ses_event_user_turn",
    ),
  ],
}
eventUserTurnOmoOutput.messages[0].parts[0].synthetic = true
eventUserTurnOmoOutput.messages[0].parts[0].metadata = { compaction_continue: true }
applyOmoContinuationGuard(eventUserTurnOmoOutput, eventUserTurnGuards, 5101)
if (!getActiveOmoGuard(eventUserTurnGuards, "ses_event_user_turn", 5102)) {
  throw new Error("expected event user-turn guard to be active after OMO continuation")
}
updateSessionGuardFromEvent(eventUserTurnGuards, eventUserTurnBuffers, {
  type: "message.updated",
  properties: {
    message: message("user", "Cancel the LMAS run now.", "event_user_turn_real_user", "ses_event_user_turn"),
  },
}, 5103)
if (getActiveOmoGuard(eventUserTurnGuards, "ses_event_user_turn", 5104)) {
  throw new Error("expected message.updated real user event to clear OMO tool guard")
}
updateSessionGuardFromEvent(eventUserTurnGuards, eventUserTurnBuffers, {
  type: "message.updated",
  properties: {
    message: message(
      "user",
      "I pasted another handoff:\nLMAS_HANDOFF v1\nrun_id: lmas_should_not_be_added\nstatus: STARTED",
      "event_user_turn_handoff_paste",
      "ses_event_user_turn",
    ),
  },
}, 51045)
const eventUserTurnAfterPaste = eventUserTurnGuards.get("ses_event_user_turn")
if (eventUserTurnAfterPaste?.runIds?.includes("lmas_should_not_be_added")) {
  throw new Error("did not expect message.updated user-pasted handoff to add run id")
}
const eventUserTurnSecondOmo = message(
  "user",
  "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
  "event_user_turn_second_omo",
  "ses_event_user_turn",
)
eventUserTurnSecondOmo.parts[0].synthetic = true
eventUserTurnSecondOmo.parts[0].metadata = { compaction_continue: true }
updateSessionGuardFromEvent(eventUserTurnGuards, eventUserTurnBuffers, {
  type: "message.updated",
  properties: { message: eventUserTurnSecondOmo },
}, 5105)
if (!getActiveOmoGuard(eventUserTurnGuards, "ses_event_user_turn", 5106)) {
  throw new Error("expected message.updated OMO event to reactivate OMO tool guard")
}

const eventPartOmoGuards = new Map()
const eventPartOmoBuffers = new Map()
updateSessionGuardFromText(
  eventPartOmoGuards,
  "ses_event_part_omo",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_part_omo\nstatus: STARTED",
  5110,
)
updateSessionGuardFromEvent(eventPartOmoGuards, eventPartOmoBuffers, {
  type: "message.part.updated",
  properties: {
    sessionID: "ses_event_part_omo",
    part: {
      sessionID: "ses_event_part_omo",
      role: "user",
      synthetic: true,
      metadata: { compaction_continue: true },
      text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
    },
  },
}, 5111)
if (!getActiveOmoGuard(eventPartOmoGuards, "ses_event_part_omo", 5112)) {
  throw new Error("expected synthetic message.part.updated OMO event to activate tool guard")
}
updateSessionGuardFromEvent(eventPartOmoGuards, eventPartOmoBuffers, {
  type: "message.part.updated",
  properties: {
    sessionID: "ses_event_part_omo",
    part: {
      sessionID: "ses_event_part_omo",
      role: "user",
      text: "Cancel the LMAS run now.",
    },
  },
}, 5113)
if (getActiveOmoGuard(eventPartOmoGuards, "ses_event_part_omo", 5114)) {
  throw new Error("expected real user message.part.updated event to clear tool guard")
}

const eventDeltaOmoGuards = new Map()
const eventDeltaOmoBuffers = new Map()
updateSessionGuardFromText(
  eventDeltaOmoGuards,
  "ses_event_delta_omo",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_delta_omo\nstatus: STARTED",
  5120,
)
updateSessionGuardFromEvent(eventDeltaOmoGuards, eventDeltaOmoBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_omo",
    role: "user",
    part: {
      sessionID: "ses_event_delta_omo",
      role: "user",
      synthetic: true,
      metadata: { compaction_continue: true },
    },
    delta: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
  },
}, 5121)
if (!getActiveOmoGuard(eventDeltaOmoGuards, "ses_event_delta_omo", 5122)) {
  throw new Error("expected synthetic message.part.delta OMO event to activate tool guard")
}
updateSessionGuardFromEvent(eventDeltaOmoGuards, eventDeltaOmoBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_omo",
    role: "user",
    delta: "Cancel the LMAS run now.",
  },
}, 5123)
if (getActiveOmoGuard(eventDeltaOmoGuards, "ses_event_delta_omo", 5124)) {
  throw new Error("expected real user message.part.delta event to clear tool guard")
}

const eventDeltaTopLevelSyntheticGuards = new Map()
const eventDeltaTopLevelSyntheticBuffers = new Map()
updateSessionGuardFromText(
  eventDeltaTopLevelSyntheticGuards,
  "ses_event_delta_top_level_synthetic",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_delta_top_level_synthetic\nstatus: STARTED",
  5125,
)
updateSessionGuardFromEvent(eventDeltaTopLevelSyntheticGuards, eventDeltaTopLevelSyntheticBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_top_level_synthetic",
    role: "user",
    synthetic: true,
    metadata: { compaction_continue: true },
    delta: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
  },
}, 5126)
if (!getActiveOmoGuard(eventDeltaTopLevelSyntheticGuards, "ses_event_delta_top_level_synthetic", 5127)) {
  throw new Error("expected top-level synthetic message.part.delta OMO event to activate tool guard")
}

const eventDeltaMarkerlessSyntheticGuards = new Map()
const eventDeltaMarkerlessSyntheticBuffers = new Map()
updateSessionGuardFromText(
  eventDeltaMarkerlessSyntheticGuards,
  "ses_event_delta_markerless_synthetic",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_delta_markerless_synthetic\nstatus: STARTED",
  5128,
)
updateSessionGuardFromEvent(eventDeltaMarkerlessSyntheticGuards, eventDeltaMarkerlessSyntheticBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_markerless_synthetic",
    role: "user",
    synthetic: true,
    delta: "Continue working on the remaining task.",
  },
}, 5129)
if (!getActiveOmoGuard(eventDeltaMarkerlessSyntheticGuards, "ses_event_delta_markerless_synthetic", 5129)) {
  throw new Error("expected markerless synthetic message.part.delta OMO event to activate tool guard")
}

const eventDeltaMarkerOnlyGuards = new Map()
const eventDeltaMarkerOnlyBuffers = new Map()
updateSessionGuardFromText(
  eventDeltaMarkerOnlyGuards,
  "ses_event_delta_marker_only",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_delta_marker_only\nstatus: STARTED",
  5130,
)
updateSessionGuardFromEvent(eventDeltaMarkerOnlyGuards, eventDeltaMarkerOnlyBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_marker_only",
    role: "user",
    delta: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
  },
}, 5131)
if (!getActiveOmoGuard(eventDeltaMarkerOnlyGuards, "ses_event_delta_marker_only", 5132)) {
  throw new Error("expected marker-only message.part.delta OMO event to activate tool guard")
}

const eventDeltaMarkerlessDirectiveGuards = new Map()
const eventDeltaMarkerlessDirectiveBuffers = new Map()
updateSessionGuardFromText(
  eventDeltaMarkerlessDirectiveGuards,
  "ses_event_delta_markerless_directive",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_delta_markerless_directive\nstatus: STARTED",
  5135,
)
updateSessionGuardFromEvent(eventDeltaMarkerlessDirectiveGuards, eventDeltaMarkerlessDirectiveBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_markerless_directive",
    role: "user",
    delta: exactOmoContinuationPrompt.replace("\n<!-- OMO_INTERNAL_INITIATOR -->", ""),
  },
}, 5136)
if (!getActiveOmoGuard(eventDeltaMarkerlessDirectiveGuards, "ses_event_delta_markerless_directive", 5137)) {
  throw new Error("expected markerless OMO directive message.part.delta event to activate tool guard")
}

const eventDeltaSplitMarkerlessDirectiveGuards = new Map()
const eventDeltaSplitMarkerlessDirectiveBuffers = new Map()
updateSessionGuardFromText(
  eventDeltaSplitMarkerlessDirectiveGuards,
  "ses_event_delta_split_markerless_directive",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_delta_split_markerless_directive\nstatus: STARTED",
  5140,
)
const markerlessDirectiveText = exactOmoContinuationPrompt.replace("\n<!-- OMO_INTERNAL_INITIATOR -->", "")
const markerlessDirectiveSplit = Math.floor(markerlessDirectiveText.length / 2)
updateSessionGuardFromEvent(eventDeltaSplitMarkerlessDirectiveGuards, eventDeltaSplitMarkerlessDirectiveBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_split_markerless_directive",
    role: "user",
    delta: markerlessDirectiveText.slice(0, markerlessDirectiveSplit),
  },
}, 5141)
updateSessionGuardFromEvent(eventDeltaSplitMarkerlessDirectiveGuards, eventDeltaSplitMarkerlessDirectiveBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_split_markerless_directive",
    role: "user",
    delta: markerlessDirectiveText.slice(markerlessDirectiveSplit),
  },
}, 5142)
if (!getActiveOmoGuard(eventDeltaSplitMarkerlessDirectiveGuards, "ses_event_delta_split_markerless_directive", 5143)) {
  throw new Error("expected split markerless OMO directive message.part.delta events to activate tool guard from buffered text")
}

const eventDeltaHandoffThenMarkerlessDirectiveGuards = new Map()
const eventDeltaHandoffThenMarkerlessDirectiveBuffers = new Map()
updateSessionGuardFromEvent(eventDeltaHandoffThenMarkerlessDirectiveGuards, eventDeltaHandoffThenMarkerlessDirectiveBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_handoff_then_markerless_directive",
    role: "assistant",
    delta: "LMAS_HANDOFF v1\nrun_id: lmas_event_delta_handoff_then_markerless_directive\nstatus: STARTED",
  },
}, 5150)
updateSessionGuardFromEvent(eventDeltaHandoffThenMarkerlessDirectiveGuards, eventDeltaHandoffThenMarkerlessDirectiveBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_handoff_then_markerless_directive",
    role: "user",
    delta: markerlessDirectiveText.slice(0, markerlessDirectiveSplit),
  },
}, 5151)
updateSessionGuardFromEvent(eventDeltaHandoffThenMarkerlessDirectiveGuards, eventDeltaHandoffThenMarkerlessDirectiveBuffers, {
  type: "message.part.delta",
  properties: {
    sessionID: "ses_event_delta_handoff_then_markerless_directive",
    role: "user",
    delta: markerlessDirectiveText.slice(markerlessDirectiveSplit),
  },
}, 5152)
if (!getActiveOmoGuard(eventDeltaHandoffThenMarkerlessDirectiveGuards, "ses_event_delta_handoff_then_markerless_directive", 5153)) {
  throw new Error("expected markerless OMO directive deltas after streamed handoff delta to activate tool guard")
}

const completionOnlyGuards = new Map()
updateSessionGuardFromText(
  completionOnlyGuards,
  "ses_test",
  "LMAS_HANDOFF v1\nrun_id: lmas_completion_only\nstatus: STARTED",
  6000,
)
const completionOnlyOutput = {
  messages: [
    message(
      "user",
      "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_completion_only\nstatus: SUCCEEDED",
      "completion_only",
    ),
    message(
      "user",
      "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]\n\nIncomplete tasks remain in your todo list. Continue working on the next pending task.\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_after_completion_only",
    ),
  ],
}
completionOnlyOutput.messages[1].parts[0].synthetic = true
const completionOnlyState = applyOmoContinuationGuard(completionOnlyOutput, completionOnlyGuards, 6001)
if (completionOnlyState.active) {
  throw new Error("expected transform-visible completion to clear event-tracked active handoff")
}
if (completionOnlyOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect guard after transform-visible completion")
}
if (getActiveOmoGuard(completionOnlyGuards, "ses_test", 6002)) {
  throw new Error("did not expect tool guard after transform-visible completion")
}

const unrelatedCompletionGuards = new Map()
updateSessionGuardFromText(
  unrelatedCompletionGuards,
  "ses_unrelated_completion",
  "LMAS_HANDOFF v1\nrun_id: lmas_unrelated_completion_active\nstatus: STARTED",
  6005,
  { omoTurn: true },
)
const unrelatedCompletionOutput = {
  messages: [
    message(
      "assistant",
      "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_unrelated_completion_other\nstatus: SUCCEEDED",
      "unrelated_completion",
      "ses_unrelated_completion",
    ),
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_after_unrelated_completion",
      "ses_unrelated_completion",
    ),
  ],
}
unrelatedCompletionOutput.messages[1].parts[0].synthetic = true
const unrelatedCompletionState = applyOmoContinuationGuard(unrelatedCompletionOutput, unrelatedCompletionGuards, 6006)
if (!unrelatedCompletionState.active) {
  throw new Error("did not expect unrelated transform-visible completion to clear active handoff")
}
if (!unrelatedCompletionOutput.messages[1].parts[0].text.includes("lmas_unrelated_completion_active")) {
  throw new Error("expected guard to remain on active run after unrelated transform-visible completion")
}

const cancelOnlyGuards = new Map()
updateSessionGuardFromText(
  cancelOnlyGuards,
  "ses_cancel_only",
  "LMAS_HANDOFF v1\nrun_id: lmas_cancel_only\nstatus: STARTED",
  6010,
  { omoTurn: true },
)
const cancelOnlyOutput = {
  messages: [
    message(
      "assistant",
      "LMAS_CANCEL v1\nrun_id: lmas_cancel_only\nstatus: CANCELLED",
      "cancel_only",
      "ses_cancel_only",
    ),
    message(
      "user",
      "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]\n\nIncomplete tasks remain in your todo list. Continue working on the next pending task.\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_after_cancel_only",
      "ses_cancel_only",
    ),
  ],
}
cancelOnlyOutput.messages[1].parts[0].synthetic = true
const cancelOnlyState = applyOmoContinuationGuard(cancelOnlyOutput, cancelOnlyGuards, 6011)
if (cancelOnlyState.active) {
  throw new Error("expected transform-visible cancel to clear event-tracked active handoff")
}
if (cancelOnlyOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect guard after transform-visible cancel")
}
if (getActiveOmoGuard(cancelOnlyGuards, "ses_cancel_only", 6012)) {
  throw new Error("did not expect tool guard after transform-visible cancel")
}

const unrelatedCancelGuards = new Map()
updateSessionGuardFromText(
  unrelatedCancelGuards,
  "ses_unrelated_cancel",
  "LMAS_HANDOFF v1\nrun_id: lmas_unrelated_cancel_active\nstatus: STARTED",
  6015,
  { omoTurn: true },
)
const unrelatedCancelOutput = {
  messages: [
    message(
      "assistant",
      "LMAS_CANCEL v1\nrun_id: lmas_unrelated_cancel_other\nstatus: CANCELLED",
      "unrelated_cancel",
      "ses_unrelated_cancel",
    ),
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_after_unrelated_cancel",
      "ses_unrelated_cancel",
    ),
  ],
}
unrelatedCancelOutput.messages[1].parts[0].synthetic = true
const unrelatedCancelState = applyOmoContinuationGuard(unrelatedCancelOutput, unrelatedCancelGuards, 6016)
if (!unrelatedCancelState.active) {
  throw new Error("did not expect unrelated transform-visible cancel to clear active handoff")
}
if (!unrelatedCancelOutput.messages[1].parts[0].text.includes("lmas_unrelated_cancel_active")) {
  throw new Error("expected guard to remain on active run after unrelated transform-visible cancel")
}

const deletedSessionGuards = new Map()
updateSessionGuardFromText(
  deletedSessionGuards,
  "ses_deleted",
  "LMAS_HANDOFF v1\nrun_id: lmas_deleted\nstatus: STARTED",
  7000,
)
const deletedOutput = {
  messages: [
    message(
      "user",
      "[SYSTEM DIRECTIVE: OH-MY-OPENCODE - TODO CONTINUATION]\n\nIncomplete tasks remain in your todo list. Continue working on the next pending task.\n<!-- OMO_INTERNAL_INITIATOR -->",
      "omo_deleted",
      "ses_deleted",
    ),
  ],
}
deletedOutput.messages[0].parts[0].synthetic = true
applyOmoContinuationGuard(deletedOutput, deletedSessionGuards, 7001)
if (!getActiveOmoGuard(deletedSessionGuards, "ses_deleted", 7002)) {
  throw new Error("expected active guard before session deletion")
}
if (!clearSessionGuard(deletedSessionGuards, "ses_deleted")) {
  throw new Error("expected session guard deletion to report true")
}
if (getActiveOmoGuard(deletedSessionGuards, "ses_deleted", 7003)) {
  throw new Error("expected no guard after session deletion")
}

const bashArgs = createGuardedToolArgs("bash", { command: "cat expensive.log", timeout: 60000 }, ["lmas_args"])
if (!bashArgs.command.includes("LMAS handoff is active")) {
  throw new Error("expected bash command to be replaced by guard message")
}
if (bashArgs.timeout !== 10000) {
  throw new Error("expected guarded bash timeout")
}

const capitalBashArgs = createGuardedToolArgs("Bash", { command: "cat expensive.log", timeout: 60000 }, ["lmas_args"])
if (!capitalBashArgs.command.includes("LMAS handoff is active")) {
  throw new Error("expected capitalized Bash command to be replaced by guard message")
}

const mcpBashArgs = createGuardedToolArgs("mcp_bash", { command: "cat expensive.log", timeout: 60000 }, ["lmas_args"])
if (!mcpBashArgs.command.includes("LMAS handoff is active")) {
  throw new Error("expected mcp_bash command to be replaced by guard message")
}

const readArgs = createGuardedToolArgs("read", { filePath: "/real/file" }, ["lmas_args"])
if (readArgs.filePath !== "/dev/null") {
  throw new Error("expected read filePath to be replaced")
}

const capitalReadArgs = createGuardedToolArgs("Read", { filePath: "/real/file" }, ["lmas_args"])
if (capitalReadArgs.filePath !== "/dev/null") {
  throw new Error("expected capitalized Read filePath to be replaced")
}

const grepArgs = createGuardedToolArgs("grep", { pattern: "LMAS", path: "." }, ["lmas_args"])
if (grepArgs.pattern !== "__LMAS_GUARD_NO_MATCH__" || grepArgs.path !== "/dev/null") {
  throw new Error("expected grep args to be replaced")
}

const capitalGrepArgs = createGuardedToolArgs("Grep", { pattern: "LMAS", path: "." }, ["lmas_args"])
if (capitalGrepArgs.pattern !== "__LMAS_GUARD_NO_MATCH__" || capitalGrepArgs.path !== "/dev/null") {
  throw new Error("expected capitalized Grep args to be replaced")
}

const globArgs = createGuardedToolArgs("glob", { pattern: "**/*" }, ["lmas_args"])
if (globArgs.pattern !== "__LMAS_GUARD_NO_MATCH__") {
  throw new Error("expected glob pattern to be replaced")
}

const capitalGlobArgs = createGuardedToolArgs("Glob", { pattern: "**/*" }, ["lmas_args"])
if (capitalGlobArgs.pattern !== "__LMAS_GUARD_NO_MATCH__") {
  throw new Error("expected capitalized Glob pattern to be replaced")
}

if (createGuardedToolArgs("todowrite", { todos: [] }, ["lmas_args"]) !== undefined) {
  throw new Error("did not expect unsafe todowrite rewrite")
}

const todoAction = createGuardedToolAction("todowrite", { todos: [] }, ["lmas_args"])
if (todoAction.type !== "block" || !todoAction.message.includes("LMAS handoff is active")) {
  throw new Error("expected todowrite to be blocked while LMAS guard is active")
}

const unknownAction = createGuardedToolAction("unknown_tool", {}, ["lmas_args"])
if (unknownAction.type !== "block" || !unknownAction.message.includes("LMAS handoff is active")) {
  throw new Error("expected unknown tool to be blocked while LMAS guard is active")
}

const statusGuards = new Map()
updateSessionGuardFromStatusText(
  statusGuards,
  "ses_status",
  "LMAS_STATUS v1\nrun_id: lmas_status_running\nstatus: RUNNING\n",
  7050,
)
const runningStatusGuard = getActiveOmoGuard(statusGuards, "ses_status", 7051)
if (!runningStatusGuard || !runningStatusGuard.runIds.includes("lmas_status_running")) {
  throw new Error("expected RUNNING LMAS_STATUS to activate tool guard")
}
updateSessionGuardFromStatusText(
  statusGuards,
  "ses_status",
  "LMAS_STATUS v1\nrun_id: lmas_status_finalizing\nstatus: FINALIZING\n",
  7051,
)
const finalizingStatusGuard = getActiveOmoGuard(statusGuards, "ses_status", 7052)
if (!finalizingStatusGuard || !finalizingStatusGuard.runIds.includes("lmas_status_finalizing")) {
  throw new Error("expected FINALIZING LMAS_STATUS to keep tool guard active")
}
updateSessionGuardFromStatusText(
  statusGuards,
  "ses_status",
  "LMAS_STATUS v1\nrun_id: lmas_status_running\nrun_id: lmas_status_finalizing\nstatus: SUCCEEDED\n",
  7053,
)
if (getActiveOmoGuard(statusGuards, "ses_status", 7054)) {
  throw new Error("expected completed LMAS_STATUS to clear guarded runs")
}

const finalizingCancelGuards = new Map()
updateSessionGuardFromText(
  finalizingCancelGuards,
  "ses_finalizing_cancel",
  "LMAS_HANDOFF v1\nrun_id: lmas_finalizing_cancel\nstatus: STARTED",
  7055,
  { omoTurn: true },
)
updateSessionGuardFromCancelText(
  finalizingCancelGuards,
  "ses_finalizing_cancel",
  "LMAS_CANCEL v1\nrun_id: lmas_finalizing_cancel\nstatus: ALREADY_COMPLETED\nexisting_status: CANCELLED\nmessage: job has already exited; completion event is finalizing\n",
  7056,
)
const finalizingCancelGuard = getActiveOmoGuard(finalizingCancelGuards, "ses_finalizing_cancel", 7057)
if (!finalizingCancelGuard?.runIds?.includes("lmas_finalizing_cancel")) {
  throw new Error("expected finalizing LMAS_CANCEL result to keep guard active")
}
updateSessionGuardFromText(
  finalizingCancelGuards,
  "ses_finalizing_cancel",
  "LMAS_CANCEL v1\nrun_id: lmas_finalizing_cancel\nstatus: ALREADY_COMPLETED\nexisting_status: CANCELLED\nmessage: job has already exited; completion event is finalizing\n",
  7058,
)
if (!getActiveOmoGuard(finalizingCancelGuards, "ses_finalizing_cancel", 7059)?.runIds?.includes("lmas_finalizing_cancel")) {
  throw new Error("expected event-visible finalizing LMAS_CANCEL to keep guard active")
}

const finalizingCancelHistoryOutput = {
  messages: [
    message(
      "assistant",
      "LMAS_HANDOFF v1\nrun_id: lmas_finalizing_cancel_history\nstatus: STARTED",
      "finalizing_cancel_history_handoff",
      "ses_finalizing_cancel_history",
    ),
    message(
      "assistant",
      "LMAS_CANCEL v1\nrun_id: lmas_finalizing_cancel_history\nstatus: ALREADY_COMPLETED\nexisting_status: CANCELLED\nmessage: job has already exited; completion event is finalizing\n",
      "finalizing_cancel_history_cancel",
      "ses_finalizing_cancel_history",
    ),
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "finalizing_cancel_history_continue",
      "ses_finalizing_cancel_history",
    ),
  ],
}
finalizingCancelHistoryOutput.messages[2].parts[0].synthetic = true
finalizingCancelHistoryOutput.messages[2].parts[0].metadata = { compaction_continue: true }
const finalizingCancelHistoryState = applyOmoContinuationGuard(finalizingCancelHistoryOutput, new Map(), 7060)
if (!finalizingCancelHistoryState.active || !finalizingCancelHistoryState.activeRunIds.includes("lmas_finalizing_cancel_history")) {
  throw new Error("expected history-visible finalizing LMAS_CANCEL to keep handoff active")
}
if (!finalizingCancelHistoryOutput.messages[2].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected history-visible finalizing LMAS_CANCEL to keep OMO continuation neutralized")
}

const cancelIntentGuards = new Map()
const cancelIntentBuffers = new Map()
updateSessionGuardFromText(
  cancelIntentGuards,
  "ses_cancel_intent",
  "LMAS_HANDOFF v1\nrun_id: lmas_cancel_intent\nstatus: STARTED",
  7060,
  { omoTurn: true },
)
updateSessionGuardFromEvent(cancelIntentGuards, cancelIntentBuffers, {
  type: "message.updated",
  properties: {
    message: message("user", "Check status and cancel it if it is still running.", "cancel_intent_user", "ses_cancel_intent"),
  },
}, 7061)
updateSessionGuardFromStatusText(
  cancelIntentGuards,
  "ses_cancel_intent",
  "LMAS_STATUS v1\nrun_id: lmas_cancel_intent\nstatus: RUNNING\n",
  7062,
)
const cancelIntentGuard = getActiveOmoGuard(cancelIntentGuards, "ses_cancel_intent", 7063)
if (!cancelIntentGuard?.allowCancel || !cancelIntentGuard.runIds.includes("lmas_cancel_intent")) {
  throw new Error("expected explicit user cancel intent to survive RUNNING status guard")
}
updateSessionGuardFromCancelText(
  cancelIntentGuards,
  "ses_cancel_intent",
  "LMAS_CANCEL v1\nrun_id: lmas_cancel_intent\nstatus: CANCELLED\n",
  7064,
)
if (getActiveOmoGuard(cancelIntentGuards, "ses_cancel_intent", 7065)) {
  throw new Error("expected LMAS_CANCEL to clear run guard")
}

const eventCancelGuards = new Map()
const eventCancelBuffers = new Map()
updateSessionGuardFromText(
  eventCancelGuards,
  "ses_event_cancel",
  "LMAS_HANDOFF v1\nrun_id: lmas_event_cancel\nstatus: STARTED",
  7066,
  { omoTurn: true },
)
updateSessionGuardFromEvent(eventCancelGuards, eventCancelBuffers, {
  type: "message.updated",
  properties: {
    message: message(
      "assistant",
      "LMAS_CANCEL v1\nrun_id: lmas_event_cancel\nstatus: CANCELLED",
      "event_cancel_message",
      "ses_event_cancel",
    ),
  },
}, 7067)
if (getActiveOmoGuard(eventCancelGuards, "ses_event_cancel", 7068)) {
  throw new Error("expected event-visible LMAS_CANCEL to clear run guard")
}

const unrelatedEventCancelGuards = new Map()
const unrelatedEventCancelBuffers = new Map()
updateSessionGuardFromText(
  unrelatedEventCancelGuards,
  "ses_unrelated_event_cancel",
  "LMAS_HANDOFF v1\nrun_id: lmas_unrelated_event_cancel_active\nstatus: STARTED",
  7069,
  { omoTurn: true },
)
updateSessionGuardFromEvent(unrelatedEventCancelGuards, unrelatedEventCancelBuffers, {
  type: "message.updated",
  properties: {
    message: message(
      "assistant",
      "LMAS_CANCEL v1\nrun_id: lmas_unrelated_event_cancel_other\nstatus: CANCELLED",
      "unrelated_event_cancel_message",
      "ses_unrelated_event_cancel",
    ),
  },
}, 70695)
const unrelatedEventCancelGuard = getActiveOmoGuard(unrelatedEventCancelGuards, "ses_unrelated_event_cancel", 70696)
if (!unrelatedEventCancelGuard?.runIds?.includes("lmas_unrelated_event_cancel_active")) {
  throw new Error("did not expect unrelated event-visible LMAS_CANCEL to clear active run guard")
}

const negatedEventCancelGuards = new Map()
const negatedEventCancelBuffers = new Map()
updateSessionGuardFromText(
  negatedEventCancelGuards,
  "ses_negated_event_cancel",
  "LMAS_HANDOFF v1\nrun_id: lmas_negated_event_cancel\nstatus: STARTED",
  7070,
  { omoTurn: true },
)
updateSessionGuardFromEvent(negatedEventCancelGuards, negatedEventCancelBuffers, {
  type: "message.updated",
  properties: {
    message: message("user", "Do not cancel this run.", "negated_event_cancel_user", "ses_negated_event_cancel"),
  },
}, 7071)
updateSessionGuardFromStatusText(
  negatedEventCancelGuards,
  "ses_negated_event_cancel",
  "LMAS_STATUS v1\nrun_id: lmas_negated_event_cancel\nstatus: RUNNING\n",
  7072,
)
const negatedEventCancelGuard = getActiveOmoGuard(negatedEventCancelGuards, "ses_negated_event_cancel", 7073)
if (negatedEventCancelGuard?.allowCancel === true) {
  throw new Error("did not expect event path negated cancel text to allow cancellation")
}

const deltaSessionGuards = new Map()
const deltaEventBuffers = new Map()
updateSessionGuardFromEvent(deltaSessionGuards, deltaEventBuffers, {
  type: "message.part.delta",
  properties: { sessionID: "ses_delta", field: "text", delta: "LMAS_HAND" },
})
updateSessionGuardFromEvent(deltaSessionGuards, deltaEventBuffers, {
  type: "message.part.delta",
  properties: { sessionID: "ses_delta", field: "text", delta: "OFF v1\nrun_id: lmas_delta\nstatus: STARTED" },
})

const deltaTrackedOutput = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "delta_continue",
      "ses_delta",
    ),
  ],
}
deltaTrackedOutput.messages[0].parts[0].synthetic = true
deltaTrackedOutput.messages[0].parts[0].metadata = { compaction_continue: true }
applyOmoContinuationGuard(deltaTrackedOutput, deltaSessionGuards, 8000)
if (!deltaTrackedOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected event delta-tracked handoff to guard OMO continuation")
}

updateSessionGuardFromEvent(deltaSessionGuards, deltaEventBuffers, {
  type: "message.part.delta",
  properties: { sessionID: "ses_delta", field: "text", delta: "\nLMAS_COMPLETION_EVENT v1\nrun_id: lmas_delta\nstatus: SUCCEEDED" },
})
if (deltaEventBuffers.has("ses_delta")) {
  throw new Error("expected delta event buffer to clear after completion")
}
const deltaCompletionOutput = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "delta_after_completion",
      "ses_delta",
    ),
  ],
}
deltaCompletionOutput.messages[0].parts[0].synthetic = true
deltaCompletionOutput.messages[0].parts[0].metadata = { compaction_continue: true }
applyOmoContinuationGuard(deltaCompletionOutput, deltaSessionGuards, 8001)
if (deltaCompletionOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("did not expect event delta-tracked completion to keep OMO guard active")
}

const userDeltaHandoffGuards = new Map()
const userDeltaHandoffBuffers = new Map()
updateSessionGuardFromEvent(userDeltaHandoffGuards, userDeltaHandoffBuffers, {
  type: "message.part.delta",
  properties: { sessionID: "ses_user_delta", role: "user", field: "text", delta: "LMAS_HAND" },
})
updateSessionGuardFromEvent(userDeltaHandoffGuards, userDeltaHandoffBuffers, {
  type: "message.part.delta",
  properties: { sessionID: "ses_user_delta", role: "user", field: "text", delta: "OFF v1\nrun_id: lmas_user_delta\nstatus: STARTED" },
})
if (userDeltaHandoffGuards.get("ses_user_delta")?.runIds?.includes("lmas_user_delta")) {
  throw new Error("did not expect user-role message.part.delta handoff to add run id")
}

const userPartHandoffGuards = new Map()
const userPartHandoffBuffers = new Map()
updateSessionGuardFromEvent(userPartHandoffGuards, userPartHandoffBuffers, {
  type: "message.part.updated",
  properties: {
    sessionID: "ses_user_part",
    part: {
      role: "user",
      text: "LMAS_HANDOFF v1\nrun_id: lmas_user_part\nstatus: STARTED",
    },
  },
})
if (userPartHandoffGuards.get("ses_user_part")?.runIds?.includes("lmas_user_part")) {
  throw new Error("did not expect user-role message.part.updated handoff to add run id")
}

const messageUpdatedGuards = new Map()
const messageUpdatedBuffers = new Map()
updateSessionGuardFromEvent(messageUpdatedGuards, messageUpdatedBuffers, {
  type: "message.updated",
  properties: {
    message: message(
      "assistant",
      "LMAS_HANDOFF v1\nrun_id: lmas_message_updated\nstatus: STARTED",
      "message_updated_handoff",
      "ses_message_updated",
    ),
  },
})
const messageUpdatedOutput = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "message_updated_continue",
      "ses_message_updated",
    ),
  ],
}
messageUpdatedOutput.messages[0].parts[0].synthetic = true
messageUpdatedOutput.messages[0].parts[0].metadata = { compaction_continue: true }
applyOmoContinuationGuard(messageUpdatedOutput, messageUpdatedGuards, 8100)
if (!messageUpdatedOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected message.updated handoff with nested session id to activate guard")
}
updateSessionGuardFromEvent(messageUpdatedGuards, messageUpdatedBuffers, {
  type: "session.deleted",
  properties: { info: { id: "ses_message_updated" } },
})
if (getActiveOmoGuard(messageUpdatedGuards, "ses_message_updated", 8101)) {
  throw new Error("expected session.deleted info.id to clear guard")
}

const messageUpdatedInfoGuards = new Map()
const messageUpdatedInfoBuffers = new Map()
updateSessionGuardFromEvent(messageUpdatedInfoGuards, messageUpdatedInfoBuffers, {
  type: "message.updated",
  properties: {
    info: {
      id: "message_updated_info_handoff",
      sessionID: "ses_message_updated_info",
      role: "assistant",
      parts: [{
        id: "message_updated_info_handoff_part",
        sessionID: "ses_message_updated_info",
        type: "text",
        text: "LMAS_HANDOFF v1\nrun_id: lmas_message_updated_info\nstatus: STARTED",
      }],
    },
  },
})
const messageUpdatedInfoOutput = {
  messages: [
    message(
      "user",
      "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
      "message_updated_info_continue",
      "ses_message_updated_info",
    ),
  ],
}
messageUpdatedInfoOutput.messages[0].parts[0].synthetic = true
messageUpdatedInfoOutput.messages[0].parts[0].metadata = { compaction_continue: true }
applyOmoContinuationGuard(messageUpdatedInfoOutput, messageUpdatedInfoGuards, 8150)
if (!messageUpdatedInfoOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected message.updated properties.info with parts to activate guard")
}

updateSessionGuardFromEvent(messageUpdatedInfoGuards, messageUpdatedInfoBuffers, {
  type: "message.updated",
  properties: {
    info: {
      id: "sdk_info_only_user",
      sessionID: "ses_message_updated_info",
      role: "user",
    },
  },
}, 8151)
if (!getActiveOmoGuard(messageUpdatedInfoGuards, "ses_message_updated_info", 8152)) {
  throw new Error("expected SDK-shaped message.updated without parts not to clear active OMO guard")
}

const camelSessionGuards = new Map()
const camelSessionBuffers = new Map()
updateSessionGuardFromEvent(camelSessionGuards, camelSessionBuffers, {
  type: "message.updated",
  properties: {
    message: {
      info: {
        id: "camel_session_handoff",
        sessionId: "ses_camel_message_updated",
        role: "assistant",
      },
      parts: [{
        id: "camel_session_handoff_part",
        sessionId: "ses_camel_message_updated",
        type: "text",
        text: "LMAS_HANDOFF v1\nrun_id: lmas_camel_message_updated\nstatus: STARTED",
      }],
    },
  },
}, 8160)
const camelSessionOutput = {
  messages: [
    {
      info: { id: "camel_session_continue", sessionId: "ses_camel_message_updated", role: "user" },
      parts: [{
        id: "camel_session_continue_part",
        sessionId: "ses_camel_message_updated",
        type: "text",
        text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
        synthetic: true,
        metadata: { compaction_continue: true },
      }],
    },
  ],
}
applyOmoContinuationGuard(camelSessionOutput, camelSessionGuards, 8161)
if (!camelSessionOutput.messages[0].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected camelCase sessionId message.updated event to activate guard")
}
updateSessionGuardFromEvent(camelSessionGuards, camelSessionBuffers, {
  type: "session.deleted",
  properties: { info: { sessionId: "ses_camel_message_updated" } },
}, 8162)
if (getActiveOmoGuard(camelSessionGuards, "ses_camel_message_updated", 8163)) {
  throw new Error("expected session.deleted info.sessionId to clear guard")
}

const messageCompletionGuards = new Map()
const messageCompletionBuffers = new Map()
updateSessionGuardFromText(
  messageCompletionGuards,
  "ses_message_completion",
  "LMAS_HANDOFF v1\nrun_id: lmas_message_completion\nstatus: STARTED",
  8200,
)
updateSessionGuardFromEvent(messageCompletionGuards, messageCompletionBuffers, {
  type: "message.updated",
  properties: {
    message: message(
      "user",
      "LMAS_COMPLETION_EVENT v1\nrun_id: lmas_message_completion\nstatus: SUCCEEDED",
      "message_completion_event",
      "ses_message_completion",
    ),
  },
}, 8201)
if (messageCompletionBuffers.has("ses_message_completion")) {
  throw new Error("expected message.updated event buffer to clear after completion")
}
if (getActiveOmoGuard(messageCompletionGuards, "ses_message_completion", 8202)) {
  throw new Error("expected message.updated completion to clear guard")
}

const fallbackSessionGuards = new Map()
const fallbackSessionOutput = {
  messages: [
    {
      info: { id: "fallback_handoff", role: "assistant" },
      parts: [{
        id: "fallback_handoff_part",
        type: "text",
        text: "LMAS_HANDOFF v1\nrun_id: lmas_fallback_session\nstatus: STARTED",
      }],
    },
    {
      info: { id: "fallback_omo", role: "user" },
      parts: [{
        id: "fallback_omo_part",
        type: "text",
        text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
        synthetic: true,
        metadata: { compaction_continue: true },
      }],
    },
  ],
}
applyOmoContinuationGuard(fallbackSessionOutput, fallbackSessionGuards, 8300, "ses_fallback_transform")
if (!fallbackSessionOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected transform fallback session id to neutralize OMO continuation")
}
if (!getActiveOmoGuard(fallbackSessionGuards, "ses_fallback_transform", 8301)) {
  throw new Error("expected transform fallback session id to set active guard")
}

const partOnlySessionGuards = new Map()
const partOnlySessionOutput = {
  messages: [
    {
      info: { id: "part_only_handoff", role: "assistant" },
      parts: [{
        id: "part_only_handoff_part",
        sessionID: "ses_part_only_transform",
        type: "text",
        text: "LMAS_HANDOFF v1\nrun_id: lmas_part_only_session\nstatus: STARTED",
      }],
    },
    {
      info: { id: "part_only_omo", role: "user" },
      parts: [{
        id: "part_only_omo_part",
        sessionID: "ses_part_only_transform",
        type: "text",
        text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
        synthetic: true,
        metadata: { compaction_continue: true },
      }],
    },
  ],
}
applyOmoContinuationGuard(partOnlySessionOutput, partOnlySessionGuards, 8310)
if (!partOnlySessionOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected transform part-only session id to neutralize OMO continuation")
}
if (!getActiveOmoGuard(partOnlySessionGuards, "ses_part_only_transform", 8311)) {
  throw new Error("expected transform part-only session id to set active guard")
}

const camelPartOnlySessionGuards = new Map()
const camelPartOnlySessionOutput = {
  messages: [
    {
      info: { id: "camel_part_only_handoff", role: "assistant" },
      parts: [{
        id: "camel_part_only_handoff_part",
        sessionId: "ses_camel_part_only_transform",
        type: "text",
        text: "LMAS_HANDOFF v1\nrun_id: lmas_camel_part_only_session\nstatus: STARTED",
      }],
    },
    {
      info: { id: "camel_part_only_omo", role: "user" },
      parts: [{
        id: "camel_part_only_omo_part",
        sessionId: "ses_camel_part_only_transform",
        type: "text",
        text: "continue\n<!-- OMO_INTERNAL_INITIATOR -->",
        synthetic: true,
        metadata: { compaction_continue: true },
      }],
    },
  ],
}
applyOmoContinuationGuard(camelPartOnlySessionOutput, camelPartOnlySessionGuards, 8320)
if (!camelPartOnlySessionOutput.messages[1].parts[0].text.includes("[LMAS GUARD: ACTIVE HANDOFF]")) {
  throw new Error("expected transform camelCase part-only session id to neutralize OMO continuation")
}
if (!getActiveOmoGuard(camelPartOnlySessionGuards, "ses_camel_part_only_transform", 8321)) {
  throw new Error("expected transform camelCase part-only session id to set active guard")
}

console.log("ok omo guard")
JS
