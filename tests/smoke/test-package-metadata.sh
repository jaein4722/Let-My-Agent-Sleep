#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)

node - "$ROOT" <<'JS'
const fs = require("node:fs")
const path = require("node:path")

const root = process.argv[2]
const pkgPath = path.join(root, "packages/let-my-agent-sleep/package.json")
const lockPath = path.join(root, "package-lock.json")
const readmePath = path.join(root, "packages/let-my-agent-sleep/README.md")
const rootLicensePath = path.join(root, "LICENSE")
const packageLicensePath = path.join(root, "packages/let-my-agent-sleep/LICENSE")
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"))
const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"))
const readme = fs.readFileSync(readmePath, "utf8")

function assert(condition, message) {
  if (!condition) {
    console.error(message)
    process.exit(1)
  }
}

function assertReadmeUrlBackedBySiteAsset(url, minBytes) {
  assert(readme.includes(url), `npm README should include ${url}`)
  const sitePath = path.join(root, "site", new URL(url).pathname.replace(/^\/Let-My-Agent-Sleep\//, ""))
  assert(fs.existsSync(sitePath), `npm README URL is not backed by a site asset: ${url}`)
  assert(fs.statSync(sitePath).size >= minBytes, `site asset for ${url} is unexpectedly small`)
}

assert(pkg.name === "let-my-agent-sleep", "unexpected package name")
assert(pkg.homepage === "https://jaein4722.github.io/Let-My-Agent-Sleep/", "package homepage should point to the public landing page")
assert(pkg.description.includes("Start long-running agent jobs"), "package description should explain the user-facing value")
assert(pkg.description.includes("OpenCode") && pkg.description.includes("Codex") && pkg.description.includes("Claude Code"), "package description should name supported agents")
assert(pkg.repository?.url === "git+https://github.com/jaein4722/Let-My-Agent-Sleep.git", "repository URL drifted")
assert(pkg.bugs?.url === "https://github.com/jaein4722/Let-My-Agent-Sleep/issues", "bugs URL drifted")
assert(pkg.license === "MIT", "license drifted")
assert(pkg.bin?.lmas === "bin/lmas-install.js", "lmas bin drifted")
assert(pkg.bin?.["let-my-agent-sleep"] === "bin/lmas-install.js", "let-my-agent-sleep bin drifted")
assert(pkg.engines?.node === ">=18", "node engine drifted")
for (const keyword of ["opencode", "codex", "claude-code", "long-running-jobs", "llmops"]) {
  assert(pkg.keywords?.includes(keyword), `missing keyword: ${keyword}`)
}
for (const file of ["src", "bin", "skills", "codex-plugin", "claude/let-my-agent-sleep/commands", "claude/let-my-agent-sleep/assets", "README.md", "CHANGELOG.md", "LICENSE"]) {
  assert(pkg.files?.includes(file), `missing package files entry: ${file}`)
}
assert(lock.packages?.["packages/let-my-agent-sleep"]?.version === pkg.version, "package-lock workspace version does not match package.json")
assert(fs.readFileSync(rootLicensePath, "utf8") === fs.readFileSync(packageLicensePath, "utf8"), "package LICENSE differs from root LICENSE")
assertReadmeUrlBackedBySiteAsset("https://jaein4722.github.io/Let-My-Agent-Sleep/social-card.png", 10_000)
assertReadmeUrlBackedBySiteAsset("https://jaein4722.github.io/Let-My-Agent-Sleep/demo.gif", 10_000)

console.log(`ok package metadata: ${pkg.version}`)
JS
