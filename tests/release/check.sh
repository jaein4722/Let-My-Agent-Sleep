#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 1

PACKAGE_JSON="packages/let-my-agent-sleep/package.json"
PACKAGE_NAME=$(node -p "require('./$PACKAGE_JSON').name")
LOCAL_VERSION=$(node -p "require('./$PACKAGE_JSON').version")

printf 'release check: %s@%s\n' "$PACKAGE_NAME" "$LOCAL_VERSION"

if ! git diff --quiet || ! git diff --cached --quiet; then
  printf 'working tree must be clean before release:check\n' >&2
  exit 1
fi

PUBLISHED_VERSION=$(npm view "$PACKAGE_NAME" version)
printf 'published version: %s@%s\n' "$PACKAGE_NAME" "$PUBLISHED_VERSION"

node - "$LOCAL_VERSION" "$PUBLISHED_VERSION" <<'JS'
const [localVersion, publishedVersion] = process.argv.slice(2)

function parseVersion(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(version)
  if (!match) {
    throw new Error(`unsupported semver version: ${version}`)
  }
  return match.slice(1, 4).map(Number)
}

const local = parseVersion(localVersion)
const published = parseVersion(publishedVersion)
const comparison = local.findIndex((part, index) => part !== published[index])
const isNewer = comparison !== -1 && local[comparison] > published[comparison]

if (!isNewer) {
  console.error(`local package version ${localVersion} must be newer than published ${publishedVersion}`)
  process.exit(1)
}
JS

for changelog in CHANGELOG.md packages/let-my-agent-sleep/CHANGELOG.md; do
  if ! grep -Fq "## $LOCAL_VERSION - " "$changelog"; then
    printf '%s does not contain a dated %s release heading\n' "$changelog" "$LOCAL_VERSION" >&2
    exit 1
  fi
  if grep -Fq "## $LOCAL_VERSION - Unreleased" "$changelog"; then
    printf '%s still marks %s as Unreleased\n' "$changelog" "$LOCAL_VERSION" >&2
    exit 1
  fi
done

if [ -z "${GITHUB_ACTIONS:-}" ]; then
  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
  if [ -z "$UPSTREAM" ]; then
    printf 'could not determine upstream branch; cannot verify publish workflow trigger path\n' >&2
    exit 1
  fi

  TRIGGER_CHANGES=$(git diff --name-only "$UPSTREAM..HEAD" -- \
    packages/let-my-agent-sleep/package.json \
    .github/workflows/publish.yml)
  if [ -z "$TRIGGER_CHANGES" ]; then
    printf 'push range %s..HEAD does not include a publish workflow trigger path\n' "$UPSTREAM" >&2
    printf 'change packages/let-my-agent-sleep/package.json or .github/workflows/publish.yml before relying on push-triggered publish automation\n' >&2
    exit 1
  fi
fi

npm run test:syntax
npm run test:site
npm run test:smoke
npm run pack
git diff --check

printf 'release check passed: %s@%s is ready to push for publish automation\n' "$PACKAGE_NAME" "$LOCAL_VERSION"
