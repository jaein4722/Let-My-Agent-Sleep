# Release

This project publishes `let-my-agent-sleep` from GitHub Actions with npm trusted publishing.

## Before pushing a release

Check the package version:

```bash
node -p "require('./packages/let-my-agent-sleep/package.json').version"
```

Check the current npm version:

```bash
npm view let-my-agent-sleep version
```

Only push a release version when the local package version is newer than the npm version.
Update `CHANGELOG.md` and `packages/let-my-agent-sleep/CHANGELOG.md` for the release candidate before pushing. The release heading should use the published version and release date, not `Unreleased`.

Run the local checks:

```bash
npm run test:site
npm run test:smoke
npm run pack
git diff --check
```

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
4. Runs site docs checks and smoke tests when npm publish or GitHub release creation is needed.
5. Runs an npm pack dry run before publishing.
6. Publishes to npm when the version is not already published.
7. Creates GitHub release `v<version>` when it does not already exist.

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
```

If the OpenCode server requires authentication:

```bash
LMAS_OPENCODE_PASSWORD=<password> lmas doctor --agent opencode --server-url http://127.0.0.1:4096
```
