#!/usr/bin/env node
import { spawnSync } from "node:child_process"
import { createInterface } from "node:readline/promises"
import { stdin as input, stdout as output } from "node:process"
import { copyFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs"
import { basename, dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { homedir } from "node:os"

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const packageJson = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"))
const packageName = packageJson.name

const paths = {
  openCodeSkill: join(packageRoot, "skills", "let-my-agent-sleep", "SKILL.md"),
  codexPlugin: join(packageRoot, "codex-plugin", "let-my-agent-sleep"),
}

function usage() {
  console.log(`Usage:
  lmas install [--agent opencode|codex|all|detected] [--yes] [--dry-run] [--force]
  lmas start [options] -- <command...>
  lmas status [--runs-dir <path>] <run_id|run_dir>
  lmas list [--runs-dir <path>]

Options:
  --agent <target>  Target agent. May be repeated or comma-separated. Default: interactive.
  --yes, -y         Use defaults without prompting.
  --dry-run         Print intended writes without changing files.
  --force           Overwrite existing Let My Agent Sleep-managed files without backup.
  --help, -h        Show this help.
`)
}

function runWrapper(argv) {
  const script = join(packageRoot, "bin", "lmas.sh")
  const result = spawnSync("bash", [script, ...argv], {
    stdio: "inherit",
    env: process.env,
  })

  if (result.error) {
    throw result.error
  }

  process.exit(result.status ?? 1)
}

function parseArgs(argv) {
  const options = {
    agents: [],
    yes: false,
    dryRun: false,
    force: false,
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === "install") continue
    if (arg === "--help" || arg === "-h") {
      usage()
      process.exit(0)
    }
    if (arg === "--yes" || arg === "-y") {
      options.yes = true
      continue
    }
    if (arg === "--dry-run") {
      options.dryRun = true
      continue
    }
    if (arg === "--force") {
      options.force = true
      continue
    }
    if (arg === "--agent") {
      const value = argv[index + 1]
      if (!value) throw new Error("--agent requires a value")
      options.agents.push(...value.split(",").map((item) => item.trim()).filter(Boolean))
      index += 1
      continue
    }
    if (arg.startsWith("--agent=")) {
      options.agents.push(...arg.slice("--agent=".length).split(",").map((item) => item.trim()).filter(Boolean))
      continue
    }
    throw new Error(`unknown argument: ${arg}`)
  }

  return options
}

function commandExists(command) {
  const result = spawnSync(command, ["--version"], { stdio: "ignore" })
  return !result.error
}

function detectAgents() {
  return [
    { id: "opencode", label: "OpenCode", detected: commandExists("opencode") },
    { id: "codex", label: "Codex", detected: commandExists("codex") },
  ]
}

function expandAgents(agentValues, detectedAgents) {
  const detected = detectedAgents.filter((agent) => agent.detected).map((agent) => agent.id)
  const expanded = new Set()

  for (const value of agentValues) {
    if (value === "all") {
      expanded.add("opencode")
      expanded.add("codex")
      continue
    }
    if (value === "detected") {
      for (const agent of detected) expanded.add(agent)
      continue
    }
    if (value === "opencode" || value === "codex") {
      expanded.add(value)
      continue
    }
    throw new Error(`unknown agent target: ${value}`)
  }

  return Array.from(expanded)
}

async function chooseAgents(options, detectedAgents) {
  if (options.agents.length > 0) {
    return expandAgents(options.agents, detectedAgents)
  }

  const detected = detectedAgents.filter((agent) => agent.detected)
  if (options.yes) {
    return detected.length > 0 ? detected.map((agent) => agent.id) : ["opencode"]
  }

  const ordered = [
    ...detectedAgents.filter((agent) => agent.detected),
    ...detectedAgents.filter((agent) => !agent.detected),
  ]
  const choices = []

  if (detected.length > 1) {
    choices.push({ id: "detected", label: "All detected agents", hint: detected.map((agent) => agent.label).join(", ") })
  }

  for (const agent of ordered) {
    choices.push({
      id: agent.id,
      label: agent.label,
      hint: agent.detected ? "detected" : "not detected",
    })
  }

  choices.push({ id: "all", label: "All supported agents", hint: "OpenCode, Codex" })

  console.log("Select Let My Agent Sleep install target:")
  choices.forEach((choice, index) => {
    console.log(`  ${index + 1}) ${choice.label} (${choice.hint})`)
  })

  const rl = createInterface({ input, output })
  const answer = await rl.question(`Choice [1]: `)
  rl.close()

  const index = answer.trim() === "" ? 0 : Number(answer.trim()) - 1
  if (!Number.isInteger(index) || index < 0 || index >= choices.length) {
    throw new Error(`invalid choice: ${answer}`)
  }

  return expandAgents([choices[index].id], detectedAgents)
}

function logWrite(options, action, target) {
  const prefix = options.dryRun ? "[dry-run]" : "[write]"
  console.log(`${prefix} ${action}: ${target}`)
}

function logSkip(action, target) {
  console.log(`[skip] ${action}: ${target}`)
}

function backupIfNeeded(target, options) {
  if (!existsSync(target) || options.force || options.dryRun) return
  const backup = `${target}.bak.${new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z")}`
  renameSync(target, backup)
  console.log(`[backup] ${target} -> ${backup}`)
}

function timestamp() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z")
}

function moveAside(target, backupRoot, options) {
  if (!existsSync(target)) return
  const backup = join(backupRoot, `${basename(target)}.${timestamp()}`)
  const prefix = options.dryRun ? "[dry-run]" : "[write]"
  console.log(`${prefix} move-aside: ${target} -> ${backup}`)
  if (options.dryRun) return
  mkdirSync(backupRoot, { recursive: true })
  renameSync(target, backup)
}

function moveMatchingSiblingBackups(parent, prefix, backupRoot, options) {
  if (!existsSync(parent)) return
  for (const entry of readdirSync(parent, { withFileTypes: true })) {
    if (!entry.name.startsWith(`${prefix}.bak.`)) continue
    moveAside(join(parent, entry.name), backupRoot, options)
  }
}

function sameFileContent(source, target) {
  if (!existsSync(source) || !existsSync(target)) return false
  const sourceStat = statSync(source)
  const targetStat = statSync(target)
  if (!sourceStat.isFile() || !targetStat.isFile()) return false
  return readFileSync(source).equals(readFileSync(target))
}

function sameTreeContent(source, target) {
  if (!existsSync(source) || !existsSync(target)) return false

  const sourceStat = statSync(source)
  const targetStat = statSync(target)

  if (sourceStat.isFile() || targetStat.isFile()) {
    return sameFileContent(source, target)
  }

  if (!sourceStat.isDirectory() || !targetStat.isDirectory()) {
    return false
  }

  const sourceEntries = readdirSync(source, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))
  const targetEntries = readdirSync(target, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))

  if (sourceEntries.length !== targetEntries.length) return false

  for (let index = 0; index < sourceEntries.length; index += 1) {
    const sourceEntry = sourceEntries[index]
    const targetEntry = targetEntries[index]
    if (sourceEntry.name !== targetEntry.name) return false
    if (sourceEntry.isDirectory() !== targetEntry.isDirectory()) return false
    if (sourceEntry.isFile() !== targetEntry.isFile()) return false
    if (!sameTreeContent(join(source, sourceEntry.name), join(target, targetEntry.name))) return false
  }

  return true
}

function writeText(target, content, options) {
  if (existsSync(target) && statSync(target).isFile() && readFileSync(target, "utf8") === content) {
    logSkip("write", target)
    return
  }
  logWrite(options, "write", target)
  if (options.dryRun) return
  mkdirSync(dirname(target), { recursive: true })
  backupIfNeeded(target, options)
  writeFileSync(target, content)
}

function copyFileAsset(source, target, options) {
  if (sameFileContent(source, target)) {
    logSkip("copy", `${source} -> ${target}`)
    return
  }
  logWrite(options, "copy", `${source} -> ${target}`)
  if (options.dryRun) return
  mkdirSync(dirname(target), { recursive: true })
  backupIfNeeded(target, options)
  copyFileSync(source, target)
}

function copyDirAsset(source, target, options) {
  if (sameTreeContent(source, target)) {
    logSkip("copy-dir", `${source} -> ${target}`)
    return
  }
  logWrite(options, "copy-dir", `${source} -> ${target}`)
  if (options.dryRun) return
  if (existsSync(target)) {
    if (options.force) {
      rmSync(target, { recursive: true, force: true })
    } else {
      const backup = `${target}.bak.${new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z")}`
      renameSync(target, backup)
      console.log(`[backup] ${target} -> ${backup}`)
    }
  }
  mkdirSync(dirname(target), { recursive: true })
  cpSync(source, target, { recursive: true })
}

function readJsonIfExists(target, fallback) {
  if (!existsSync(target)) return fallback
  return JSON.parse(readFileSync(target, "utf8"))
}

function installOpenCode(options) {
  const configDir = process.env.OPENCODE_CONFIG_DIR || join(homedir(), ".config", "opencode")
  const configPath = join(configDir, "opencode.json")
  const skillTarget = join(configDir, "skills", "let-my-agent-sleep", "SKILL.md")
  const config = readJsonIfExists(configPath, {})

  if (config.plugin === undefined) {
    config.plugin = []
  } else if (typeof config.plugin === "string") {
    config.plugin = [config.plugin]
  } else if (!Array.isArray(config.plugin)) {
    throw new Error(`${configPath} has unsupported "plugin" shape; expected string or array`)
  }

  if (!config.plugin.includes(packageName)) {
    config.plugin.push(packageName)
  }

  writeText(configPath, `${JSON.stringify(config, null, 2)}\n`, options)
  copyFileAsset(paths.openCodeSkill, skillTarget, options)

  console.log("OpenCode install configured.")
  console.log(`  plugin: ${packageName}`)
  console.log(`  skill: ${skillTarget}`)
}

function removeMarketplaceEntry(marketplace, entryName) {
  if (!Array.isArray(marketplace.plugins)) return marketplace
  marketplace.plugins = marketplace.plugins.filter((plugin) => plugin.name !== entryName)
  return marketplace
}

function installCodex(options) {
  const agentsRoot = join(homedir(), ".agents")
  const codexSkillTarget = join(agentsRoot, "skills", "let-my-agent-sleep")
  const marketplaceDir = join(agentsRoot, "plugins")
  const marketplacePath = join(marketplaceDir, "marketplace.json")
  const legacyCodexPluginTarget = join(marketplaceDir, "plugins", "let-my-agent-sleep")
  const backupRoot = join(agentsRoot, "lmas-backups")

  copyDirAsset(join(paths.codexPlugin, "skills", "let-my-agent-sleep"), codexSkillTarget, options)
  moveAside(legacyCodexPluginTarget, join(backupRoot, "plugins"), options)
  moveMatchingSiblingBackups(join(agentsRoot, "skills"), "let-my-agent-sleep", join(backupRoot, "skills"), options)
  moveMatchingSiblingBackups(join(marketplaceDir, "plugins"), "let-my-agent-sleep", join(backupRoot, "plugins"), options)

  if (existsSync(marketplacePath)) {
    const marketplace = readJsonIfExists(marketplacePath, {})
    const original = JSON.stringify(marketplace)
    removeMarketplaceEntry(marketplace, "let-my-agent-sleep")
    if (JSON.stringify(marketplace) !== original) {
      writeText(marketplacePath, `${JSON.stringify(marketplace, null, 2)}\n`, { ...options, force: true })
    }
  }

  console.log("Codex install configured.")
  console.log(`  skill: ${codexSkillTarget}`)
  console.log("  plugin: not installed; Codex uses the standalone skill to avoid duplicate indexing.")
  console.log(`  backups: ${backupRoot}`)
}

async function main() {
  const argv = process.argv.slice(2)
  const command = argv[0]

  if (command === "start" || command === "status" || command === "list" || command === "__watch") {
    runWrapper(argv)
  }

  const options = parseArgs(argv)
  const detectedAgents = detectAgents()
  const selectedAgents = await chooseAgents(options, detectedAgents)

  if (selectedAgents.length === 0) {
    throw new Error("no install targets selected")
  }

  console.log("Detected agents:")
  for (const agent of detectedAgents) {
    console.log(`  ${agent.detected ? "✓" : "-"} ${agent.label}`)
  }

  for (const agent of selectedAgents) {
    if (agent === "opencode") installOpenCode(options)
    if (agent === "codex") installCodex(options)
  }

  console.log("Let My Agent Sleep install complete.")
  if (selectedAgents.includes("opencode")) {
    console.log("Restart OpenCode so it reloads plugins and skills.")
  }
  if (selectedAgents.includes("codex")) {
    console.log("Restart Codex so it reloads skills/plugins.")
  }
}

main().catch((error) => {
  console.error(`lmas install failed: ${error.message}`)
  process.exit(1)
})
