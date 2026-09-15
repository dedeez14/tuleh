'use strict'

// Auto-start gateway Go (mpos-backend) dari aplikasi.
//
// Saat aplikasi dibuka, gateway dinyalakan otomatis dan seluruh permintaan API
// dialirkan melewatinya (cache + rate limit + allowlist). Gateway yang sudah berjalan
// dipakai ulang HANYA bila upstream DAN versinya sama dengan aplikasi. Bila binary
// tidak ditemukan / gagal start / proses keluar, aplikasi segera kembali ke koneksi
// langsung dan pengawas mencoba menyalakannya lagi dengan mundur (lib/pengawas-gateway.js).
// stdout/stderr gateway masuk ke logs/gateway.log.

const fs = require('node:fs')
const path = require('node:path')
const { spawn } = require('node:child_process')
const { app } = require('electron')
const { buatPengawasGateway } = require('./lib/pengawas-gateway')
const diagnostik = require('./diagnostik')

const PROBE_TIMEOUT_MS = 700

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

let pendengarBerubah = () => {}

const pengawas = buatPengawasGateway({
  exePath,
  existsSync: (p) => fs.existsSync(p),
  spawn: (exe, env) => spawn(exe, [], {
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true
  }),
  probe: probeHealth,
  versiApp: app.getVersion(),
  onBerubah: (st) => { try { pendengarBerubah(st) } catch { /* abaikan */ } },
  log: (baris) => diagnostik.log('gateway', 'info', baris)
})

/** Pasang pendengar perubahan status (ipc.js: atur transport api-client). */
function onBerubah(fn) { pendengarBerubah = typeof fn === 'function' ? fn : () => {} }

module.exports = {
  ensureRunning: (upstream) => pengawas.pastikan(upstream),
  restart: (upstream) => pengawas.mulaiUlang(upstream),
  stop: () => pengawas.hentikan(),
  laporGagal: () => pengawas.laporGagal(),
  status: () => pengawas.status(),
  onBerubah
}
