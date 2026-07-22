'use strict'

// Auto-start gateway Go (mpos-backend) dari aplikasi.
//
// Saat aplikasi dibuka, gateway dinyalakan otomatis dan seluruh permintaan API
// dialirkan melewatinya (cache + rate limit + allowlist). Bila sudah ada
// gateway berjalan dengan upstream yang sama (mis. dijalankan manual lewat
// run-backend.ps1), instance itu dipakai ulang dan TIDAK dimatikan saat keluar.
// Bila binary tidak ditemukan / gagal start, aplikasi otomatis jatuh kembali
// ke koneksi langsung — fitur tetap jalan, hanya tanpa akselerasi.

const fs = require('node:fs')
const path = require('node:path')
const { spawn } = require('node:child_process')
const { app } = require('electron')

const PORTS = [8787, 8788, 8789, 8790]
const PROBE_TIMEOUT_MS = 700
const START_WAIT_MS = 2500
const START_POLL_MS = 250

let child = null
let state = { running: false, port: null, upstream: null, external: false }

function exePath() {
  const name = process.platform === 'win32' ? 'mpos-backend.exe' : 'mpos-backend'
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'backend', name)
  }
  // Mode pengembangan: hasil build tools/run-backend.ps1
  return path.join(app.getPath('appData'), '..', 'Local', 'ipos-build', 'backend', name)
}

async function probeHealth(port) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS)
  try {
    const res = await fetch(`http://127.0.0.1:${port}/healthz`, { signal: controller.signal })
    if (!res.ok) return null
    const payload = await res.json()
    if (payload && payload.success && payload.data && payload.data.app === 'mpos-backend') {
      return payload.data // { app, version, upstream, time }
    }
    return null
  } catch {
    return null
  } finally {
    clearTimeout(timer)
  }
}

function spawnGateway(port, upstream) {
  const exe = exePath()
  const proc = spawn(exe, [], {
    env: {
      ...process.env,
      MPOS_LISTEN: `127.0.0.1:${port}`,
      MPOS_UPSTREAM: upstream
    },
    stdio: 'ignore',
    windowsHide: true
  })
  proc.on('exit', () => {
    if (child === proc) {
      child = null
      state = { running: false, port: null, upstream: null, external: false }
    }
  })
  proc.on('error', () => {
    if (child === proc) child = null
  })
  return proc
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

/**
 * Pastikan gateway berjalan untuk upstream tertentu.
 * @returns {Promise<{ok: boolean, port?: number, external?: boolean, reason?: string}>}
 */
async function ensureRunning(upstream) {
  // Upstream lokal berarti pengguna sudah menunjuk server lokal sendiri —
  // jangan tumpuk gateway di atasnya (hindari loop).
  let host
  try {
    host = new URL(upstream).hostname
  } catch {
    return { ok: false, reason: 'upstream tidak valid' }
  }
  if (host === 'localhost' || host === '127.0.0.1') {
    return { ok: false, reason: 'upstream lokal' }
  }

  if (!fs.existsSync(exePath())) {
    return { ok: false, reason: 'binary tidak ditemukan' }
  }

  const freePorts = []
  for (const port of PORTS) {
    const health = await probeHealth(port)
    if (health) {
      if (health.upstream === upstream) {
        state = { running: true, port, upstream, external: child === null }
        return { ok: true, port, external: state.external }
      }
      continue // port terisi gateway lain (upstream beda) — cari port lain
    }
    freePorts.push(port)
  }

  for (const port of freePorts) {
    const proc = spawnGateway(port, upstream)
    const deadline = Date.now() + START_WAIT_MS
    while (Date.now() < deadline) {
      await sleep(START_POLL_MS)
      const health = await probeHealth(port)
      if (health && health.upstream === upstream) {
        child = proc
        state = { running: true, port, upstream, external: false }
        return { ok: true, port, external: false }
      }
      if (proc.exitCode !== null) break // gagal start (mis. port direbut) → coba port lain
    }
    try { proc.kill() } catch { /* sudah mati */ }
  }

  return { ok: false, reason: 'gagal memulai gateway' }
}

/** Matikan gateway HANYA bila kita yang menyalakannya. */
function stop() {
  if (child) {
    try { child.kill() } catch { /* abaikan */ }
    child = null
  }
  state = { running: false, port: null, upstream: null, external: false }
}

async function restart(upstream) {
  stop()
  return ensureRunning(upstream)
}

function status() {
  return { ...state }
}

module.exports = { ensureRunning, restart, stop, status }
