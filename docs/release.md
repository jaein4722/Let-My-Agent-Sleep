# Release

This project publishes `let-my-agent-sleep` from GitHub Actions with npm trusted publishing.

## Before pushing a release

Run the release check:

```bash
npm run release:check
```

This checks:

- Local `packages/let-my-agent-sleep/package.json` version.
- Current npm version from `npm view let-my-agent-sleep version`.
- Local version is newer than the npm version.
- `CHANGELOG.md` and `packages/let-my-agent-sleep/CHANGELOG.md` contain a dated release heading, not `Unreleased`.
- `npm run test:site`.
- `npm run test:smoke`.
- `npm run pack`.
- `git diff --check`.

Only push a release version after `npm run release:check` passes.

## npm trusted publisher

The npm package must have a trusted publisher configured in npm package settings:

- Provider: GitHub Actions
- Repository owner: `jaein4722`
- Repository name: `Let-My-Agent-Sleep`
- Workflow filename: `publish.yml`
- Package: `let-my-agent-sleep`

The filename should be the workflow file name only, not the full `.github/workflows/publish.yml` path.

The workflow already grants the required `id-token: write` permission and uses Node 24 with npm from GitHub Actions.

## Publish flow

Pushing to `master` triggers `.github/workflows/publish.yml` when either of these files changes:

- `packages/let-my-agent-sleep/package.json`
- `.github/workflows/publish.yml`

The workflow:

1. Reads the local package version.
2. Checks whether `let-my-agent-sleep@<version>` already exists on npm.
3. Checks whether GitHub release `v<version>` already exists.
4. When npm publish is needed, verifies the local version is newer than npm latest. When publish or release creation is needed, verifies both changelogs contain a dated release heading.
5. Runs site docs checks and smoke tests when npm publish or GitHub release creation is needed.
6. Runs an npm pack dry run before publishing.
7. Publishes to npm when the version is not already published.
8. Creates GitHub release `v<version>` when it does not already exist.

This means the workflow is idempotent for an already-published npm version. If npm publish succeeded but the GitHub release failed, rerunning the workflow should skip npm publish and create the missing release.

## After publish

Verify the npm version:

```bash
npm view let-my-agent-sleep version
```

Verify install behavior from the registry:

```bash
npx let-my-agent-sleep@latest install --agent opencode --dry-run --yes
```

For an OpenCode environment, run:

```bash
lmas doctor --agent opencode
lmas doctor --agent opencode --server-url http://127.0.0.1:4096
lmas doctor --agent opencode --server-url http://127.0.0.1:4096 --directory "$PWD"
```

If the OpenCode server requires authentication:

```bash
LMAS_OPENCODE_PASSWORD=<password> lmas doctor --agent opencode --server-url http://127.0.0.1:4096
```
