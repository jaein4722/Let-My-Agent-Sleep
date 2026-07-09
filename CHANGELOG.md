# Changelog

All notable changes to Let My Agent Sleep are documented here.

## 0.2.7 - Unreleased

### Added

- Added `lmas_cancel` support across the CLI and OpenCode plugin, including cancellation events and smoke coverage.
- Added `lmas doctor` diagnostics for OpenCode installs, plugin order, OMO continuation configuration, plugin cache state, and live tool exposure.
- Added GitHub Actions release automation for npm trusted publishing and GitHub release creation.
- Added smoke coverage for packaged assets, packed tarball CLI behavior, OpenCode plugin imports, OMO handoff guards, live doctor checks, and install idempotency.

### Changed

- OpenCode installs now load `let-my-agent-sleep@latest` before continuation plugins and disable known Oh My OpenAgent continuation hooks by default.
- The OpenCode runtime guard now no-ops reply-expecting prompt injection into a session with an active `LMAS_HANDOFF v1`, while still allowing `noReply` notifications and `LMAS_COMPLETION_EVENT v1`.
- OpenCode auth handling now uses the same username/password behavior in the adapter and doctor checks.
- Release CI now uses `npm ci`, Node 24, full smoke tests, pack dry runs, and patch hygiene checks over the pushed or PR change range.
- The package now pins `@opencode-ai/plugin` to `1.2.27` for reproducible plugin behavior.

### Fixed

- Fixed OpenCode package cache refresh behavior so stale `let-my-agent-sleep` cache entries are removed during install.
- Fixed Codex plugin manifest metadata so its version matches the npm package version.
- Fixed package asset layout for Claude Code experimental command assets and Codex plugin skill wrappers.
- Fixed license metadata alignment between the repository and npm package.

## 0.2.6 and earlier

- Established the initial npm package, CLI alias (`lmas`), OpenCode plugin, Codex skill/plugin assets, Claude Code experimental assets, tmux-backed handoff runner, completion event injection, and no-poll skill instructions.
