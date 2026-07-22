'use strict'

// Akses internet publik untuk halaman pelanggan (Cloudflare Quick Tunnel).
//
// Saat diaktifkan (saklar di Pengaturan), PC kasir mendapat URL HTTPS publik
// (https://<acak>.trycloudflare.com) yang meneruskan ke server pelanggan lokal
// — pelanggan memakai kuota datanya sendiri, tidak perlu satu WiFi.
//
// Catatan: Quick Tunnel memberi URL BERBEDA setiap kali dinyalakan. QR yang
// dibuat aplikasi (struk, modal meja, papan TV) selalu memakai URL terbaru;
// untuk QR meja CETAK permanen dibutuhkan domain tetap (tunnel ber-akun atau
// halaman publik server MOVERA — Blueprint §16).

const fs = require('node:fs')
const path = require('node:path')
const { spawn } = require('node:child_process')

const DOWNLOAD_URL = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
const URL_RE = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/
const START_TIMEOUT_MS = 45000

let child = null
let state = { running: false, url: null, starting: false }

function candidatePaths() {
  const paths = []
  try {
    // Tersedia di proses main Electron; tidak ada saat dipakai dari node murni
    const { app } = require('electron')
    paths.push(path.join(app.getPath('userData'), 'bin', 'cloudflared.exe'))
  } catch { /* mode node murni (test) */ }
  if (process.env.LOCALAPPDATA) {
    paths.push(path.join(process.env.LOCALAPPDATA, 'ipos-build', 'bin', 'cloudflared.exe'))
  }
  return paths
}

async function ensureBinary() {
  const candidates = candidatePaths()
  for (const p of candidates) {
    if (fs.existsSync(p)) return p
  }
  // Unduh sekali ke lokasi pertama yang bisa ditulis (userData / LOCALAPPDATA)
  const target = candidates[0]
  if (!target) throw new Error('Lokasi binary tidak tersedia.')
  fs.mkdirSync(path.dirname(target), { recursive: true })
  const res = await fetch(DOWNLOAD_URL)
  if (!res.ok) throw new Error(`Gagal mengunduh cloudflared (HTTP ${res.status}).`)
  const buf = Buffer.from(await res.arrayBuffer())
  fs.writeFileSync(target, buf)
  return target
}

/** Nyalakan tunnel ke port lokal. Resolve { ok, url } atau { ok:false, reason }. */
async function start(localPort) {
  if (state.running) return { ok: true, url: state.url }
  if (state.starting) return { ok: false, reason: 'Tunnel sedang dinyalakan.' }
  state.starting = true

  let bin
  try {
    bin = await ensureBinary()
  } catch (err) {
    state.starting = false
    return { ok: false, reason: err.message }
  }

  return new Promise((resolve) => {
    // --protocol http2: jalur TCP 443 — jaringan yang memblokir QUIC/UDP
    // (umum di WiFi kantor/kampus/warung) tetap bisa tersambung.
    const proc = spawn(bin, [
      'tunnel', '--url', `http://127.0.0.1:${localPort}`,
      '--no-autoupdate', '--protocol', 'http2'
    ], { windowsHide: true })
    child = proc

    let buffer = ''
    let done = false
    let foundUrl = null

    const finish = (result) => {
      if (done) return
      done = true
      state.starting = false
      if (result.ok) {
        state.running = true
        state.url = result.url
      } else {
        try { proc.kill() } catch { /* abaikan */ }
        if (child === proc) child = null
      }
      resolve(result)
    }

    const onData = (chunk) => {
      buffer += String(chunk)
      if (!foundUrl) {
        const match = buffer.match(URL_RE)
        if (match) foundUrl = match[0]
      }
      // Tunggu koneksi ke edge benar-benar terdaftar — URL saja belum berarti
      // tunnel siap menerima trafik.
      if (foundUrl && /Registered tunnel connection/.test(buffer)) {
        finish({ ok: true, url: foundUrl })
      }
      if (/429 Too Many Requests|error.*quick tunnel/i.test(buffer)) {
        finish({ ok: false, reason: 'Layanan quick tunnel sedang membatasi permintaan (coba lagi beberapa menit).' })
      }
    }
    proc.stdout.on('data', onData)
    proc.stderr.on('data', onData)

    proc.on('exit', () => {
      if (child === proc) {
        child = null
        state = { running: false, url: null, starting: false }
      }
      finish({ ok: false, reason: 'cloudflared berhenti sebelum tunnel siap.' })
    })
    proc.on('error', (err) => finish({ ok: false, reason: `Gagal menjalankan cloudflared: ${err.message}` }))

    setTimeout(() => finish({ ok: false, reason: 'Timeout menyalakan tunnel (periksa koneksi internet).' }), START_TIMEOUT_MS)
  })
}

function stop() {
  if (child) {
    try { child.kill() } catch { /* abaikan */ }
    child = null
  }
  state = { running: false, url: null, starting: false }
}

function status() {
  return { running: state.running, url: state.url }
}

module.exports = { start, stop, status }
