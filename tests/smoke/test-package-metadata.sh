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
const rootReadmePath = path.join(root, "README.md")
const rootLicensePath = path.join(root, "LICENSE")
const packageLicensePath = path.join(root, "packages/let-my-agent-sleep/LICENSE")
const publicSiteBase = "https://jaein4722.github.io/Let-My-Agent-Sleep/"
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"))
const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"))
const readme = fs.readFileSync(readmePath, "utf8")
const rootReadme = fs.readFileSync(rootReadmePath, "utf8")

function assert(condition, message) {
  if (!condition) {
    console.error(message)
    process.exit(1)
  }
}

function sitePathForPublicUrl(url) {
  const parsed = new URL(url)
  assert(parsed.href.startsWith(publicSiteBase), `unexpected public site URL: ${url}`)
  let relative = parsed.pathname.replace(/^\/Let-My-Agent-Sleep\/?/, "")
  if (relative === "" || relative.endsWith("/")) relative = path.join(relative, "index.html")
  return path.join(root, "site", relative)
}

function assertReadmeUrlBackedBySiteAsset(label, content, url, minBytes) {
  assert(content.includes(url), `${label} should include ${url}`)
  const sitePath = sitePathForPublicUrl(url)
  assert(fs.existsSync(sitePath), `${label} URL is not backed by a site asset: ${url}`)
  assert(fs.statSync(sitePath).size >= minBytes, `site asset for ${url} is unexpectedly small`)
}

function assertReadmePublicUrlsBackedBySite(label, content) {
  const urls = new Set()
  const pattern = /https:\/\/jaein4722\.github\.io\/Let-My-Agent-Sleep\/[^\s)"'<>]*/g
  for (const match of content.matchAll(pattern)) {
    urls.add(match[0])
  }
  assert(urls.size > 0, `${label} should include public site URLs`)

  for (const url of urls) {
    const sitePath = sitePathForPublicUrl(url)
    assert(fs.existsSync(sitePath), `${label} public URL is not backed by a site file: ${url}`)
  }
}

function assertRootReadmeSiteAsset(relativePath, minBytes) {
  assert(rootReadme.includes(relativePath), `root README should include ${relativePath}`)
  const sitePath = path.join(root, relativePath)
  assert(fs.existsSync(sitePath), `root README local site asset is missing: ${relativePath}`)
  assert(fs.statSync(sitePath).size >= minBytes, `root README local site asset is unexpectedly small: ${relativePath}`)
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
assertReadmeUrlBackedBySiteAsset("npm README", readme, "https://jaein4722.github.io/Let-My-Agent-Sleep/social-card.png", 10_000)
assertReadmeUrlBackedBySiteAsset("npm README", readme, "https://jaein4722.github.io/Let-My-Agent-Sleep/demo.gif", 10_000)
assertReadmePublicUrlsBackedBySite("npm README", readme)
assertReadmePublicUrlsBackedBySite("root README", rootReadme)
assertRootReadmeSiteAsset("site/social-card.png", 10_000)
assertRootReadmeSiteAsset("site/demo.gif", 10_000)

console.log(`ok package metadata: ${pkg.version}`)
JS
