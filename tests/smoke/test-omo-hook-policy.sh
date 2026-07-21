#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

cd "$ROOT" || exit 1

node --input-type=module - <<'JS'
import { readFileSync } from "node:fs"
import { omoContinuationHooks } from "./packages/let-my-agent-sleep/src/omo-constants.js"

const guardedContinuationHooks = [
  "todo-continuation-enforcer",
  "ralph-loop",
  "ulw-loop",
  "ultrawork",
  "start-work-continuation",
  "boulder-continuation",
  "unstable-agent-babysitter",
]

const intentionallyUnguardedHooks = [
  "start-work",
  "model-fallback",
  "runtime-fallback",
  "atlas",
  "stop-continuation-guard",
  "background-notification",
  "compaction-context-injector",
  "compaction-todo-preserver",
]

const actual = new Set(omoContinuationHooks)
for (const hook of guardedContinuationHooks) {
  if (!actual.has(hook)) {
    throw new Error(`OMO continuation guard policy is missing hook: ${hook}`)
  }
}

for (const hook of intentionallyUnguardedHooks) {
  if (actual.has(hook)) {
    throw new Error(`OMO continuation guard policy covers too broadly: ${hook}`)
  }
}

if (actual.size !== guardedContinuationHooks.length) {
  throw new Error(`OMO continuation hook policy has unexpected hooks: ${omoContinuationHooks.join(", ")}`)
}

for (const readmePath of ["README.md", "packages/let-my-agent-sleep/README.md"]) {
  const readme = readFileSync(readmePath, "utf8")
  for (const text of [
    "LMAS does not modify Oh My OpenAgent `disabled_hooks` or `disabled_skills`",
    "Existing OMO settings are preserved",
    "Unmarked fallback prompts, benign synthetic notifications, direct user slash commands",
  ]) {
    if (!readme.includes(text)) {
      throw new Error(`${readmePath} does not document default OMO continuation policy: ${text}`)
    }
  }
}

const opencodeSiteDocs = readFileSync("site/docs/opencode.html", "utf8")
for (const text of [
  "LMAS does not modify Oh My OpenAgent <code>disabled_hooks</code> or <code>disabled_skills</code>",
  "Existing settings are preserved",
  "Unmarked fallback prompts, benign synthetic notifications, direct user slash commands",
]) {
  if (!opencodeSiteDocs.includes(text)) {
    throw new Error(`site/docs/opencode.html does not document default OMO continuation policy: ${text}`)
  }
}
JS

printf 'ok omo hook policy\n'
