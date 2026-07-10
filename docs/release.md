# Release

This project publishes `let-my-agent-sleep` from GitHub Actions with npm trusted publishing.

## Before pushing a release

Run the release check:

```bash
npm run release:check
```

This checks:

- Local `packages/let-my-agent-sleep/package.json` version.
- Git working tree and index are clean.
- Current npm version from `npm view let-my-agent-sleep version`.
- Local version is newer than the npm version.
- `CHANGELOG.md` and `packages/let-my-agent-sleep/CHANGELOG.md` contain a dated release heading, not `Unreleased`.
- Local `@{upstream}..HEAD` includes a publish workflow trigger path: `packages/let-my-agent-sleep/package.json` or `.github/workflows/publish.yml`.
- `npm run test:syntax`.
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

The workflow already grants the required `id-token: write` permission, uses Node 24, and checks the npm trusted publishing runtime minimums before installing dependencies or publishing.

## Publish flow

Pushing to `master` triggers `.github/workflows/publish.yml` when either of these files changes:

- `packages/let-my-agent-sleep/package.json`
- `.github/workflows/publish.yml`

The workflow:

1. Reads the local package version.
2. Refuses to run from a branch other than `master`.
3. Checks whether `let-my-agent-sleep@<version>` already exists on npm. If it does, its npm `gitHead` must equal the current commit.
4. Checks whether tag and GitHub release `v<version>` already exist. Any existing tag must resolve to the current commit.
5. When npm publish is needed, verifies the local version is newer than npm latest. When publish or release creation is needed, verifies both changelogs contain a dated release heading.
6. Runs syntax, site docs, and smoke tests when npm publish or GitHub release creation is needed.
7. Runs an npm pack dry run before publishing.
8. Publishes to npm when the version is not already published.
9. Creates or verifies the exact tag, then creates GitHub release `v<version>` with `--verify-tag` when it does not already exist.

This means the workflow is idempotent only when npm, the git tag, and the workflow all refer to the same commit. If npm publish succeeded but the GitHub release failed, rerunning the same commit skips npm publish and creates the missing verified tag/release; a later commit cannot reuse that version.

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
lmas doctor --agent opencode --server-url http://127.0.0.1:4096 --workspace "<workspace-id>"
```

If the OpenCode server requires authentication:

```bash
LMAS_OPENCODE_PASSWORD=<password> lmas doctor --agent opencode --server-url http://127.0.0.1:4096
```
