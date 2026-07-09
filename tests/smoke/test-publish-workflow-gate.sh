#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-publish-gate.XXXXXX")
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

cd "$ROOT" || exit 1

LOCAL_VERSION=$(node -p "require('./packages/let-my-agent-sleep/package.json').version")
LOWER_VERSION=$(node - "$LOCAL_VERSION" <<'JS'
const version = process.argv[2]
const match = /^(\d+)\.(\d+)\.(\d+)([-+].*)?$/.exec(version)
if (!match) {
  throw new Error(`unsupported test version: ${version}`)
}
const major = Number(match[1])
const minor = Number(match[2])
const patch = Number(match[3])
if (patch > 0) {
  console.log(`${major}.${minor}.${patch - 1}`)
} else if (minor > 0) {
  console.log(`${major}.${minor - 1}.999`)
} else if (major > 0) {
  console.log(`${major - 1}.999.999`)
} else {
  throw new Error(`cannot derive lower version for ${version}`)
}
JS
)

extract_gate_script() {
  publish_needed=$1
  target=$2

  python3 - "$publish_needed" "$target" "$LOCAL_VERSION" <<'PY'
from pathlib import Path
import sys

publish_needed, target, local_version = sys.argv[1:]
workflow = Path(".github/workflows/publish.yml").read_text()
lines = workflow.splitlines()

start = None
for index, line in enumerate(lines):
    if line == "      - name: Check release version and changelog":
        start = index
        break

if start is None:
    raise SystemExit("publish workflow missing release version/changelog gate")

run_start = None
for index in range(start + 1, len(lines)):
    if lines[index] == "        run: |":
        run_start = index + 1
        break

if run_start is None:
    raise SystemExit("publish workflow release gate missing run block")

block = []
for line in lines[run_start:]:
    if line.startswith("      - name: "):
        break
    if line.startswith("          "):
        block.append(line[10:])
    elif line.strip() == "":
        block.append("")
    else:
        raise SystemExit(f"unexpected indentation in release gate run block: {line!r}")

script = "\n".join(block)
script = script.replace("${{ steps.release.outputs.version }}", local_version)
script = script.replace("${{ steps.release.outputs.publish_needed }}", publish_needed)
Path(target).write_text(script + "\n")
PY
}

FALSE_SCRIPT="$TMPDIR_ROOT/publish-gate-false.sh"
TRUE_SCRIPT="$TMPDIR_ROOT/publish-gate-true.sh"

extract_gate_script false "$FALSE_SCRIPT"
extract_gate_script true "$TRUE_SCRIPT"

bash -n "$FALSE_SCRIPT"
bash -n "$TRUE_SCRIPT"

MOCK_BIN="$TMPDIR_ROOT/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/npm" <<'SH'
#!/usr/bin/env sh
echo "npm should not be called when publish_needed=false" >&2
exit 99
SH
chmod +x "$MOCK_BIN/npm"
PATH="$MOCK_BIN:$PATH" bash "$FALSE_SCRIPT"

cat > "$MOCK_BIN/npm" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$LMAS_TEST_NPM_VERSION"
SH
chmod +x "$MOCK_BIN/npm"
LMAS_TEST_NPM_VERSION="$LOWER_VERSION" PATH="$MOCK_BIN:$PATH" bash "$TRUE_SCRIPT"

SAME_VERSION_OUTPUT="$TMPDIR_ROOT/same-version.out"
if LMAS_TEST_NPM_VERSION="$LOCAL_VERSION" PATH="$MOCK_BIN:$PATH" bash "$TRUE_SCRIPT" >"$SAME_VERSION_OUTPUT" 2>&1; then
  printf 'publish gate should fail when publish_needed=true and npm latest equals local version\n' >&2
  cat "$SAME_VERSION_OUTPUT" >&2
  exit 1
fi
grep -q 'must be newer than npm latest' "$SAME_VERSION_OUTPUT" || {
  printf 'publish gate failure did not explain npm latest version conflict\n' >&2
  cat "$SAME_VERSION_OUTPUT" >&2
  exit 1
}

printf 'ok publish workflow gate\n'
