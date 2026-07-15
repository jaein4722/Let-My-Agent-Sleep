# LMAS Session Handoff - 2026-07-10

This document is for the next coding agent session. It summarizes the current repository state, user intent, major decisions, and local changes that must be preserved.

## Immediate Instructions

- Do not push, publish, or create a release unless the user explicitly asks.
- Current local changes are intended to be collected into a later `0.3.2` patch.
- Do not reintroduce global disabling of Oh My OpenAgent/OMO continuation hooks.
- Do not replace the SVG-derived social card with a newly designed raster image.
- Do not restore the README demo GIF or its generator script.
- Keep commits grouped by feature, not by tiny cosmetic fragments.

## Project

The project is now named **Let My Agent Sleep** (`let-my-agent-sleep`, CLI alias `lmas`).

Core idea:

> Start long jobs. Stop the loop. Resume the same agent session when they finish.

LMAS lets agents start long-running jobs such as training, evaluation, preprocessing, migration, benchmark, or batch commands without polling logs or repeatedly continuing while the job is still running.

The protocol uses:

- `LMAS_HANDOFF v1`: emitted after a long job is safely started. The agent must stop the current turn and must not poll.
- `LMAS_COMPLETION_EVENT v1`: emitted after the watched command exits. The target agent session receives the result prompt or a fallback prompt is recorded.

## Current Release Context

The last pushed/published release before this handoff is `0.3.1`.

The working tree has local `0.3.2` changes that are not committed, not pushed, and not published.

Current branch state when this handoff was written:

```text
master...origin/master
```

Current local changes include:

- `CHANGELOG.md`
- `README.md`
- `package-lock.json`
- `packages/let-my-agent-sleep/CHANGELOG.md`
- `packages/let-my-agent-sleep/README.md`
- `packages/let-my-agent-sleep/bin/lmas-install.js`
- `packages/let-my-agent-sleep/codex-plugin/let-my-agent-sleep/.codex-plugin/plugin.json`
- `packages/let-my-agent-sleep/package.json`
- deleted `scripts/render-demo-gif.sh`
- deleted `site/demo.gif`
- `site/docs/opencode.html`
- `site/social-card.png`
- several smoke/site tests

## High-Level Timeline

The project started as **LongBridge**, a lightweight handoff protocol for long-running agent work. It was renamed to **Let My Agent Sleep** after the npm package name `longbridge` was found to already exist.

Main evolution:

1. Prototype shell wrapper and watcher.
2. OpenCode primary support.
3. Codex secondary support.
4. npm packaging with installer and `lmas` alias.
5. tmux became a required dependency for consistent out-of-sandbox process behavior.
6. OpenCode plugin integration was refined.
7. Codex resume behavior was validated using `CODEX_THREAD_ID`.
8. Claude Code support was added as experimental only.
9. Cancel/status/doctor/package tests were added.
10. OMO continuation interaction was investigated and fixed with runtime guards instead of global feature disabling.
11. Landing page, README, SEO, and social-card assets were improved.

## Agent Support Status

### OpenCode

OpenCode is the primary target.

Important behavior:

- OpenCode plugin tools are expected to provide `lmas_start`, `lmas_status`, and related LMAS behavior.
- OpenCode `serve` must be alive for native prompt injection behavior.
- If OpenCode plugin loading fails in an old session, a fresh OpenCode session may load correctly even when the stale session insists the tool is missing.
- The user has seen a bad OpenCode session fail to recognize tools while a new session recognized them correctly.

OpenCode local verification has succeeded multiple times, including via local server ports such as `4096` and `45137`.

### Codex

Codex persisted-thread resume works, but an already-running client has a verified stale-context boundary.

Important behavior:

- Codex can resume by thread/session ID.
- In Codex CLI environments, `CODEX_THREAD_ID` has been observed and used.
- The watcher can run `codex exec resume` or equivalent resume logic from tmux after the original interactive agent process is gone.
- The process runs inside tmux, which is why tmux is now a hard requirement.
- A Codex Desktop-created thread accepted an external CLI turn and displayed it in the persisted thread, but the next Desktop turn could not recall the injected marker. UI visibility does not mean the already-running app-server rebased its model-visible context.
- Reload or reopen a Codex Desktop task or CLI TUI before continuing after an external completion.

Codex behavior was tested with short and long LMAS jobs, including a 20-minute resource-trace job. Completion events were delivered. Later direct active-session tests established that restart/reopen is a correctness requirement, not merely a display refresh workaround.

### Claude Code

Claude Code support is experimental.

Do not present Claude support as guaranteed. The main uncertainty is session history/front-end silo behavior, especially with Desktop app, CLI, VS Code, and remote SSH surfaces potentially maintaining separate recents/session mappings.

The package should keep Claude wording as experimental and avoid guarantees about native Desktop session injection.

## OMO / Continuation Guard Decision

This is the most sensitive recent design area.

The user explicitly rejected globally disabling OMO continuation hooks. The reason is that users install OMO for those continuation features, and LMAS must not turn them off outside LMAS handoff windows.

Correct policy:

- Keep OMO continuation hooks enabled by default.
- Do not write OMO `disabled_hooks` settings.
- Do not expose `--disable-omo-continuation` or `--keep-omo-continuation`.
- Block reply-expecting continuation prompts only while an `LMAS_HANDOFF v1` is active in the same OpenCode session.
- Allow LMAS completion prompts and internal `noReply` notifications.
- Once completion/cancel/lost cleanup occurs, normal OMO behavior should resume.

The `0.3.2` local changes remove the global disable installer path entirely.

## README / Website / Assets

The README is consumer-facing. Do not put developer-only implementation notes there unless they directly affect installation or usage.

Recent decisions:

- Remove the low-quality README demo GIF entirely.
- Delete `site/demo.gif`.
- Delete `scripts/render-demo-gif.sh`.
- Remove tests that require the demo GIF.
- Use `site/social-card.svg` as the source of truth.
- Render `site/social-card.png` directly from the checked-in SVG, without redesigning it.

The current PNG was rendered from the SVG with headless Chrome and verified as:

```text
site/social-card.png: PNG image data, 1200 x 630, 8-bit/color RGB, non-interlaced
```

Size at verification time:

```text
300K
```

## Versioning / Release Policy

The user wants version bumps to be intentional.

Important release automation policy:

- Automatic npm publish should be gated by changes to `package.json` or `publish.yml`, not arbitrary source changes.
- Do not bump version for every small source edit.
- For this batch, local changes target `0.3.2`, but do not publish until the user confirms.

Previous version discussion:

- User considered the large OMO/cancel/plugin fixes substantial enough for `0.3.0`.
- Later fixes landed through `0.3.1`.
- Current local cleanup is staged conceptually for `0.3.2`.

## Current Local 0.3.2 Changes

### Removed OMO global-disable installer behavior

Files affected include:

- `packages/let-my-agent-sleep/bin/lmas-install.js`
- `README.md`
- `packages/let-my-agent-sleep/README.md`
- `site/docs/opencode.html`
- related tests

Removed or changed behavior:

- Removed `--disable-omo-continuation`.
- Removed `--keep-omo-continuation`.
- Removed code that wrote OMO `disabled_hooks`.
- Doctor/test wording now reflects that LMAS does not manage OMO hooks globally.

Intentional test behavior:

- Tests may still mention `--disable-omo-continuation` only to assert that the removed argument fails as unknown.

### Removed demo GIF

Files affected include:

- deleted `site/demo.gif`
- deleted `scripts/render-demo-gif.sh`
- `README.md`
- `packages/let-my-agent-sleep/README.md`
- `tests/site/check-site.py`
- `tests/smoke/test-packaged-assets.sh`
- `tests/smoke/test-package-metadata.sh`
- `tests/smoke/test-packed-tarball-cli.sh`

### Re-rendered social card PNG

File affected:

- `site/social-card.png`

The PNG should remain a direct render of `site/social-card.svg`.

## Verification Already Run

After the asset cleanup and 0.3.2 local changes, the following passed:

```text
npm run test:syntax
npm run test:site
tests/smoke/test-packaged-assets.sh
tests/smoke/test-package-metadata.sh
tests/smoke/test-packed-tarball-cli.sh
npm run test:smoke
```

Note:

- `tests/smoke/test-packed-tarball-cli.sh` fails inside the sandbox because tmux socket creation is not permitted.
- The same test passed when run outside the sandbox.
- Full `npm run test:smoke` also passed outside the sandbox.

Final full smoke output included:

```text
ok basic handoff
ok success completion
ok failed completion
ok status/list
ok cancel
ok omo hook policy
ok omo guard
ok opencode plugin guard
ok opencode plugin real import
ok packed opencode plugin import
ok opencode adapter
ok codex adapter
ok claude adapter
ok doctor
ok publish workflow gate
ok installer dry-run
ok idempotent install
ok opencode legacy cleanup
ok package metadata: 0.3.2
ok packaged assets
ok packed tarball cli
```

## Useful Commands

Check local state:

```bash
git status --short --branch
git diff --stat
```

Check removed references:

```bash
rg -n "demo\\.gif|render-demo-gif" README.md packages/let-my-agent-sleep/README.md site tests scripts
rg -n "disable-omo|keep-omo|disabled_hooks|Oh My OpenAgent continuation configured" packages/let-my-agent-sleep/bin packages/let-my-agent-sleep/src README.md packages/let-my-agent-sleep/README.md site/docs/opencode.html
```

Expected:

- No consumer/product references to demo GIF or render script.
- No product/user-doc references to global OMO disable.

Run focused tests:

```bash
npm run test:syntax
npm run test:site
tests/smoke/test-packaged-assets.sh
tests/smoke/test-package-metadata.sh
tests/smoke/test-packed-tarball-cli.sh
```

Run full smoke outside sandbox:

```bash
npm run test:smoke
```

## Communication Notes

The user is technically precise and strongly prefers concrete evidence over speculative explanations.

Avoid:

- Guessing about OpenCode/OMO internals without verifying.
- Saying “this is probably” when local inspection or direct testing is possible.
- Pushing before showing the result when the user asks to review first.
- Splitting trivial README/cosmetic changes into many tiny commits.
- Reintroducing global disable behavior under a different name.

Prefer:

- Inspecting actual files, local server state, package contents, and tests.
- Reporting exact commands and outcomes.
- Keeping consumer README clean.
- Keeping internal/developer details in `docs/`.
- Making one coherent commit for a coherent feature/fix batch.

## Next Likely Steps

1. Re-check `git diff` carefully.
2. Decide whether the current local patch should be one `0.3.2` commit.
3. If the user approves, commit only after reviewing the final diff.
4. Push only if explicitly requested.
5. Publish only if explicitly requested or if the release automation is intentionally triggered through the version/package metadata path.
