#!/usr/bin/env node

const { createHash } = require("node:crypto")
const { existsSync, unlinkSync, writeFileSync } = require("node:fs")
const net = require("node:net")

const [socketPath, mode, capturePath, readyPath] = process.argv.slice(2)
if (!socketPath || !mode || !capturePath || !readyPath) {
  throw new Error("usage: mock-codex-app-server.cjs <socket> <success|resume-error|turn-error|late-errors-after-turn|timeout-after-turn> <capture> <ready>")
}

if (existsSync(socketPath)) unlinkSync(socketPath)

const captured = []

function capture(message) {
  captured.push(message)
  writeFileSync(capturePath, `${JSON.stringify(captured, null, 2)}\n`)
}

function frame(message, opcode = 0x1) {
  const payload = Buffer.from(typeof message === "string" ? message : JSON.stringify(message), "utf8")
  let header
  if (payload.length <= 125) {
    header = Buffer.from([0x80 | opcode, payload.length])
  } else if (payload.length <= 0xffff) {
    header = Buffer.allocUnsafe(4)
    header[0] = 0x80 | opcode
    header[1] = 126
    header.writeUInt16BE(payload.length, 2)
  } else {
    header = Buffer.allocUnsafe(10)
    header[0] = 0x80 | opcode
    header[1] = 127
    header.writeBigUInt64BE(BigInt(payload.length), 2)
  }
  return Buffer.concat([header, payload])
}

function parseFrames(state, chunk, onMessage) {
  state.buffer = Buffer.concat([state.buffer, chunk])
  while (state.buffer.length >= 2) {
    const first = state.buffer[0]
    const second = state.buffer[1]
    const opcode = first & 0x0f
    const masked = (second & 0x80) !== 0
    let length = second & 0x7f
    let offset = 2

    if (length === 126) {
      if (state.buffer.length < 4) return
      length = state.buffer.readUInt16BE(2)
      offset = 4
    } else if (length === 127) {
      if (state.buffer.length < 10) return
      length = Number(state.buffer.readBigUInt64BE(2))
      offset = 10
    }

    let mask
    if (masked) {
      if (state.buffer.length < offset + 4) return
      mask = state.buffer.subarray(offset, offset + 4)
      offset += 4
    }
    if (state.buffer.length < offset + length) return

    const payload = Buffer.from(state.buffer.subarray(offset, offset + length))
    state.buffer = state.buffer.subarray(offset + length)
    if (mask) {
      for (let index = 0; index < payload.length; index += 1) payload[index] ^= mask[index % 4]
    }

    if (opcode === 0x8) return
    if (opcode === 0x9) {
      state.socket.write(frame(payload.toString("utf8"), 0xa))
      continue
    }
    if (opcode !== 0x1) continue
    onMessage(JSON.parse(payload.toString("utf8")))
  }
}

const server = net.createServer((socket) => {
  const state = { buffer: Buffer.alloc(0), socket }
  let upgraded = false
  let httpBuffer = Buffer.alloc(0)
  let initializeId = ""
  let resumeId = ""

  const handleMessage = (message) => {
    capture(message)

    if (message.method === "initialize") {
      initializeId = message.id
      socket.write(frame({
        id: message.id,
        result: {
          userAgent: "mock-codex-app-server",
        },
      }))
      return
    }

    if (message.method === "thread/resume") {
      resumeId = message.id
      if (mode === "resume-error") {
        socket.write(frame({ id: message.id, error: { code: -32000, message: "mock resume rejected" } }))
      } else {
        socket.write(frame({
          id: message.id,
          result: { thread: { id: message.params?.threadId } },
        }))
      }
      return
    }

    if (message.method !== "turn/start") return
    if (mode === "success") {
      socket.write(frame({
        id: message.id,
        result: { turn: { id: "mock-turn", status: "inProgress" } },
      }))
    } else if (mode === "turn-error") {
      socket.write(frame({ id: message.id, error: { code: -32001, message: "mock turn rejected" } }))
    } else if (mode === "late-errors-after-turn") {
      socket.write(Buffer.concat([
        frame({ id: initializeId, error: { code: -32002, message: "late initialize error" } }),
        frame({ id: resumeId, error: { code: -32003, message: "late resume error" } }),
      ]))
    } else if (mode !== "timeout-after-turn" && mode !== "resume-error") {
      throw new Error(`unknown mock mode: ${mode}`)
    }
  }

  socket.on("data", (chunk) => {
    if (upgraded) {
      parseFrames(state, chunk, handleMessage)
      return
    }

    httpBuffer = Buffer.concat([httpBuffer, chunk])
    const headerEnd = httpBuffer.indexOf("\r\n\r\n")
    if (headerEnd < 0) return
    const request = httpBuffer.subarray(0, headerEnd).toString("latin1")
    const match = request.match(/^Sec-WebSocket-Key:\s*(.+)$/im)
    if (!match) throw new Error("missing Sec-WebSocket-Key")
    const accept = createHash("sha1")
      .update(`${match[1].trim()}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
      .digest("base64")
    socket.write([
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${accept}`,
      "",
      "",
    ].join("\r\n"))
    upgraded = true
    const remaining = httpBuffer.subarray(headerEnd + 4)
    httpBuffer = Buffer.alloc(0)
    if (remaining.length > 0) parseFrames(state, remaining, handleMessage)
  })

  socket.on("error", () => {})
  socket.on("close", () => server.close())
})

server.listen(socketPath, () => {
  writeFileSync(readyPath, "ready\n")
})

const deadline = setTimeout(() => server.close(), 10_000)
deadline.unref()

process.on("exit", () => {
  if (existsSync(socketPath)) unlinkSync(socketPath)
})
