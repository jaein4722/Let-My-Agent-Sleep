#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

cd "$ROOT" || exit 1

node --input-type=module - <<'JS'
import { readFileSync } from "node:fs"
import { omoContinuationHooks } from "./packages/let-my-agent-sleep/src/omo-constants.js"

const expectedDisabledHooks = [
  "todo-continuation-enforcer",
  "model-fallback",
  "runtime-fallback",
  "ralph-loop",
  "ulw-loop",
  "ultrawork",
  "start-work-continuation",
  "boulder-continuation",
  "unstable-agent-babysitter",
  "atlas",
]

const intentionallyNotDisabledHooks = [
  "start-work",
  "stop-continuation-guard",
  "background-notification",
  "compaction-context-injector",
  "compaction-todo-preserver",
]

const actual = new Set(omoContinuationHooks)
for (const hook of expectedDisabledHooks) {
  if (!actual.has(hook)) {
    throw new Error(`OMO continuation hook policy is missing disabled hook: ${hook}`)
  }
}

for (const hook of intentionallyNotDisabledHooks) {
  if (actual.has(hook)) {
    throw new Error(`OMO continuation hook policy disables too broadly: ${hook}`)
  }
}

if (actual.size !== expectedDisabledHooks.length) {
  throw new Error(`OMO continuation hook policy has unexpected hooks: ${omoContinuationHooks.join(", ")}`)
}

for (const readmePath of ["README.md", "packages/let-my-agent-sleep/README.md"]) {
  const readme = readFileSync(readmePath, "utf8")
  for (const text of [
    "LMAS leaves Oh My OpenAgent continuation hooks enabled by default",
    "LMAS does not globally disable OMO continuation features",
    "--disable-omo-continuation",
  ]) {
    if (!readme.includes(text)) {
      throw new Error(`${readmePath} does not document default OMO continuation policy: ${text}`)
    }
  }
}

const opencodeSiteDocs = readFileSync("site/docs/opencode.html", "utf8")
for (const text of [
  "LMAS leaves Oh My OpenAgent continuation hooks enabled by default",
  "LMAS does not globally disable OMO continuation features",
  "<code>--disable-omo-continuation</code>",
]) {
  if (!opencodeSiteDocs.includes(text)) {
    throw new Error(`site/docs/opencode.html does not document default OMO continuation policy: ${text}`)
  }
}
JS

printf 'ok omo hook policy\n'
