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

extract_step_script() {
  step_name=$1
  target=$2

  python3 - "$step_name" "$target" <<'PY'
from pathlib import Path
import sys

step_name, target = sys.argv[1:]
workflow = Path(".github/workflows/publish.yml").read_text()
lines = workflow.splitlines()

start = None
for index, line in enumerate(lines):
    if line == f"      - name: {step_name}":
        start = index
        break

if start is None:
    raise SystemExit(f"publish workflow missing step: {step_name}")

run_start = None
for index in range(start + 1, len(lines)):
    if lines[index] == "        run: |":
        run_start = index + 1
        break

if run_start is None:
    raise SystemExit(f"publish workflow step {step_name} missing run block")

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

Path(target).write_text("\n".join(block) + "\n")
PY
}

extract_gate_script() {
  publish_needed=$1
  target=$2

  extract_step_script "Check release version and changelog" "$target"
  python3 - "$publish_needed" "$target" "$LOCAL_VERSION" <<'PY'
from pathlib import Path
import sys

publish_needed, target, local_version = sys.argv[1:]
script = Path(target).read_text()
script = script.replace("${{ steps.release.outputs.version }}", local_version)
script = script.replace("${{ steps.release.outputs.publish_needed }}", publish_needed)
Path(target).write_text(script)
PY
}

assert_release_state() {
  output_file=$1
  expected_publish=$2
  expected_release=$3

  grep -q "^version=$LOCAL_VERSION$" "$output_file" || {
    printf 'detect release state output missing version=%s\n' "$LOCAL_VERSION" >&2
    cat "$output_file" >&2
    exit 1
  }
  grep -q "^tag=v$LOCAL_VERSION$" "$output_file" || {
    printf 'detect release state output missing tag=v%s\n' "$LOCAL_VERSION" >&2
    cat "$output_file" >&2
    exit 1
  }
  grep -q "^publish_needed=$expected_publish$" "$output_file" || {
    printf 'detect release state output has wrong publish_needed value\n' >&2
    cat "$output_file" >&2
    exit 1
  }
  grep -q "^release_needed=$expected_release$" "$output_file" || {
    printf 'detect release state output has wrong release_needed value\n' >&2
    cat "$output_file" >&2
    exit 1
  }
}

run_detect_release_state() {
  npm_state=$1
  gh_state=$2
  output_file=$3
  script=$4

  : > "$output_file"
  LMAS_TEST_NPM_STATE="$npm_state" \
    LMAS_TEST_GH_STATE="$gh_state" \
    GITHUB_OUTPUT="$output_file" \
    PATH="$MOCK_BIN:$PATH" \
    GH_TOKEN=test-token \
    bash "$script" >> "$output_file" 2>&1
}

DETECT_SCRIPT="$TMPDIR_ROOT/detect-release-state.sh"
FALSE_SCRIPT="$TMPDIR_ROOT/publish-gate-false.sh"
TRUE_SCRIPT="$TMPDIR_ROOT/publish-gate-true.sh"

extract_step_script "Detect release state" "$DETECT_SCRIPT"
extract_gate_script false "$FALSE_SCRIPT"
extract_gate_script true "$TRUE_SCRIPT"

bash -n "$DETECT_SCRIPT"
bash -n "$FALSE_SCRIPT"
bash -n "$TRUE_SCRIPT"

python3 - <<'PY'
from pathlib import Path

workflow = Path(".github/workflows/publish.yml").read_text()
required = [
    "id-token: write",
    "contents: write",
    "uses: actions/checkout@v6",
    "uses: actions/setup-node@v6",
    'node-version: "24"',
    'registry-url: "https://registry.npmjs.org"',
    "package-manager-cache: false",
    "Check trusted publishing prerequisites",
    'node: "22.14.0"',
    'npm: "11.5.1"',
    "npm --version",
    "npm publish --workspace let-my-agent-sleep",
]

for text in required:
    if text not in workflow:
        raise SystemExit(f"publish workflow missing trusted publishing invariant: {text}")

for forbidden in ["NODE_AUTH_TOKEN", "NPM_TOKEN", "--otp", "always-auth"]:
    if forbidden in workflow:
        raise SystemExit(f"publish workflow should not use token/OTP publishing path: {forbidden}")
PY

MOCK_BIN="$TMPDIR_ROOT/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/npm" <<'SH'
#!/usr/bin/env sh
if [ "$1" = "view" ] && [ "$3" = "version" ]; then
  case "$LMAS_TEST_NPM_STATE" in
    published)
      printf '%s\n' "$LMAS_TEST_NPM_VERSION"
      exit 0
      ;;
    missing)
      printf 'npm error code E404\n' >&2
      printf 'npm error 404 No match found for version\n' >&2
      exit 1
      ;;
    error)
      printf 'npm error code E500\n' >&2
      exit 1
      ;;
  esac
fi
printf 'unexpected npm invocation: %s\n' "$*" >&2
exit 98
SH
chmod +x "$MOCK_BIN/npm"

cat > "$MOCK_BIN/gh" <<'SH'
#!/usr/bin/env sh
if [ "$1" = "release" ] && [ "$2" = "view" ]; then
  case "$LMAS_TEST_GH_STATE" in
    exists)
      exit 0
      ;;
    missing)
      printf 'release not found\n' >&2
      exit 1
      ;;
    error)
      printf 'gh api unavailable\n' >&2
      exit 1
      ;;
  esac
fi
printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 98
SH
chmod +x "$MOCK_BIN/gh"

DETECT_ALREADY_DONE_OUTPUT="$TMPDIR_ROOT/detect-already-done.out"
LMAS_TEST_NPM_VERSION="$LOCAL_VERSION" run_detect_release_state published exists "$DETECT_ALREADY_DONE_OUTPUT" "$DETECT_SCRIPT"
assert_release_state "$DETECT_ALREADY_DONE_OUTPUT" false false

DETECT_NEEDED_OUTPUT="$TMPDIR_ROOT/detect-needed.out"
LMAS_TEST_NPM_VERSION="$LOCAL_VERSION" run_detect_release_state missing missing "$DETECT_NEEDED_OUTPUT" "$DETECT_SCRIPT"
assert_release_state "$DETECT_NEEDED_OUTPUT" true true

DETECT_NPM_ERROR_OUTPUT="$TMPDIR_ROOT/detect-npm-error.out"
if LMAS_TEST_NPM_VERSION="$LOCAL_VERSION" run_detect_release_state error exists "$DETECT_NPM_ERROR_OUTPUT" "$DETECT_SCRIPT" 2>&1; then
  printf 'detect release state should fail on unexpected npm errors\n' >&2
  cat "$DETECT_NPM_ERROR_OUTPUT" >&2
  exit 1
fi
grep -q 'E500' "$DETECT_NPM_ERROR_OUTPUT" || {
  printf 'detect release state unexpected npm error was not surfaced\n' >&2
  cat "$DETECT_NPM_ERROR_OUTPUT" >&2
  exit 1
}

DETECT_GH_ERROR_OUTPUT="$TMPDIR_ROOT/detect-gh-error.out"
if LMAS_TEST_NPM_VERSION="$LOCAL_VERSION" run_detect_release_state published error "$DETECT_GH_ERROR_OUTPUT" "$DETECT_SCRIPT" 2>&1; then
  printf 'detect release state should fail on unexpected gh errors\n' >&2
  cat "$DETECT_GH_ERROR_OUTPUT" >&2
  exit 1
fi
grep -q 'gh api unavailable' "$DETECT_GH_ERROR_OUTPUT" || {
  printf 'detect release state unexpected gh error was not surfaced\n' >&2
  cat "$DETECT_GH_ERROR_OUTPUT" >&2
  exit 1
}

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
