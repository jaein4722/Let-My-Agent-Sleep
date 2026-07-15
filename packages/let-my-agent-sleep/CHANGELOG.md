# Changelog

All notable changes to Let My Agent Sleep are documented here.

## 0.3.3 - 2026-07-15

### Fixed

- Added an OpenCode TUI sidebar entity for current-session LMAS guard state and active/finalizing run visibility.
- Extended `lmas_info` to report current-session guard state and visible run summaries.
- Removed the OpenCode compaction autocontinue and session-compacting guard hooks; LMAS now leaves compaction/continuation ownership to OpenCode and other plugins while blocking only live reply-expecting prompts for active handoffs.
- Removed the `--disable-omo-continuation` and `--keep-omo-continuation` install options.
- Removed installer writes to Oh My OpenAgent `disabled_hooks` and `disabled_skills`; existing OMO settings are preserved byte-for-byte.
- Added a read-only doctor warning for known continuation-hook entries that may remain from an LMAS 0.3.0 install.
- Kept OMO compatibility entirely in the OpenCode runtime guard, scoped to sessions with an active `LMAS_HANDOFF v1`.
- Restricted runtime protocol learning to LMAS tools, recognized LMAS CLI commands, and session events; arbitrary tool output can no longer arm or clear a handoff guard.
- Kept the npm entry module limited to explicit OpenCode `server` and `tui` plugin exports so OpenCode does not execute test helpers as additional plugins.
- Validated protocol run IDs, removed dynamic data from guarded shell no-ops, bounded streaming buffers, and fixed split-delta handoff parsing.
- Required explicit cancel intent and an exact active run ID without overriding the user's OpenCode permission decision.
- Made completion and resume files atomic, added a handoff-start barrier, moved tmux sockets to short stable paths, and surfaced surviving cancellation processes.
- Added post-launch tmux socket/session verification so sandbox-denied socket creation cannot emit a false `LMAS_HANDOFF STARTED` before becoming `LOST`.
- Added non-Git Codex resume support, a configurable `LMAS_CODEX_BIN`, and an explicit reload/reopen requirement after external completion of an already-running Codex Desktop task or CLI TUI.
- Documented direct Codex Desktop testing that showed persisted external turns can be visible in the thread while remaining absent from the already-running app-server's model context.
- Restricted completion HTTP endpoints to `http://` or `https://` and removed model-facing notification/server URL fields from OpenCode tools.
- Pinned the OpenCode plugin spec to the exact LMAS version while leaving both legacy and versioned OpenCode cache layouts entirely under OpenCode's control.
- Stopped OpenCode-only installs from moving Codex or Claude assets, and moved Codex update backups outside the discoverable skills directory.
- Hardened publish recovery with master-only execution, npm `gitHead` and tag-SHA checks, verified-tag release creation, and clean-tree local release checks.
- Re-rendered the PNG social card directly from the checked-in SVG source.
- Removed the low-quality README demo GIF and its generator script.

## 0.3.1 - 2026-07-10

### Fixed

- Fixed OpenCode install behavior so LMAS no longer disables Oh My OpenAgent continuation hooks by default.
- Fixed `lmas doctor` so enabled OMO continuation hooks are reported as the default policy instead of a failed install.
- Clarified that LMAS blocks reply-expecting continuation only while an `LMAS_HANDOFF v1` is active in the same OpenCode session.
- Kept `--disable-omo-continuation` as an explicit opt-in for users who want to disable known OMO continuation hooks globally.
- Marked `--keep-omo-continuation` as a deprecated no-op because keeping OMO continuation hooks is now the default.

## 0.3.0 - 2026-07-10

### Added

- Hardened the existing `lmas_cancel` CLI and OpenCode plugin support with cancellation events and expanded smoke coverage.
- Added protocol documentation and packaged-asset checks for the `LMAS_CANCEL v1` event contract.
- Added `lmas doctor` diagnostics for OpenCode installs, plugin order, OMO continuation configuration, plugin cache state, and live tool exposure.
- Hardened the existing GitHub Actions release automation for npm trusted publishing and GitHub release creation.
- Expanded `npm run release:check` to enforce local version, npm version, changelog, smoke, site, pack, and patch hygiene checks before pushing release automation.
- Added smoke coverage for packaged assets, packed tarball CLI behavior, OpenCode plugin imports, OMO handoff guards, live doctor checks, and install idempotency.
- Added smoke coverage for GitHub Actions release-state detection, including already-published, missing-version, npm-error, and GitHub-release-error paths.
- Added cancel process-group cleanup, KILL fallback, and `cancel_surviving_pids` metadata when cancellation cannot fully terminate a process.
- Added smoke coverage proving adapter failures leave `resume_prompt.txt` available and keep the completed run status intact.
- Added guard regression coverage proving unrelated completion and cancel events do not clear active handoffs.
- Added `elapsed_seconds`, command summaries, and optional `progress.txt` status reporting for explicit user-requested observability without polling.
- Added secondary completion notification with `--notify <url>` and `LMAS_NOTIFY_URL`, including adapter-failure smoke coverage.
- Added `npm run test:syntax` to release and CI gates for shell and JavaScript syntax checks.
- Added a README handoff demo GIF and native-background-task comparison note.
- Added package metadata coverage that verifies npm README public site links are backed by generated site files.
- Added package metadata coverage that verifies root README public links and local site demo assets.
- Added bounded HTTP timeouts for OpenCode adapter and secondary notification completion paths.
- Added bounded timeout handling for OpenCode live doctor checks.
- Added `lmas_info` as an OpenCode plugin diagnostic tool so live doctor checks can detect stale plugin caches more reliably.
- Added `--directory` for OpenCode live doctor checks so tool exposure can be verified against the actual workspace directory.
- Added doctor coverage for legacy OpenCode package cache directories and stale root `node_modules` installs.
- Added shared OMO continuation hook constants so installer, runtime guards, and smoke tests cannot silently drift.
- Added OpenCode adapter smoke coverage that validates completion prompt injection as parseable JSON with the expected prompt text.
- Added Codex and Claude adapter smoke coverage for fallback session detection, missing-session skip behavior, and Claude `--continue` resume mode.
- Added a local release check that verifies the push range includes a publish workflow trigger path before release commits are pushed.
- Added OMO guard coverage for markerless directive continuations so OpenCode metadata differences do not bypass active handoffs.
- Added `--workspace` for OpenCode live doctor checks so workspace-scoped tool exposure can be verified on newer OpenCode servers.
- Added package-lock dependency drift coverage for the pinned OpenCode plugin dependency.
- Added OMO hook policy smoke coverage so fallback continuation hooks stay disabled without disabling broader work-starting or notification hooks.
- Added OpenCode prompt guard coverage for OMO fallback-shaped prompt payloads, live-route prompt injection, and no-reply wake notifications.
- Added packed OpenCode plugin import coverage for the compaction autocontinue guard hook.
- Added OpenCode guard coverage proving compaction autocontinue is re-enabled after LMAS cancellation clears an active handoff.
- Added packaged OpenCode plugin coverage for the `command.execute.before` guard hook.
- Added OpenCode guard coverage for part-level role fields in message payloads.
- Added OpenCode fetch guard coverage proving pass-through `Request` bodies remain intact.
- Added run operations docs covering status, progress, notification, cancellation, and runtime files.
- Added site docs verification for canonical URLs, sitemap coverage, local links, and demo/social assets.
- Added a PNG social preview card and site verification for Open Graph, Twitter, and JSON-LD metadata.

### Changed

- OpenCode installs now load `let-my-agent-sleep@latest` before continuation plugins and disable a broader set of known Oh My OpenAgent continuation hooks by default.
- OpenCode installs now disable OMO `model-fallback` and `runtime-fallback` continuation hooks by default in addition to the loop-oriented hooks.
- OpenCode installs now also disable OMO's `unstable-agent-babysitter` continuation hook by default while leaving `background-notification` available for no-reply notifications.
- OpenCode runtime continuation guards now cover the same known OMO continuation command names that the installer disables.
- The OpenCode runtime guard now no-ops reply-expecting prompt injection into a session with an active `LMAS_HANDOFF v1`, while still allowing `noReply` notifications and `LMAS_COMPLETION_EVENT v1`.
- The OpenCode runtime guard now disables compaction autocontinue while an `LMAS_HANDOFF v1` is active.
- OpenCode runtime guards now recognize camelCase and top-level session id fields in event and message payloads.
- OpenCode runtime guards now recognize top-level role fields in event and message payloads.
- OpenCode cancellation permission handshakes now recognize camelCase `callId` fields.
- OpenCode runtime guards now normalize object-shaped tool identifiers for cancellation and guarded tool no-ops.
- OpenCode plugin tools and runtime hooks now recognize camelCase `sessionId` fields in hook inputs and tool contexts.
- OpenCode session compaction now preserves active LMAS handoff state in the compaction context instead of letting summaries reframe waiting as unfinished work.
- OpenCode `chat.message` hooks now update LMAS handoff, continuation, and explicit cancel state before subsequent tool or permission hooks run.
- OpenCode system prompt transforms now preserve active LMAS handoff state when a model call still proceeds during a handoff.
- OpenCode `tool.execute.after` hooks now learn LMAS handoff, status, completion, and cancel state from CLI fallback tool output.
- OpenCode `shell.env` hooks now inject `LMAS_OPENCODE_SESSION_ID` and default `LMAS_OPENCODE_SERVER_URL` so CLI fallback runs can resume the same OpenCode session.
- OpenCode CLI fallback output tracking now treats finalizing `LMAS_CANCEL v1` responses as active stop-and-wait state until the completion event arrives.
- OpenCode auth handling now uses the same username/password behavior in the adapter and doctor checks.
- Release CI now uses `npm ci`, Node 24, full smoke tests, pack dry runs, and patch hygiene checks over the pushed or PR change range.
- Release CI now checks site docs before publishing and uses the same `npm run pack` path as local release checks.
- Syntax checks now discover every packaged JavaScript file under `bin` and `src` instead of relying on a manual file list.
- Release CI now checks npm trusted publishing runtime prerequisites before installing dependencies or publishing.
- Publish automation now rejects publish candidates that are not newer than npm latest while still allowing GitHub release recovery after npm publish succeeds.
- The package now pins `@opencode-ai/plugin` to `1.2.27` for reproducible plugin behavior.
- The npm package description and homepage now point users to the public landing page and supported-agent value proposition.

### Fixed

- Fixed OpenCode package cache refresh behavior so stale `let-my-agent-sleep` cache entries are removed during install.
- Fixed Codex plugin manifest metadata so its version matches the npm package version.
- Fixed package asset layout for Claude Code experimental command assets and Codex plugin skill wrappers.
- Fixed license metadata alignment between the repository and npm package.
- Fixed ignore coverage for generated runtime artifacts, npm pack tarballs, debug logs, and Python bytecode caches.
- Fixed OpenCode doctor checks so stale plugin cache dependency specs are reported instead of passing as merely present.
- Fixed CLI wrapper error prefixes so `doctor`, `start`, `status`, `cancel`, and `list` failures are not reported as install failures.
- Fixed multiline command and metadata recording so event and metadata files stay line-oriented while the original command still executes unchanged.
- Fixed OpenCode continuation guard state so `LMAS_CANCEL v1` clears active handoffs when seen through message history or event hooks.
- Fixed malformed run handling so `lmas status` fails clearly when `handoff.txt` is missing and `lmas list` skips incomplete run directories.
- Fixed multiline cancel reasons so cancellation metadata stays line-oriented.
- Fixed line-oriented event output for handoff, completion, status, and cancel fields.
- Fixed completion event publishing so `resume_prompt.txt` is ready before `completion_event.txt` appears.
- Fixed finalizing run handling so status/list report `FINALIZING` and cancel does not kill a job that has already exited.
- Fixed protocol and skill documentation for `FINALIZING` so agents treat it as a stop-and-wait state.
- Fixed status/list handling so staged `.completion_event.txt` files remain `FINALIZING` until the public completion event is published.
- Fixed OpenCode guard handling so `FINALIZING` status keeps continuation tools blocked like `RUNNING`.
- Fixed `lmas cancel` output so finalizing runs include the documented explanatory message.
- Fixed OpenCode history guard handling so finalizing `LMAS_CANCEL` events do not clear active handoffs before the completion event is published.
- Fixed cancellation finalizing order so duplicate cancel/status calls preserve `CANCELLED` while the public completion event is still being prepared.
- Fixed OpenCode guard handling so finalizing `LMAS_CANCEL v1` results do not unblock continuation before the completion event is published.
- Fixed OpenCode guard handling so user-pasted `LMAS_CANCEL v1` logs do not clear active handoffs.
- Fixed OpenCode `lmas_status` guard handling so active handoffs only allow status checks after an explicit user status request; non-status user follow-ups cannot accidentally reopen polling.
- Fixed OpenCode guard documentation and import smoke wording so `experimental.compaction.autocontinue` is treated as a best-effort compatibility hook, not as part of the pinned official `@opencode-ai/plugin@1.2.27` type surface.
- Fixed consumer documentation to distinguish LMAS having no daemon from the OpenCode adapter requirement that the owning OpenCode server/session must still be alive for automatic completion injection.
- Fixed the OpenCode site docs so the listed disabled Oh My OpenAgent continuation hooks match the installer behavior.
- Fixed OpenCode installs with `OPENCODE_CONFIG_FILE` so skills and Oh My OpenAgent config are written next to the selected config file instead of the default config directory.

## 0.2.6 and earlier

- Established the initial npm package, CLI alias (`lmas`), OpenCode plugin, Codex skill/plugin assets, Claude Code experimental assets, tmux-backed handoff runner, completion event injection, and no-poll skill instructions.
