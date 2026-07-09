#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-publish-gate.XXXXXX")
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

cd "$ROOT" || exit 1

extract_gate_script() {
  publish_needed=$1
  target=$2

  python3 - "$publish_needed" "$target" <<'PY'
from pathlib import Path
import sys

publish_needed, target = sys.argv[1:]
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
script = script.replace("${{ steps.release.outputs.version }}", "0.2.7")
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
echo 0.2.6
SH
chmod +x "$MOCK_BIN/npm"
PATH="$MOCK_BIN:$PATH" bash "$TRUE_SCRIPT"

cat > "$MOCK_BIN/npm" <<'SH'
#!/usr/bin/env sh
echo 0.2.7
SH
chmod +x "$MOCK_BIN/npm"
SAME_VERSION_OUTPUT="$TMPDIR_ROOT/same-version.out"
if PATH="$MOCK_BIN:$PATH" bash "$TRUE_SCRIPT" >"$SAME_VERSION_OUTPUT" 2>&1; then
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
