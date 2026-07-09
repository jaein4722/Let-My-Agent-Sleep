#!/usr/bin/env node
import { spawnSync } from "node:child_process"
import { createInterface } from "node:readline/promises"
import { stdin as input, stdout as output } from "node:process"
import { chmodSync, copyFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs"
import { basename, dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { homedir } from "node:os"

const packageRoot = dirname(dirname(fileURLToPath(import.meta.url)))
const packageJson = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"))
const packageName = packageJson.name
const openCodePluginSpec = `${packageName}@latest`
const openCodeCacheDependencySpec = ">=0.0.0"
const openCodeSkillName = "let-my-agent-sleep"
const legacyCodexSkillName = "let-my-agent-sleep-codex"
const legacyClaudeSkillName = "let-my-agent-sleep-claude"
const openCodeHiddenCrossAgentSkills = [
  legacyCodexSkillName,
  legacyClaudeSkillName,
]
const omoContinuationHooks = [
  "todo-continuation-enforcer",
  "ralph-loop",
  "ulw-loop",
  "ultrawork",
  "start-work-continuation",
  "boulder-continuation",
  "unstable-agent-babysitter",
  "atlas",
]

const paths = {
  openCodeSkill: join(packageRoot, "skills", "let-my-agent-sleep", "SKILL.md"),
  codexPlugin: join(packageRoot, "codex-plugin", "let-my-agent-sleep"),
  claudeCommand: join(packageRoot, "claude", "let-my-agent-sleep", "commands", "let-my-agent-sleep.md"),
  claudeBin: join(packageRoot, "claude", "let-my-agent-sleep", "assets", "bin", "lmas.sh"),
  claudeScript: join(packageRoot, "claude", "let-my-agent-sleep", "assets", "scripts", "lmas.sh"),
}

function usage() {
  console.log(`Usage:
  lmas install [--agent opencode|codex|claude|all|detected] [--yes] [--dry-run] [--force] [--disable-omo-continuation] [--keep-omo-continuation]
  lmas doctor [--agent opencode|codex|claude|all|detected] [--yes] [--server-url <url>] [--directory <path>] [--server-username <name>] [--server-password <password>]
  lmas start [options] -- <command...>
  lmas status [--runs-dir <path>] <run_id|run_dir>
  lmas cancel [--runs-dir <path>] [--reason <text>] <run_id|run_dir>
  lmas list [--runs-dir <path>]

Options:
  --agent <target>  Target agent. May be repeated or comma-separated. Default: interactive.
  --yes, -y         Use defaults without prompting.
  --dry-run         Print intended writes without changing files.
  --force           Overwrite existing Let My Agent Sleep-managed files without backup.
  --disable-omo-continuation
                   Add known OMO continuation hooks to oh-my-openagent disabled_hooks.
                   This is the default during OpenCode install.
  --keep-omo-continuation
                   Do not modify Oh My OpenAgent disabled_hooks during OpenCode install.
  --server-url <url>
                   During OpenCode doctor, also verify the live server exposes lmas tools.
  --directory <path>
                   During OpenCode live doctor, pass the workspace directory to OpenCode.
  --server-username <name>
                   Basic-auth username for OpenCode live doctor. Default: LMAS_OPENCODE_USERNAME, OPENCODE_SERVER_USERNAME, or opencode.
  --server-password <password>
                   Basic-auth password for OpenCode live doctor. Default: LMAS_OPENCODE_PASSWORD or OPENCODE_SERVER_PASSWORD.
  LMAS_HTTP_MAX_TIME
                   OpenCode live doctor request timeout in seconds. Default: 30.
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
    disableOmoContinuation: false,
    keepOmoContinuation: false,
    serverUrl: "",
    directory: "",
    serverUsername: "",
    serverPassword: "",
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === "install" || arg === "doctor") continue
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
    if (arg === "--disable-omo-continuation") {
      options.disableOmoContinuation = true
      continue
    }
    if (arg === "--keep-omo-continuation") {
      options.keepOmoContinuation = true
      continue
    }
    if (arg === "--server-url") {
      const value = argv[index + 1]
      if (!value) throw new Error("--server-url requires a value")
      options.serverUrl = value
      index += 1
      continue
    }
    if (arg.startsWith("--server-url=")) {
      options.serverUrl = arg.slice("--server-url=".length)
      continue
    }
    if (arg === "--directory") {
      const value = argv[index + 1]
      if (!value) throw new Error("--directory requires a value")
      options.directory = value
      index += 1
      continue
    }
    if (arg.startsWith("--directory=")) {
      options.directory = arg.slice("--directory=".length)
      continue
    }
    if (arg === "--server-username") {
      const value = argv[index + 1]
      if (!value) throw new Error("--server-username requires a value")
      options.serverUsername = value
      index += 1
      continue
    }
    if (arg.startsWith("--server-username=")) {
      options.serverUsername = arg.slice("--server-username=".length)
      continue
    }
    if (arg === "--server-password") {
      const value = argv[index + 1]
      if (!value) throw new Error("--server-password requires a value")
      options.serverPassword = value
      index += 1
      continue
    }
    if (arg.startsWith("--server-password=")) {
      options.serverPassword = arg.slice("--server-password=".length)
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

  if (options.disableOmoContinuation && options.keepOmoContinuation) {
    throw new Error("--disable-omo-continuation and --keep-omo-continuation cannot be used together")
  }

  return options
}

function commandExists(command) {
  const checker = process.platform === "win32" ? "where" : "command"
  const args = process.platform === "win32" ? [command] : ["-v", command]
  const result = spawnSync(checker, args, { stdio: "ignore", shell: process.platform !== "win32" })
  return result.status === 0
}

function detectAgents() {
  return [
    { id: "opencode", label: "OpenCode", detected: commandExists("opencode") },
    { id: "codex", label: "Codex", detected: commandExists("codex") },
    { id: "claude", label: "Claude Code", detected: commandExists("claude") },
  ]
}

function expandAgents(agentValues, detectedAgents) {
  const detected = detectedAgents.filter((agent) => agent.detected).map((agent) => agent.id)
  const expanded = new Set()

  for (const value of agentValues) {
    if (value === "all") {
      expanded.add("opencode")
      expanded.add("codex")
      expanded.add("claude")
      continue
    }
    if (value === "detected") {
      for (const agent of detected) expanded.add(agent)
      continue
    }
    if (value === "opencode" || value === "codex" || value === "claude") {
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

  choices.push({ id: "all", label: "All supported agents", hint: "OpenCode, Codex, Claude Code" })

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
  if ((sourceStat.mode & 0o777) !== (targetStat.mode & 0o777)) return false
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
  chmodSync(target, statSync(source).mode & 0o777)
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

function removePath(target, options) {
  if (!existsSync(target)) return
  logWrite(options, "remove", target)
  if (options.dryRun) return
  rmSync(target, { recursive: true, force: true })
}

function readJsonIfExists(target, fallback) {
  if (!existsSync(target)) return fallback
  return JSON.parse(readFileSync(target, "utf8"))
}

function stripJsonc(input) {
  let output = ""
  let inString = false
  let quote = ""
  let escaped = false

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index]
    const next = input[index + 1]

    if (inString) {
      output += char
      if (escaped) {
        escaped = false
      } else if (char === "\\") {
        escaped = true
      } else if (char === quote) {
        inString = false
      }
      continue
    }

    if (char === '"' || char === "'") {
      inString = true
      quote = char
      output += char
      continue
    }

    if (char === "/" && next === "/") {
      while (index < input.length && input[index] !== "\n") index += 1
      output += "\n"
      continue
    }

    if (char === "/" && next === "*") {
      index += 2
      while (index < input.length && !(input[index] === "*" && input[index + 1] === "/")) index += 1
      index += 1
      continue
    }

    output += char
  }

  return stripTrailingJsoncCommas(output)
}

function stripTrailingJsoncCommas(input) {
  let output = ""
  let inString = false
  let escaped = false

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index]

    if (inString) {
      output += char
      if (escaped) {
        escaped = false
      } else if (char === "\\") {
        escaped = true
      } else if (char === '"') {
        inString = false
      }
      continue
    }

    if (char === '"') {
      inString = true
      output += char
      continue
    }

    if (char === ",") {
      let lookahead = index + 1
      while (/\s/.test(input[lookahead] || "")) lookahead += 1
      if (input[lookahead] === "}" || input[lookahead] === "]") continue
    }

    output += char
  }

  return output
}

function readJsoncIfExists(target, fallback) {
  if (!existsSync(target)) return fallback
  return JSON.parse(stripJsonc(readFileSync(target, "utf8")))
}

function isJsoncPath(target) {
  return target.endsWith(".jsonc")
}

function lineIndentBefore(content, index) {
  const lineStart = content.lastIndexOf("\n", index - 1) + 1
  const match = content.slice(lineStart, index).match(/^\s*/)
  return match?.[0] || ""
}

function skipJsoncTrivia(content, index) {
  let cursor = index
  while (cursor < content.length) {
    if (/\s/.test(content[cursor] || "")) {
      cursor += 1
      continue
    }
    if (content[cursor] === "/" && content[cursor + 1] === "/") {
      cursor += 2
      while (cursor < content.length && content[cursor] !== "\n") cursor += 1
      continue
    }
    if (content[cursor] === "/" && content[cursor + 1] === "*") {
      cursor += 2
      while (cursor < content.length && !(content[cursor] === "*" && content[cursor + 1] === "/")) cursor += 1
      cursor += 2
      continue
    }
    break
  }
  return cursor
}

function readJsoncString(content, index) {
  const quote = content[index]
  if (quote !== '"' && quote !== "'") return undefined
  let value = ""
  let cursor = index + 1
  let escaped = false

  while (cursor < content.length) {
    const char = content[cursor]
    if (escaped) {
      value += char
      escaped = false
    } else if (char === "\\") {
      value += char
      escaped = true
    } else if (char === quote) {
      return { value, end: cursor + 1 }
    } else {
      value += char
    }
    cursor += 1
  }

  return undefined
}

function findTopLevelObjectClose(content) {
  let depth = 0
  let inString = false
  let quote = ""
  let escaped = false
  let lineComment = false
  let blockComment = false

  for (let index = 0; index < content.length; index += 1) {
    const char = content[index]
    const next = content[index + 1]

    if (lineComment) {
      if (char === "\n") lineComment = false
      continue
    }
    if (blockComment) {
      if (char === "*" && next === "/") {
        blockComment = false
        index += 1
      }
      continue
    }
    if (inString) {
      if (escaped) {
        escaped = false
      } else if (char === "\\") {
        escaped = true
      } else if (char === quote) {
        inString = false
      }
      continue
    }
    if (char === "/" && next === "/") {
      lineComment = true
      index += 1
      continue
    }
    if (char === "/" && next === "*") {
      blockComment = true
      index += 1
      continue
    }
    if (char === '"' || char === "'") {
      inString = true
      quote = char
      continue
    }
    if (char === "{") {
      depth += 1
      continue
    }
    if (char === "}") {
      depth -= 1
      if (depth === 0) return index
    }
  }

  return -1
}

function findTopLevelProperty(content, key) {
  let depth = 0
  let inString = false
  let quote = ""
  let escaped = false
  let lineComment = false
  let blockComment = false

  for (let index = 0; index < content.length; index += 1) {
    const char = content[index]
    const next = content[index + 1]

    if (lineComment) {
      if (char === "\n") lineComment = false
      continue
    }
    if (blockComment) {
      if (char === "*" && next === "/") {
        blockComment = false
        index += 1
      }
      continue
    }
    if (inString) {
      if (escaped) {
        escaped = false
      } else if (char === "\\") {
        escaped = true
      } else if (char === quote) {
        inString = false
      }
      continue
    }
    if (char === "/" && next === "/") {
      lineComment = true
      index += 1
      continue
    }
    if (char === "/" && next === "*") {
      blockComment = true
      index += 1
      continue
    }
    if (char === "{") {
      depth += 1
      continue
    }
    if (char === "}") {
      depth -= 1
      continue
    }
    if (depth !== 1 || (char !== '"' && char !== "'")) continue

    const property = readJsoncString(content, index)
    if (!property || property.value !== key) continue

    let cursor = skipJsoncTrivia(content, property.end)
    if (content[cursor] !== ":") continue
    cursor = skipJsoncTrivia(content, cursor + 1)

    const valueStart = cursor
    let valueDepth = 0
    let valueString = false
    let valueQuote = ""
    let valueEscaped = false
    let valueLineComment = false
    let valueBlockComment = false

    while (cursor < content.length) {
      const valueChar = content[cursor]
      const valueNext = content[cursor + 1]

      if (valueLineComment) {
        if (valueChar === "\n") valueLineComment = false
        cursor += 1
        continue
      }
      if (valueBlockComment) {
        if (valueChar === "*" && valueNext === "/") {
          valueBlockComment = false
          cursor += 2
          continue
        }
        cursor += 1
        continue
      }
      if (valueString) {
        if (valueEscaped) {
          valueEscaped = false
        } else if (valueChar === "\\") {
          valueEscaped = true
        } else if (valueChar === valueQuote) {
          valueString = false
        }
        cursor += 1
        continue
      }
      if (valueChar === "/" && valueNext === "/") {
        valueLineComment = true
        cursor += 2
        continue
      }
      if (valueChar === "/" && valueNext === "*") {
        valueBlockComment = true
        cursor += 2
        continue
      }
      if (valueChar === '"' || valueChar === "'") {
        valueString = true
        valueQuote = valueChar
        cursor += 1
        continue
      }
      if (valueChar === "{" || valueChar === "[") {
        valueDepth += 1
        cursor += 1
        continue
      }
      if (valueChar === "}" || valueChar === "]") {
        if (valueDepth === 0 && valueChar === "}") break
        valueDepth -= 1
        cursor += 1
        continue
      }
      if (valueDepth === 0 && valueChar === ",") break
      cursor += 1
    }

    let valueEnd = cursor
    while (valueEnd > valueStart && /\s/.test(content[valueEnd - 1] || "")) valueEnd -= 1

    return {
      keyStart: index,
      valueStart,
      valueEnd,
      indent: lineIndentBefore(content, index),
    }
  }

  return undefined
}

function formatJsoncManagedValue(value, propertyIndent) {
  const json = JSON.stringify(value, null, 2)
  if (!json.includes("\n")) return json
  return json
    .split("\n")
    .map((line, index) => index === 0 ? line : `${propertyIndent}${line}`)
    .join("\n")
}

function formatStringArray(values, propertyIndent) {
  const itemIndent = `${propertyIndent}  `
  if (values.length === 0) return "[]"
  return [
    "[",
    values.map((value) => `${itemIndent}${JSON.stringify(value)}`).join(",\n"),
    `${propertyIndent}]`,
  ].join("\n")
}

function writeJsonConfigWithStringArray(target, config, key, values, options) {
  const jsonText = `${JSON.stringify(config, null, 2)}\n`
  if (!isJsoncPath(target) || !existsSync(target)) {
    writeText(target, jsonText, options)
    return
  }

  const content = readFileSync(target, "utf8")
  const property = findTopLevelProperty(content, key)

  if (property) {
    const replacement = Array.isArray(values) && values.every((value) => typeof value === "string")
      ? formatStringArray(values, property.indent)
      : formatJsoncManagedValue(values, property.indent)
    writeText(target, `${content.slice(0, property.valueStart)}${replacement}${content.slice(property.valueEnd)}`, options)
    return
  }

  const closeIndex = findTopLevelObjectClose(content)
  if (closeIndex === -1) {
    writeText(target, jsonText, options)
    return
  }

  const closeIndent = lineIndentBefore(content, closeIndex)
  const propertyIndent = `${closeIndent}  `
  const beforeClose = content.slice(0, closeIndex).trimEnd()
  const hasOtherProperties = Object.keys(config).some((propertyName) => propertyName !== key)
  const needsComma = hasOtherProperties && !beforeClose.endsWith(",")
  const prefix = needsComma ? "," : ""
  const formattedValue = Array.isArray(values) && values.every((value) => typeof value === "string")
    ? formatStringArray(values, propertyIndent)
    : formatJsoncManagedValue(values, propertyIndent)
  const insertion = `${prefix}\n${propertyIndent}${JSON.stringify(key)}: ${formattedValue}\n`
  writeText(target, `${content.slice(0, closeIndex).trimEnd()}${insertion}${content.slice(closeIndex)}`, options)
}

function resolveOpenCodeConfigDir() {
  const customConfigDir = process.env.OPENCODE_CONFIG_DIR?.trim()
  if (customConfigDir) return customConfigDir

  const xdgConfigHome = process.env.XDG_CONFIG_HOME?.trim()
  return join(xdgConfigHome || join(homedir(), ".config"), "opencode")
}

function resolveOpenCodeConfigPath(configDir) {
  if (process.env.OPENCODE_CONFIG_FILE) return process.env.OPENCODE_CONFIG_FILE

  const jsoncPath = join(configDir, "opencode.jsonc")
  const jsonPath = join(configDir, "opencode.json")

  if (existsSync(jsoncPath)) return jsoncPath
  if (existsSync(jsonPath)) return jsonPath
  return jsoncPath
}

function resolveOmoConfigPath(configDir) {
  const candidates = [
    join(configDir, "oh-my-openagent.jsonc"),
    join(configDir, "oh-my-openagent.json"),
    join(configDir, "oh-my-opencode.jsonc"),
    join(configDir, "oh-my-opencode.json"),
  ]

  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate
  }

  return join(configDir, "oh-my-openagent.json")
}

function resolveOpenCodeCacheDir() {
  if (process.env.OPENCODE_CACHE_DIR) return process.env.OPENCODE_CACHE_DIR
  const cacheHome = process.env.XDG_CACHE_HOME || join(homedir(), ".cache")
  return join(cacheHome, "opencode")
}

function maybeDisableOmoContinuation(configDir, options, reason) {
  if (!reason) return

  const omoConfigPath = resolveOmoConfigPath(configDir)
  const omoConfig = readJsoncIfExists(omoConfigPath, {})

  if (omoConfig.disabled_hooks === undefined) {
    omoConfig.disabled_hooks = []
  }
  if (!Array.isArray(omoConfig.disabled_hooks)) {
    throw new Error(`${omoConfigPath} has unsupported "disabled_hooks" shape; expected array`)
  }
  for (const hookName of omoContinuationHooks) {
    if (!omoConfig.disabled_hooks.includes(hookName)) {
      omoConfig.disabled_hooks.push(hookName)
    }
  }

  writeJsonConfigWithStringArray(omoConfigPath, omoConfig, "disabled_hooks", omoConfig.disabled_hooks, options)
  console.log("Oh My OpenAgent continuation configured.")
  console.log(`  reason: ${reason}`)
  console.log(`  disabled hooks: ${omoContinuationHooks.join(", ")}`)
  console.log(`  config: ${omoConfigPath}`)
}

function maybeDisableOpenCodeShadowSkills(configDir, options, writeOptions = {}) {
  const omoConfigPath = resolveOmoConfigPath(configDir)
  const omoConfig = readJsoncIfExists(omoConfigPath, {})

  if (omoConfig.disabled_skills === undefined) {
    omoConfig.disabled_skills = []
  }
  if (!Array.isArray(omoConfig.disabled_skills)) {
    throw new Error(`${omoConfigPath} has unsupported "disabled_skills" shape; expected array`)
  }
  for (const skillName of openCodeHiddenCrossAgentSkills) {
    if (!omoConfig.disabled_skills.includes(skillName)) {
      omoConfig.disabled_skills.push(skillName)
    }
  }

  const finalOptions = writeOptions.skipBackup ? { ...options, force: true } : options
  writeJsonConfigWithStringArray(omoConfigPath, omoConfig, "disabled_skills", omoConfig.disabled_skills, finalOptions)
  console.log("OpenCode cross-agent skill shadowing configured.")
  console.log(`  hidden skills: ${openCodeHiddenCrossAgentSkills.join(", ")}`)
  console.log(`  config: ${omoConfigPath}`)
}

function moveLegacyCrossAgentOpenCodeSkillConflicts(options) {
  const agentsRoot = join(homedir(), ".agents")
  const claudeRoot = join(homedir(), ".claude")

  moveAside(
    join(agentsRoot, "skills", openCodeSkillName),
    join(agentsRoot, "lmas-backups", "skills"),
    options,
  )
  moveAside(
    join(agentsRoot, "skills", legacyCodexSkillName),
    join(agentsRoot, "lmas-backups", "skills"),
    options,
  )
  moveAside(
    join(claudeRoot, "skills", openCodeSkillName),
    join(claudeRoot, "lmas-backups", "skills"),
    options,
  )
  moveAside(
    join(claudeRoot, "skills", legacyClaudeSkillName),
    join(claudeRoot, "lmas-backups", "skills"),
    options,
  )
  moveMatchingSiblingBackups(join(agentsRoot, "skills"), openCodeSkillName, join(agentsRoot, "lmas-backups", "skills"), options)
  moveMatchingSiblingBackups(join(agentsRoot, "skills"), legacyCodexSkillName, join(agentsRoot, "lmas-backups", "skills"), options)
  moveMatchingSiblingBackups(join(claudeRoot, "skills"), openCodeSkillName, join(claudeRoot, "lmas-backups", "skills"), options)
  moveMatchingSiblingBackups(join(claudeRoot, "skills"), legacyClaudeSkillName, join(claudeRoot, "lmas-backups", "skills"), options)
}

function updateOpenCodeRootCachePackage(rootPackagePath, options) {
  const dependencyPattern = new RegExp(`("${packageName}"\\s*:\\s*)"[^"]+"`)

  if (existsSync(rootPackagePath)) {
    const content = readFileSync(rootPackagePath, "utf8")
    if (dependencyPattern.test(content)) {
      writeText(rootPackagePath, content.replace(dependencyPattern, `$1"${openCodeCacheDependencySpec}"`), options)
      return
    }

    const rootPackageJson = JSON.parse(content)
    if (!rootPackageJson.dependencies || typeof rootPackageJson.dependencies !== "object" || Array.isArray(rootPackageJson.dependencies)) {
      rootPackageJson.dependencies = {}
    }
    rootPackageJson.dependencies[packageName] = openCodeCacheDependencySpec
    writeText(rootPackagePath, `${JSON.stringify(rootPackageJson, null, 2)}\n`, options)
    return
  }

  writeText(rootPackagePath, `${JSON.stringify({ dependencies: { [packageName]: openCodeCacheDependencySpec } }, null, 2)}\n`, options)
}

function refreshOpenCodePluginCache(options) {
  const cacheDir = resolveOpenCodeCacheDir()
  const packagesDir = join(cacheDir, "packages")
  const rootPackagePath = join(cacheDir, "package.json")
  const stalePackageCaches = new Set([
    join(packagesDir, packageName),
    join(packagesDir, openCodePluginSpec),
  ])

  if (existsSync(packagesDir)) {
    for (const entry of readdirSync(packagesDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue
      if (entry.name === packageName || entry.name.startsWith(`${packageName}@`)) {
        stalePackageCaches.add(join(packagesDir, entry.name))
      }
    }
  }

  updateOpenCodeRootCachePackage(rootPackagePath, options)
  removePath(join(cacheDir, "bun.lock"), options)
  removePath(join(cacheDir, "package-lock.json"), options)
  removePath(join(cacheDir, "node_modules", packageName), options)
  removePath(join(cacheDir, "node_modules", ".bin", "lmas"), options)
  removePath(join(cacheDir, "node_modules", ".bin", packageName), options)

  for (const target of stalePackageCaches) {
    removePath(target, options)
  }
}

function getPluginSpecName(plugin) {
  if (typeof plugin === "string") return plugin
  if (Array.isArray(plugin) && typeof plugin[0] === "string") return plugin[0]
  return undefined
}

function isPackagePluginSpec(plugin, name) {
  const spec = getPluginSpecName(plugin)
  return spec === name || spec?.startsWith(`${name}@`) === true
}

function isOmoPluginSpec(plugin) {
  const spec = getPluginSpecName(plugin)
  return spec === "oh-my-openagent"
    || spec?.startsWith("oh-my-openagent@") === true
    || spec === "oh-my-opencode"
    || spec?.startsWith("oh-my-opencode@") === true
}

function warnIfOmoContinuationStillEnabled(config, options) {
  if (options.disableOmoContinuation) return
  if (!options.keepOmoContinuation) return
  if (!Array.isArray(config.plugin) || !config.plugin.some(isOmoPluginSpec)) return

  console.log("[warn] Oh My OpenAgent plugin detected.")
  console.log("[warn] OMO continuation hooks were left enabled because --keep-omo-continuation was used.")
  console.log("[warn] To disable it, run:")
  console.log("[warn]   lmas install --agent opencode")
}

function installOpenCode(options) {
  const configDir = resolveOpenCodeConfigDir()
  const configPath = resolveOpenCodeConfigPath(configDir)
  const skillTarget = join(configDir, "skills", openCodeSkillName, "SKILL.md")
  const config = readJsoncIfExists(configPath, {})

  if (config.plugin === undefined) {
    config.plugin = []
  } else if (typeof config.plugin === "string") {
    config.plugin = [config.plugin]
  } else if (!Array.isArray(config.plugin)) {
    throw new Error(`${configPath} has unsupported "plugin" shape; expected string or array`)
  }

  warnIfOmoContinuationStillEnabled(config, options)

  config.plugin = config.plugin.filter((plugin) => !isPackagePluginSpec(plugin, packageName))
  // LMAS must load before continuation plugins so prompt/fetch guards are installed
  // before those plugins capture OpenCode prompt methods.
  config.plugin.unshift(openCodePluginSpec)

  writeJsonConfigWithStringArray(configPath, config, "plugin", config.plugin, options)
  const omoDisableReason = options.disableOmoContinuation
    ? "requested by --disable-omo-continuation"
    : !options.keepOmoContinuation
      ? "OpenCode install defaults to disabling known OMO continuation hooks"
      : ""
  maybeDisableOmoContinuation(configDir, options, omoDisableReason)
  maybeDisableOpenCodeShadowSkills(configDir, options, { skipBackup: Boolean(omoDisableReason) })
  moveLegacyCrossAgentOpenCodeSkillConflicts(options)
  copyFileAsset(paths.openCodeSkill, skillTarget, options)
  refreshOpenCodePluginCache(options)

  console.log("OpenCode install configured.")
  console.log(`  plugin: ${openCodePluginSpec}`)
  console.log(`  skill: ${skillTarget}`)
  console.log(`  plugin cache: ${resolveOpenCodeCacheDir()}`)
}

function doctorLine(state, message) {
  console.log(`[${state}] ${message}`)
}

function doctorOk(message) {
  doctorLine("ok", message)
}

function doctorWarn(message) {
  doctorLine("warn", message)
}

function doctorFail(message) {
  doctorLine("fail", message)
  return false
}

function isExecutableFile(target) {
  if (!existsSync(target)) return false
  const stat = statSync(target)
  return stat.isFile() && (stat.mode & 0o111) !== 0
}

function liveToolIDsUrl(serverUrl, options = {}) {
  const base = new URL(serverUrl)
  const url = new URL("/experimental/tool/ids", base)
  if (options.directory) url.searchParams.set("directory", options.directory)
  return url
}

function openCodeAuthHeaders(options) {
  const password = options.serverPassword || process.env.LMAS_OPENCODE_PASSWORD || process.env.OPENCODE_SERVER_PASSWORD || ""
  if (!password) return undefined

  const username = options.serverUsername || process.env.LMAS_OPENCODE_USERNAME || process.env.OPENCODE_SERVER_USERNAME || "opencode"
  const token = Buffer.from(`${username}:${password}`).toString("base64")
  return { Authorization: `Basic ${token}` }
}

async function doctorOpenCodeLiveTools(options) {
  const requiredTools = ["lmas_start", "lmas_status", "lmas_cancel", "lmas_info"]
  const serverUrl = options.serverUrl
  const timeoutSeconds = Number(process.env.LMAS_HTTP_MAX_TIME || 30)
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), Number.isFinite(timeoutSeconds) && timeoutSeconds > 0 ? timeoutSeconds * 1000 : 30000)
  let response
  try {
    response = await fetch(liveToolIDsUrl(serverUrl, options), {
      headers: openCodeAuthHeaders(options),
      signal: controller.signal,
    })
  } catch (error) {
    if (error.name === "AbortError") {
      return doctorFail(`OpenCode server live doctor timed out at ${serverUrl} after ${Number.isFinite(timeoutSeconds) && timeoutSeconds > 0 ? timeoutSeconds : 30}s`)
    }
    return doctorFail(`OpenCode server is unreachable at ${serverUrl}: ${error.message}`)
  } finally {
    clearTimeout(timeout)
  }

  if (response.status === 401) {
    return doctorFail(`OpenCode server rejected live doctor authentication at ${serverUrl}; pass --server-password or set LMAS_OPENCODE_PASSWORD`)
  }

  if (!response.ok) {
    return doctorFail(`OpenCode server tool id check failed at ${serverUrl}: HTTP ${response.status}`)
  }

  let toolIDs
  try {
    toolIDs = await response.json()
  } catch (error) {
    return doctorFail(`OpenCode server tool id response is not JSON: ${error.message}`)
  }

  if (!Array.isArray(toolIDs)) {
    return doctorFail("OpenCode server tool id response has unexpected shape; expected an array")
  }

  const missingTools = requiredTools.filter((toolID) => !toolIDs.includes(toolID))
  if (missingTools.length > 0) {
    return doctorFail(`OpenCode live server does not expose LMAS tools: ${missingTools.join(", ")}`)
  }

  doctorOk(`OpenCode live server exposes LMAS tools: ${requiredTools.join(", ")}`)
  return true
}

async function doctorOpenCode(options) {
  let healthy = true
  const configDir = resolveOpenCodeConfigDir()
  const configPath = resolveOpenCodeConfigPath(configDir)
  const omoConfigPath = resolveOmoConfigPath(configDir)
  const skillTarget = join(configDir, "skills", openCodeSkillName, "SKILL.md")
  const cacheDir = resolveOpenCodeCacheDir()
  const rootPackagePath = join(cacheDir, "package.json")

  console.log("OpenCode doctor:")
  console.log(`  config: ${configPath}`)
  console.log(`  omo config: ${omoConfigPath}`)
  console.log(`  skill: ${skillTarget}`)
  console.log(`  plugin cache: ${cacheDir}`)

  if (!existsSync(configPath)) {
    healthy = doctorFail("OpenCode config is missing; run: lmas install --agent opencode") && healthy
  } else {
    try {
      const config = readJsoncIfExists(configPath, {})
      const plugins = Array.isArray(config.plugin)
        ? config.plugin
        : typeof config.plugin === "string"
          ? [config.plugin]
          : []
      const pluginSpecs = plugins.map(getPluginSpecName).filter(Boolean)
      const lmasIndex = plugins.findIndex((plugin) => isPackagePluginSpec(plugin, packageName))

      if (lmasIndex === -1) {
        healthy = doctorFail(`OpenCode plugin list does not include ${openCodePluginSpec}`) && healthy
      } else if (lmasIndex !== 0) {
        healthy = doctorFail(`${packageName} is not first in the OpenCode plugin list; reinstall with: lmas install --agent opencode`) && healthy
      } else {
        doctorOk(`${packageName} is first in the OpenCode plugin list`)
      }

      const omoIndex = plugins.findIndex(isOmoPluginSpec)
      if (omoIndex !== -1 && lmasIndex !== -1 && lmasIndex > omoIndex) {
        healthy = doctorFail("Oh My OpenAgent loads before LMAS; LMAS continuation guards may be installed too late") && healthy
      } else if (omoIndex !== -1 && lmasIndex !== -1) {
        doctorOk("LMAS loads before Oh My OpenAgent")
      } else if (pluginSpecs.length > 0) {
        doctorWarn("Oh My OpenAgent plugin was not detected in the OpenCode plugin list")
      }
    } catch (error) {
      healthy = doctorFail(`OpenCode config could not be parsed: ${error.message}`) && healthy
    }
  }

  if (!existsSync(skillTarget)) {
    healthy = doctorFail("OpenCode skill file is missing; run: lmas install --agent opencode") && healthy
  } else {
    doctorOk("OpenCode skill file is installed")
  }

  if (!existsSync(omoConfigPath)) {
    healthy = doctorFail("Oh My OpenAgent config is missing; LMAS cannot confirm continuation hooks are disabled") && healthy
  } else {
    try {
      const omoConfig = readJsoncIfExists(omoConfigPath, {})
      const disabledHooks = Array.isArray(omoConfig.disabled_hooks) ? omoConfig.disabled_hooks : []
      const missingHooks = omoContinuationHooks.filter((hookName) => !disabledHooks.includes(hookName))
      if (missingHooks.length > 0) {
        healthy = doctorFail(`OMO continuation hooks are still enabled: ${missingHooks.join(", ")}`) && healthy
      } else {
        doctorOk(`OMO continuation hooks are disabled: ${omoContinuationHooks.join(", ")}`)
      }

      const disabledSkills = Array.isArray(omoConfig.disabled_skills) ? omoConfig.disabled_skills : []
      const missingSkills = openCodeHiddenCrossAgentSkills.filter((skillName) => !disabledSkills.includes(skillName))
      if (missingSkills.length > 0) {
        healthy = doctorFail(`legacy cross-agent LMAS skills are not hidden from OpenCode: ${missingSkills.join(", ")}`) && healthy
      } else {
        doctorOk(`legacy cross-agent LMAS skills are hidden: ${openCodeHiddenCrossAgentSkills.join(", ")}`)
      }
    } catch (error) {
      healthy = doctorFail(`Oh My OpenAgent config could not be parsed: ${error.message}`) && healthy
    }
  }

  if (!existsSync(rootPackagePath)) {
    healthy = doctorFail("OpenCode plugin cache package.json is missing; run: lmas install --agent opencode") && healthy
  } else {
    try {
      const cachePackage = readJsonIfExists(rootPackagePath, {})
      const dependency = cachePackage.dependencies?.[packageName]
      if (!dependency) {
        healthy = doctorFail(`OpenCode plugin cache package.json does not depend on ${packageName}`) && healthy
      } else if (dependency !== openCodeCacheDependencySpec) {
        healthy = doctorFail(`OpenCode plugin cache dependency is stale: ${packageName}@${dependency}; run: lmas install --agent opencode`) && healthy
      } else {
        doctorOk(`OpenCode plugin cache dependency is present: ${packageName}@${dependency}`)
      }
    } catch (error) {
      healthy = doctorFail(`OpenCode plugin cache package.json could not be parsed: ${error.message}`) && healthy
    }
  }

  if (options.serverUrl) {
    healthy = await doctorOpenCodeLiveTools(options) && healthy
  } else {
    doctorWarn("live OpenCode tool check skipped; pass --server-url http://127.0.0.1:4096 to verify loaded tools")
  }

  return healthy
}

function doctorCodex() {
  const codexHome = process.env.CODEX_HOME?.trim() || join(homedir(), ".codex")
  const codexSkillTarget = join(codexHome, "skills", openCodeSkillName, "SKILL.md")
  const codexBinTarget = join(codexHome, "skills", openCodeSkillName, "bin", "lmas.sh")
  const codexScriptTarget = join(codexHome, "skills", openCodeSkillName, "scripts", "lmas.sh")
  console.log("Codex doctor:")
  console.log(`  skill: ${codexSkillTarget}`)
  console.log(`  binary: ${codexBinTarget}`)
  console.log(`  wrapper: ${codexScriptTarget}`)
  let healthy = true
  if (!existsSync(codexSkillTarget)) {
    healthy = doctorFail("Codex skill file is missing; run: lmas install --agent codex") && healthy
  } else {
    doctorOk("Codex skill file is installed")
  }
  if (!isExecutableFile(codexBinTarget)) {
    healthy = doctorFail("Codex LMAS binary is missing or not executable; run: lmas install --agent codex") && healthy
  } else {
    doctorOk("Codex LMAS binary is executable")
  }
  if (!isExecutableFile(codexScriptTarget)) {
    healthy = doctorFail("Codex LMAS wrapper is missing or not executable; run: lmas install --agent codex") && healthy
  } else {
    doctorOk("Codex LMAS wrapper is executable")
  }
  return healthy
}

function doctorClaude() {
  const claudeRoot = join(homedir(), ".claude")
  const claudeCommandTarget = join(claudeRoot, "commands", `${openCodeSkillName}.md`)
  const claudeBinTarget = join(claudeRoot, "lmas", openCodeSkillName, "bin", "lmas.sh")
  const claudeScriptTarget = join(claudeRoot, "lmas", openCodeSkillName, "scripts", "lmas.sh")
  console.log("Claude Code doctor: experimental")
  console.log(`  command: ${claudeCommandTarget}`)
  console.log(`  binary: ${claudeBinTarget}`)
  console.log(`  wrapper: ${claudeScriptTarget}`)
  let healthy = true
  if (!existsSync(claudeCommandTarget)) {
    healthy = doctorFail("Claude Code command is missing; run: lmas install --agent claude") && healthy
  } else {
    doctorOk("Claude Code command is installed")
  }
  if (!isExecutableFile(claudeBinTarget)) {
    healthy = doctorFail("Claude Code LMAS binary asset is missing or not executable; run: lmas install --agent claude") && healthy
  } else {
    doctorOk("Claude Code LMAS binary asset is executable")
  }
  if (!isExecutableFile(claudeScriptTarget)) {
    healthy = doctorFail("Claude Code LMAS wrapper asset is missing or not executable; run: lmas install --agent claude") && healthy
  } else {
    doctorOk("Claude Code LMAS wrapper asset is executable")
  }
  return healthy
}

function removeMarketplaceEntry(marketplace, entryName) {
  if (!Array.isArray(marketplace.plugins)) return marketplace
  marketplace.plugins = marketplace.plugins.filter((plugin) => plugin.name !== entryName)
  return marketplace
}

function installCodex(options) {
  const codexHome = process.env.CODEX_HOME?.trim() || join(homedir(), ".codex")
  const agentsRoot = join(homedir(), ".agents")
  const codexSkillTarget = join(codexHome, "skills", openCodeSkillName)
  const legacyCodexSkillTarget = join(agentsRoot, "skills", openCodeSkillName)
  const legacyNamedCodexSkillTarget = join(agentsRoot, "skills", legacyCodexSkillName)
  const marketplaceDir = join(agentsRoot, "plugins")
  const marketplacePath = join(marketplaceDir, "marketplace.json")
  const legacyCodexPluginTarget = join(marketplaceDir, "plugins", openCodeSkillName)
  const backupRoot = join(agentsRoot, "lmas-backups")

  copyDirAsset(join(paths.codexPlugin, "skills", openCodeSkillName), codexSkillTarget, options)
  moveAside(legacyCodexSkillTarget, join(backupRoot, "skills"), options)
  moveAside(legacyNamedCodexSkillTarget, join(backupRoot, "skills"), options)
  moveAside(legacyCodexPluginTarget, join(backupRoot, "plugins"), options)
  moveMatchingSiblingBackups(join(agentsRoot, "skills"), openCodeSkillName, join(backupRoot, "skills"), options)
  moveMatchingSiblingBackups(join(agentsRoot, "skills"), legacyCodexSkillName, join(backupRoot, "skills"), options)
  moveMatchingSiblingBackups(join(marketplaceDir, "plugins"), openCodeSkillName, join(backupRoot, "plugins"), options)

  if (existsSync(marketplacePath)) {
    const marketplace = readJsonIfExists(marketplacePath, {})
    const original = JSON.stringify(marketplace)
    removeMarketplaceEntry(marketplace, openCodeSkillName)
    if (JSON.stringify(marketplace) !== original) {
      writeText(marketplacePath, `${JSON.stringify(marketplace, null, 2)}\n`, { ...options, force: true })
    }
  }

  console.log("Codex install configured.")
  console.log(`  skill: ${codexSkillTarget}`)
  console.log("  plugin: not installed; Codex uses the standalone skill to avoid duplicate indexing.")
  console.log(`  backups: ${backupRoot}`)
}

function installClaude(options) {
  const claudeRoot = join(homedir(), ".claude")
  const claudeCommandTarget = join(claudeRoot, "commands", `${openCodeSkillName}.md`)
  const claudeAssetsTarget = join(claudeRoot, "lmas", openCodeSkillName)
  const legacyClaudeExperimentalSkillTarget = join(claudeRoot, "skills", legacyClaudeSkillName)
  const legacyClaudeSkillTarget = join(claudeRoot, "skills", openCodeSkillName)
  const backupRoot = join(claudeRoot, "lmas-backups")

  copyFileAsset(paths.claudeCommand, claudeCommandTarget, options)
  copyFileAsset(paths.claudeBin, join(claudeAssetsTarget, "bin", "lmas.sh"), options)
  copyFileAsset(paths.claudeScript, join(claudeAssetsTarget, "scripts", "lmas.sh"), options)
  moveAside(legacyClaudeSkillTarget, join(backupRoot, "skills"), options)
  moveAside(legacyClaudeExperimentalSkillTarget, join(backupRoot, "skills"), options)
  moveMatchingSiblingBackups(join(claudeRoot, "skills"), openCodeSkillName, join(backupRoot, "skills"), options)
  moveMatchingSiblingBackups(join(claudeRoot, "skills"), legacyClaudeSkillName, join(backupRoot, "skills"), options)

  console.log("Claude Code install configured. (experimental; automatic resume is not guaranteed)")
  console.log(`  command: ${claudeCommandTarget}`)
  console.log(`  assets: ${claudeAssetsTarget}`)
  console.log(`  backups: ${backupRoot}`)
}

async function main() {
  const argv = process.argv.slice(2)
  const command = argv[0]

  if (command === "start" || command === "status" || command === "cancel" || command === "list" || command === "__watch") {
    runWrapper(argv)
  }

  const options = parseArgs(argv)
  const detectedAgents = detectAgents()
  const selectedAgents = await chooseAgents(options, detectedAgents)

  if (selectedAgents.length === 0) {
    throw new Error("no install targets selected")
  }

  if (command === "doctor") {
    let healthy = true
    for (const agent of selectedAgents) {
      if (agent === "opencode") healthy = await doctorOpenCode(options) && healthy
      if (agent === "codex") healthy = doctorCodex() && healthy
      if (agent === "claude") healthy = doctorClaude() && healthy
    }
    if (!healthy) process.exit(1)
    console.log("Let My Agent Sleep doctor passed.")
    return
  }

  console.log("Detected agents:")
  for (const agent of detectedAgents) {
    console.log(`  ${agent.detected ? "✓" : "-"} ${agent.label}`)
  }

  for (const agent of selectedAgents) {
    if (agent === "opencode") installOpenCode(options)
    if (agent === "codex") installCodex(options)
    if (agent === "claude") installClaude(options)
  }

  console.log("Let My Agent Sleep install complete.")
  if (selectedAgents.includes("opencode")) {
    console.log("Restart OpenCode so it reloads plugins and skills.")
    console.log("After restart, verify the install with:")
    console.log("  lmas doctor --agent opencode")
    console.log("  lmas doctor --agent opencode --server-url http://127.0.0.1:4096")
  }
  if (selectedAgents.includes("codex")) {
    console.log("Restart Codex so it reloads skills.")
  }
  if (selectedAgents.includes("claude")) {
    console.log("Restart Claude Code so it reloads commands.")
  }
}

main().catch((error) => {
  const command = process.argv[2]
  const commandLabel = command && !command.startsWith("-") ? command : "install"
  console.error(`lmas ${commandLabel} failed: ${error.message}`)
  process.exit(1)
})
