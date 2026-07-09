# Changelog

All notable changes to Let My Agent Sleep are documented here.

## 0.2.7 - 2026-07-09

### Added

- Added `lmas_cancel` support across the CLI and OpenCode plugin, including cancellation events and smoke coverage.
- Added protocol documentation and packaged-asset checks for the `LMAS_CANCEL v1` event contract.
- Added `lmas doctor` diagnostics for OpenCode installs, plugin order, OMO continuation configuration, plugin cache state, and live tool exposure.
- Added GitHub Actions release automation for npm trusted publishing and GitHub release creation.
- Added `npm run release:check` to enforce local version, npm version, changelog, smoke, site, pack, and patch hygiene checks before pushing release automation.
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
- Added run operations docs covering status, progress, notification, cancellation, and runtime files.
- Added site docs verification for canonical URLs, sitemap coverage, local links, and demo/social assets.
- Added a PNG social preview card and site verification for Open Graph, Twitter, and JSON-LD metadata.

### Changed

- OpenCode installs now load `let-my-agent-sleep@latest` before continuation plugins and disable a broader set of known Oh My OpenAgent continuation hooks by default.
- The OpenCode runtime guard now no-ops reply-expecting prompt injection into a session with an active `LMAS_HANDOFF v1`, while still allowing `noReply` notifications and `LMAS_COMPLETION_EVENT v1`.
- OpenCode auth handling now uses the same username/password behavior in the adapter and doctor checks.
- Release CI now uses `npm ci`, Node 24, full smoke tests, pack dry runs, and patch hygiene checks over the pushed or PR change range.
- Release CI now checks site docs before publishing and uses the same `npm run pack` path as local release checks.
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

## 0.2.6 and earlier

- Established the initial npm package, CLI alias (`lmas`), OpenCode plugin, Codex skill/plugin assets, Claude Code experimental assets, tmux-backed handoff runner, completion event injection, and no-poll skill instructions.
