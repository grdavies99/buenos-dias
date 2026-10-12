#!/usr/bin/env node
'use strict'

// Zero-config LAN discovery + companion command client for the buenos-dias
// Roku channel's custom mDNS/companion protocol (see
// source/components/networkBroadcastTask.brs and udpServer.brs). This plays
// the role of the "phone" side: no pairing code, no IP entry - it finds the
// TV over mDNS and can push it a command.

const dgram = require('dgram')
const dnsPacket = require('dns-packet')

const MDNS_ADDR = '224.0.0.251'
const MDNS_PORT = 5353
const SERVICE_NAME = '_adge._udp.local'
const COMPANION_PORT = 16809

function parseArgs(argv) {
  const args = { timeoutMs: 3000 }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--remote') args.remote = argv[++i]
    else if (a === '--deeplink') args.deeplink = argv[++i]
    else if (a === '--timeout') args.timeoutMs = Number(argv[++i])
    else if (a === '--help' || a === '-h') args.help = true
  }
  return args
}

function printHelp() {
  console.log(`
adge-discover - zero-config LAN discovery for the buenos-dias Roku companion protocol

Usage:
  node discover.js [--timeout ms] [--remote <value> | --deeplink <url>]

Discovers any Roku on the LAN advertising "${SERVICE_NAME}" via mDNS, then
optionally sends one companion command to it over the UDP control channel.
`)
}

function buildQuery() {
  return dnsPacket.encode({
    type: 'query',
    id: 0,
    flags: 0,
    questions: [
      { type: 'PTR', name: SERVICE_NAME, class: 'IN' },
      { type: 'SRV', name: SERVICE_NAME, class: 'IN' },
      { type: 'A', name: SERVICE_NAME, class: 'IN' },
    ],
  })
}

// The responder answers PTR/SRV/A in one packet keyed inconsistently (PTR and
// SRV by the service/instance name, A by the SRV target name), so we merge
// them into one record per device as messages arrive.
function discover(timeoutMs) {
  return new Promise((resolve, reject) => {
    const socket = dgram.createSocket({ type: 'udp4', reuseAddr: true })
    const devices = new Map() // instance name -> { instanceName, target, port, ip }
    const pendingIpsByTarget = new Map() // target name -> ip, for A records seen before their SRV

    function upsert(instanceName) {
      if (!devices.has(instanceName)) devices.set(instanceName, { instanceName })
      return devices.get(instanceName)
    }

    socket.on('error', reject)

    socket.on('message', (msg) => {
      let packet
      try {
        packet = dnsPacket.decode(msg)
      } catch (err) {
        return // not a well-formed DNS packet - ignore other LAN mDNS chatter
      }

      for (const answer of packet.answers || []) {
        if (answer.type === 'PTR' && answer.name === SERVICE_NAME) {
          upsert(answer.data)
        } else if (answer.type === 'SRV') {
          const dev = upsert(answer.name)
          dev.target = answer.data.target
          dev.port = answer.data.port
          if (pendingIpsByTarget.has(dev.target)) dev.ip = pendingIpsByTarget.get(dev.target)
        } else if (answer.type === 'A') {
          pendingIpsByTarget.set(answer.name, answer.data)
          for (const dev of devices.values()) {
            if (dev.target === answer.name) dev.ip = answer.data
          }
        }
      }
    })

    socket.bind(MDNS_PORT, () => {
      socket.addMembership(MDNS_ADDR)
      socket.setMulticastTTL(255)
      const query = buildQuery()
      socket.send(query, 0, query.length, MDNS_PORT, MDNS_ADDR)
    })

    setTimeout(() => {
      socket.close()
      resolve([...devices.values()].filter((d) => d.ip && d.port))
    }, timeoutMs)
  })
}

function sendCommand(ip, command) {
  return new Promise((resolve, reject) => {
    const socket = dgram.createSocket('udp4')
    const payload = Buffer.from(command, 'utf8')
    socket.send(payload, 0, payload.length, COMPANION_PORT, ip, (err) => {
      socket.close()
      if (err) reject(err)
      else resolve()
    })
  })
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) return printHelp()

  console.log(`Searching for "${SERVICE_NAME}" on the LAN (${args.timeoutMs}ms)...`)
  const devices = await discover(args.timeoutMs)

  if (devices.length === 0) {
    console.log('No devices found. Is the channel running and on the same network/subnet?')
    process.exitCode = 1
    return
  }

  for (const d of devices) {
    console.log(`Found: ${d.instanceName}  ip=${d.ip}  port=${d.port}  target=${d.target}`)
  }

  const command = args.deeplink ? `deeplink:${args.deeplink}` : args.remote ? `remote:${args.remote}` : null

  if (command) {
    const target = devices[0]
    console.log(`Sending "${command}" to ${target.ip}:${COMPANION_PORT}...`)
    await sendCommand(target.ip, command)
    console.log('Sent.')
  }
}

main().catch((err) => {
  console.error(err)
  process.exitCode = 1
})
