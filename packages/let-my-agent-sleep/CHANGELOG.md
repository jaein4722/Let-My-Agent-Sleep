# Changelog

All notable changes to Let My Agent Sleep are documented here.

## 0.2.7 - 2026-07-09

### Added

- Added `lmas_cancel` support across the CLI and OpenCode plugin, including cancellation events and smoke coverage.
- Added `lmas doctor` diagnostics for OpenCode installs, plugin order, OMO continuation configuration, plugin cache state, and live tool exposure.
- Added GitHub Actions release automation for npm trusted publishing and GitHub release creation.
- Added `npm run release:check` to enforce local version, npm version, changelog, smoke, site, pack, and patch hygiene checks before pushing release automation.
- Added smoke coverage for packaged assets, packed tarball CLI behavior, OpenCode plugin imports, OMO handoff guards, live doctor checks, and install idempotency.
- Added cancel process-group cleanup, KILL fallback, and `cancel_surviving_pids` metadata when cancellation cannot fully terminate a process.
- Added smoke coverage proving adapter failures leave `resume_prompt.txt` available and keep the completed run status intact.
- Added `elapsed_seconds`, command summaries, and optional `progress.txt` status reporting for explicit user-requested observability without polling.
- Added secondary completion notification with `--notify <url>` and `LMAS_NOTIFY_URL`, including adapter-failure smoke coverage.
- Added a README handoff demo GIF and native-background-task comparison note.
- Added bounded HTTP timeouts for OpenCode adapter and secondary notification completion paths.
- Added bounded timeout handling for OpenCode live doctor checks.
- Added `lmas_info` as an OpenCode plugin diagnostic tool so live doctor checks can detect stale plugin caches more reliably.
- Added run operations docs covering status, progress, notification, cancellation, and runtime files.
- Added site docs verification for canonical URLs, sitemap coverage, local links, and demo/social assets.

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

## 0.2.6 and earlier

- Established the initial npm package, CLI alias (`lmas`), OpenCode plugin, Codex skill/plugin assets, Claude Code experimental assets, tmux-backed handoff runner, completion event injection, and no-poll skill instructions.
