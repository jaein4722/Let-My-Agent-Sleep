#!/usr/bin/env node

const { createHash, randomBytes, randomUUID } = require("node:crypto")
const { lstatSync, readFileSync } = require("node:fs")
const { homedir } = require("node:os")
const { dirname, join } = require("node:path")
const net = require("node:net")

const EXIT_UNAVAILABLE = 10
const EXIT_AMBIGUOUS = 11
const MAX_FRAME_BYTES = 256 * 1024 * 1024
const MAX_HTTP_HEADER_BYTES = 64 * 1024
const WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
const SAFE_REMOTE_ERRORS = new Set([
  "client-cannot-handle-request",
  "client-not-found",
  "no-client-found",
  "no-handler-for-request",
  "request-version-mismatch",
])

function parseArgs(argv) {
  const options = {
    promptFile: "",
    threadId: "",
    timeoutMs: 15_000,
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === "--thread-id") {
      options.threadId = argv[index + 1] || ""
      index += 1
      continue
    }
    if (arg === "--prompt-file") {
      options.promptFile = argv[index + 1] || ""
      index += 1
      continue
    }
    if (arg === "--timeout-ms") {
      options.timeoutMs = Number(argv[index + 1])
      index += 1
      continue
    }
    throw new Error(`unknown argument: ${arg}`)
  }

  if (!options.threadId) throw new Error("--thread-id is required")
  if (!options.promptFile) throw new Error("--prompt-file is required")
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 100 || options.timeoutMs > 120_000) {
    throw new Error("--timeout-ms must be an integer from 100 to 120000")
  }

  return options
}

function codexHome() {
  return process.env.CODEX_HOME || join(homedir(), ".codex")
}

function desktopIpcEndpoint() {
  if (process.env.LMAS_CODEX_IPC_SOCKET) return process.env.LMAS_CODEX_IPC_SOCKET
  if (process.platform === "win32") return "\\\\.\\pipe\\codex-ipc"
  return join(codexHome(), "ipc", "ipc.sock")
}

function appServerEndpoint() {
  if (process.env.LMAS_CODEX_APP_SERVER_SOCKET) return process.env.LMAS_CODEX_APP_SERVER_SOCKET
  if (process.platform === "win32") return ""
  return join(codexHome(), "app-server-control", "app-server-control.sock")
}

function liveModeDisabled(value) {
  return /^(?:0|false|off|disabled)$/i.test(value || "")
}

function verifyUnixSocket(endpoint, label) {
  if (process.platform === "win32") return

  const uid = process.getuid?.()
  const socketStat = lstatSync(endpoint)
  const directoryStat = lstatSync(dirname(endpoint))

  if (!socketStat.isSocket()) throw new Error(`${label} endpoint is not a Unix socket`)
  if (uid != null && (socketStat.uid !== uid || directoryStat.uid !== uid)) {
    throw new Error(`${label} endpoint is not owned by the current user`)
  }
  if (!directoryStat.isDirectory() || (directoryStat.mode & 0o022) !== 0) {
    throw new Error(`${label} socket directory is writable by another user`)
  }
}

function errorReason(error) {
  if (!error) return "unknown-error"
  if (typeof error === "string") return error
  if (typeof error.code === "string") return error.code
  if (typeof error.message === "string") return error.message
  try {
    return JSON.stringify(error)
  } catch {
    return String(error)
  }
}

function result(kind, endpoint, reason, transport) {
  return { kind, endpoint, reason, transport }
}

function writeOutcome(outcome) {
  process.stdout.write(`${JSON.stringify(outcome)}\n`)
}

function encodeDesktopFrame(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8")
  if (body.length === 0 || body.length > MAX_FRAME_BYTES) {
    throw new Error(`IPC frame is outside the supported size range: ${body.length}`)
  }
  const header = Buffer.allocUnsafe(4)
  header.writeUInt32LE(body.length, 0)
  return Buffer.concat([header, body])
}

function encodeWebSocketFrame(opcode, payload) {
  const body = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, "utf8")
  if (body.length > MAX_FRAME_BYTES) throw new Error(`WebSocket frame is too large: ${body.length}`)

  let headerLength = 2
  if (body.length > 125 && body.length <= 0xffff) headerLength += 2
  else if (body.length > 0xffff) headerLength += 8

  const mask = randomBytes(4)
  const frame = Buffer.allocUnsafe(headerLength + mask.length + body.length)
  frame[0] = 0x80 | opcode

  let offset = 2
  if (body.length <= 125) {
    frame[1] = 0x80 | body.length
  } else if (body.length <= 0xffff) {
    frame[1] = 0x80 | 126
    frame.writeUInt16BE(body.length, 2)
    offset += 2
  } else {
    frame[1] = 0x80 | 127
    frame.writeBigUInt64BE(BigInt(body.length), 2)
    offset += 8
  }

  mask.copy(frame, offset)
  offset += mask.length
  for (let index = 0; index < body.length; index += 1) {
    frame[offset + index] = body[index] ^ mask[index % 4]
  }
  return frame
}

function parseHttpHeaders(headerText) {
  const lines = headerText.split("\r\n")
  const statusLine = lines.shift() || ""
  const headers = new Map()
  for (const line of lines) {
    const separator = line.indexOf(":")
    if (separator <= 0) continue
    headers.set(line.slice(0, separator).trim().toLowerCase(), line.slice(separator + 1).trim())
  }
  return { statusLine, headers }
}

function appServerError(message, fallback) {
  if (!message?.error) return fallback
  if (typeof message.error === "string") return message.error
  if (typeof message.error.message === "string") return message.error.message
  return errorReason(message.error)
}

function attemptAppServer(options, prompt) {
  const endpoint = appServerEndpoint()
  const transport = "codex-app-server"

  if (liveModeDisabled(process.env.LMAS_CODEX_APP_SERVER_WAKE)) {
    return Promise.resolve(result("unavailable", endpoint, "app-server-wake-disabled", transport))
  }
  if (!endpoint) return Promise.resolve(result("unavailable", endpoint, "unsupported-platform", transport))

  try {
    verifyUnixSocket(endpoint, "app-server")
  } catch (error) {
    return Promise.resolve(result("unavailable", endpoint, errorReason(error), transport))
  }

  return new Promise((resolve) => {
    const initializeId = `lmas-initialize-${randomUUID()}`
    const resumeId = `lmas-resume-${randomUUID()}`
    const turnId = `lmas-turn-${randomUUID()}`
    const websocketKey = randomBytes(16).toString("base64")
    const expectedAccept = createHash("sha1").update(`${websocketKey}${WEBSOCKET_GUID}`).digest("base64")
    const socket = net.createConnection(endpoint)

    let finished = false
    let phase = "connecting"
    let timer = null
    let upgraded = false
    let turnDispatched = false
    let httpBuffer = Buffer.alloc(0)
    let websocketBuffer = Buffer.alloc(0)
    let fragmentedOpcode = 0
    let fragmentedPayloads = []
    let fragmentedBytes = 0

    const finish = (kind, reason) => {
      if (finished) return
      finished = true
      if (timer) clearTimeout(timer)
      socket.destroy()
      resolve(result(kind, endpoint, reason, transport))
    }

    const unavailable = (reason) => finish("unavailable", reason)
    const ambiguous = (reason) => finish("ambiguous", reason)
    const delivered = () => finish("delivered", "app-server-acknowledged-turn-start")

    const armTimer = (timeoutMs) => {
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => {
        if (turnDispatched) ambiguous(`timeout-after-${phase}`)
        else unavailable(`timeout-during-${phase}`)
      }, timeoutMs)
    }

    const sendFrame = (opcode, payload) => socket.write(encodeWebSocketFrame(opcode, payload))
    const sendJson = (message) => sendFrame(0x1, JSON.stringify(message))

    const sendInitialize = () => {
      phase = "initialize"
      armTimer(Math.min(options.timeoutMs, 5_000))
      sendJson({
        id: initializeId,
        method: "initialize",
        params: {
          clientInfo: {
            name: "let-my-agent-sleep",
            title: "Let My Agent Sleep",
            version: "0.3.6",
          },
          capabilities: { experimentalApi: true },
        },
      })
    }

    const sendResume = () => {
      phase = "thread-resume"
      armTimer(options.timeoutMs)
      sendJson({
        id: resumeId,
        method: "thread/resume",
        params: { threadId: options.threadId, excludeTurns: true },
      })
    }

    const sendTurn = () => {
      phase = "turn-start"
      turnDispatched = true
      armTimer(options.timeoutMs)
      sendJson({
        id: turnId,
        method: "turn/start",
        params: {
          threadId: options.threadId,
          clientUserMessageId: randomUUID(),
          input: [{ type: "text", text: prompt, text_elements: [] }],
        },
      })
    }

    const handleJsonMessage = (message) => {
      if (message?.id === initializeId) {
        if (message.error || !message.result) {
          unavailable(`initialize-failed:${appServerError(message, "missing-result")}`)
          return
        }
        sendJson({ method: "initialized" })
        sendResume()
        return
      }

      if (message?.id === resumeId) {
        if (message.error || !message.result?.thread) {
          unavailable(`thread-resume-failed:${appServerError(message, "missing-thread")}`)
          return
        }
        sendTurn()
        return
      }

      if (message?.id !== turnId) return
      if (message.error || !message.result?.turn) {
        unavailable(`turn-start-rejected:${appServerError(message, "missing-turn")}`)
        return
      }
      delivered()
    }

    const handleTextMessage = (payload) => {
      try {
        handleJsonMessage(JSON.parse(payload.toString("utf8")))
      } catch (error) {
        if (turnDispatched) ambiguous(`invalid-json-after-dispatch:${error.message}`)
        else unavailable(`invalid-json:${error.message}`)
      }
    }

    const handleWebSocketMessage = (opcode, payload, final) => {
      if (opcode === 0x8) {
        if (turnDispatched) ambiguous("connection-closed-after-dispatch")
        else unavailable("connection-closed-before-dispatch")
        return
      }
      if (opcode === 0x9) {
        sendFrame(0xa, payload)
        return
      }
      if (opcode === 0xa) return

      if (opcode === 0x0) {
        if (!fragmentedOpcode) {
          if (turnDispatched) ambiguous("unexpected-continuation-frame-after-dispatch")
          else unavailable("unexpected-continuation-frame")
          return
        }
        fragmentedPayloads.push(payload)
        fragmentedBytes += payload.length
        if (fragmentedBytes > MAX_FRAME_BYTES) {
          if (turnDispatched) ambiguous("fragmented-message-too-large-after-dispatch")
          else unavailable("fragmented-message-too-large")
          return
        }
        if (!final) return
        const completeOpcode = fragmentedOpcode
        const completePayload = Buffer.concat(fragmentedPayloads, fragmentedBytes)
        fragmentedOpcode = 0
        fragmentedPayloads = []
        fragmentedBytes = 0
        if (completeOpcode === 0x1) handleTextMessage(completePayload)
        return
      }

      if (opcode !== 0x1 && opcode !== 0x2) {
        if (turnDispatched) ambiguous(`unsupported-websocket-opcode-after-dispatch:${opcode}`)
        else unavailable(`unsupported-websocket-opcode:${opcode}`)
        return
      }

      if (!final) {
        fragmentedOpcode = opcode
        fragmentedPayloads = [payload]
        fragmentedBytes = payload.length
        return
      }
      if (opcode === 0x1) handleTextMessage(payload)
    }

    const parseWebSocketFrames = () => {
      while (!finished && websocketBuffer.length >= 2) {
        const first = websocketBuffer[0]
        const second = websocketBuffer[1]
        const final = (first & 0x80) !== 0
        const rsv = first & 0x70
        const opcode = first & 0x0f
        const masked = (second & 0x80) !== 0
        let payloadLength = second & 0x7f
        let offset = 2

        if (rsv !== 0) {
          if (turnDispatched) ambiguous("unsupported-websocket-extension-after-dispatch")
          else unavailable("unsupported-websocket-extension")
          return
        }
        if (payloadLength === 126) {
          if (websocketBuffer.length < 4) return
          payloadLength = websocketBuffer.readUInt16BE(2)
          offset = 4
        } else if (payloadLength === 127) {
          if (websocketBuffer.length < 10) return
          const bigLength = websocketBuffer.readBigUInt64BE(2)
          if (bigLength > BigInt(MAX_FRAME_BYTES)) {
            if (turnDispatched) ambiguous("websocket-frame-too-large-after-dispatch")
            else unavailable("websocket-frame-too-large")
            return
          }
          payloadLength = Number(bigLength)
          offset = 10
        }

        if (payloadLength > MAX_FRAME_BYTES) {
          if (turnDispatched) ambiguous("websocket-frame-too-large-after-dispatch")
          else unavailable("websocket-frame-too-large")
          return
        }

        let mask
        if (masked) {
          if (websocketBuffer.length < offset + 4) return
          mask = websocketBuffer.subarray(offset, offset + 4)
          offset += 4
        }
        if (websocketBuffer.length < offset + payloadLength) return

        const payload = Buffer.from(websocketBuffer.subarray(offset, offset + payloadLength))
        websocketBuffer = websocketBuffer.subarray(offset + payloadLength)
        if (mask) {
          for (let index = 0; index < payload.length; index += 1) payload[index] ^= mask[index % 4]
        }
        handleWebSocketMessage(opcode, payload, final)
      }
    }

    const handleUpgradeData = (chunk) => {
      httpBuffer = Buffer.concat([httpBuffer, chunk])
      if (httpBuffer.length > MAX_HTTP_HEADER_BYTES) {
        unavailable("websocket-upgrade-header-too-large")
        return
      }
      const headerEnd = httpBuffer.indexOf("\r\n\r\n")
      if (headerEnd < 0) return

      const { statusLine, headers } = parseHttpHeaders(httpBuffer.subarray(0, headerEnd).toString("latin1"))
      if (!/^HTTP\/1\.[01] 101(?: |$)/.test(statusLine)) {
        unavailable(`websocket-upgrade-failed:${statusLine || "missing-status"}`)
        return
      }
      if ((headers.get("upgrade") || "").toLowerCase() !== "websocket") {
        unavailable("websocket-upgrade-header-missing")
        return
      }
      if (headers.get("sec-websocket-accept") !== expectedAccept) {
        unavailable("websocket-accept-mismatch")
        return
      }

      upgraded = true
      websocketBuffer = httpBuffer.subarray(headerEnd + 4)
      httpBuffer = Buffer.alloc(0)
      sendInitialize()
      parseWebSocketFrames()
    }

    socket.on("connect", () => {
      phase = "websocket-upgrade"
      armTimer(Math.min(options.timeoutMs, 5_000))
      socket.write([
        "GET / HTTP/1.1",
        "Host: localhost",
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Key: ${websocketKey}`,
        "Sec-WebSocket-Version: 13",
        "",
        "",
      ].join("\r\n"))
    })

    socket.on("data", (chunk) => {
      if (finished || chunk.length === 0) return
      if (!upgraded) {
        handleUpgradeData(chunk)
        return
      }
      websocketBuffer = Buffer.concat([websocketBuffer, chunk])
      parseWebSocketFrames()
    })

    socket.on("error", (error) => {
      if (finished) return
      if (turnDispatched) ambiguous(errorReason(error))
      else unavailable(errorReason(error))
    })

    socket.on("close", () => {
      if (finished) return
      if (turnDispatched) ambiguous("connection-closed-after-dispatch")
      else unavailable("connection-closed-before-dispatch")
    })
  })
}

function attemptDesktopIpc(options, prompt) {
  const endpoint = desktopIpcEndpoint()
  const transport = "desktop-ipc"

  try {
    verifyUnixSocket(endpoint, "desktop IPC")
  } catch (error) {
    return Promise.resolve(result("unavailable", endpoint, errorReason(error), transport))
  }

  return new Promise((resolve) => {
    const initializeRequestId = randomUUID()
    const wakeRequestId = randomUUID()
    const socket = net.createConnection(endpoint)

    let buffer = Buffer.alloc(0)
    let clientId = "initializing-client"
    let finished = false
    let phase = "connecting"
    let timer = null
    let wakeDispatched = false

    const finish = (kind, reason) => {
      if (finished) return
      finished = true
      if (timer) clearTimeout(timer)
      socket.destroy()
      resolve(result(kind, endpoint, reason, transport))
    }

    const unavailable = (reason) => finish("unavailable", reason)
    const ambiguous = (reason) => finish("ambiguous", reason)
    const delivered = () => finish("delivered", "owner-acknowledged-turn-start")

    const armTimer = (timeoutMs) => {
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => {
        if (wakeDispatched) ambiguous(`timeout-after-${phase}`)
        else unavailable(`timeout-during-${phase}`)
      }, timeoutMs)
    }

    const send = (message) => socket.write(encodeDesktopFrame(message))

    const sendWake = () => {
      phase = "wake-request"
      wakeDispatched = true
      armTimer(options.timeoutMs)
      send({
        type: "request",
        requestId: wakeRequestId,
        sourceClientId: clientId,
        version: 1,
        method: "thread-follower-start-turn",
        params: {
          conversationId: options.threadId,
          turnStartParams: {
            clientUserMessageId: randomUUID(),
            input: [{ type: "text", text: prompt, text_elements: [] }],
          },
        },
        timeoutMs: options.timeoutMs,
      })
    }

    const handleMessage = (message) => {
      if (message?.type === "client-discovery-request" && typeof message.requestId === "string") {
        send({
          type: "client-discovery-response",
          requestId: message.requestId,
          response: { canHandle: false },
        })
        return
      }

      if (message?.type !== "response") return

      if (message.requestId === initializeRequestId) {
        if (phase !== "initialize") return
        if (message.resultType !== "success" || typeof message.result?.clientId !== "string") {
          unavailable(message.error || "initialize-failed")
          return
        }
        clientId = message.result.clientId
        sendWake()
        return
      }

      if (message.requestId !== wakeRequestId) return
      if (message.resultType === "success") {
        delivered()
        return
      }

      const remoteError = typeof message.error === "string" ? message.error : "wake-request-failed"
      if (SAFE_REMOTE_ERRORS.has(remoteError)) unavailable(remoteError)
      else ambiguous(remoteError)
    }

    socket.on("connect", () => {
      phase = "initialize"
      armTimer(Math.min(options.timeoutMs, 5_000))
      try {
        send({
          type: "request",
          requestId: initializeRequestId,
          sourceClientId: clientId,
          version: 0,
          method: "initialize",
          params: { clientType: "let-my-agent-sleep" },
        })
      } catch (error) {
        unavailable(error.message)
      }
    })

    socket.on("data", (chunk) => {
      if (finished || chunk.length === 0) return
      buffer = Buffer.concat([buffer, chunk])

      while (buffer.length >= 4) {
        const frameLength = buffer.readUInt32LE(0)
        if (frameLength === 0 || frameLength > MAX_FRAME_BYTES) {
          if (wakeDispatched) ambiguous(`invalid-frame-length:${frameLength}`)
          else unavailable(`invalid-frame-length:${frameLength}`)
          return
        }
        if (buffer.length < frameLength + 4) return

        const body = buffer.subarray(4, frameLength + 4)
        buffer = buffer.subarray(frameLength + 4)
        try {
          handleMessage(JSON.parse(body.toString("utf8")))
        } catch (error) {
          if (wakeDispatched) ambiguous(`invalid-response:${error.message}`)
          else unavailable(`invalid-response:${error.message}`)
          return
        }
        if (finished) return
      }
    })

    socket.on("error", (error) => {
      if (finished) return
      if (wakeDispatched) ambiguous(errorReason(error))
      else unavailable(errorReason(error))
    })

    socket.on("close", () => {
      if (finished) return
      if (wakeDispatched) ambiguous("connection-closed-after-dispatch")
      else unavailable("connection-closed-before-dispatch")
    })
  })
}

async function main() {
  let options
  let prompt
  try {
    options = parseArgs(process.argv.slice(2))
    prompt = readFileSync(options.promptFile, "utf8")
    if (!prompt.trim()) throw new Error("resume prompt is empty")
  } catch (error) {
    writeOutcome(result("unavailable", desktopIpcEndpoint(), errorReason(error), "input"))
    process.exitCode = EXIT_UNAVAILABLE
    return
  }

  const appServerResult = await attemptAppServer(options, prompt)
  writeOutcome(appServerResult)
  if (appServerResult.kind === "delivered") return
  if (appServerResult.kind === "ambiguous") {
    process.exitCode = EXIT_AMBIGUOUS
    return
  }

  const desktopResult = await attemptDesktopIpc(options, prompt)
  writeOutcome(desktopResult)
  if (desktopResult.kind === "delivered") return
  process.exitCode = desktopResult.kind === "ambiguous" ? EXIT_AMBIGUOUS : EXIT_UNAVAILABLE
}

main().catch((error) => {
  writeOutcome(result("ambiguous", desktopIpcEndpoint(), errorReason(error), "orchestrator"))
  process.exitCode = EXIT_AMBIGUOUS
})
