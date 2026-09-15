'use strict'

// Akses LAN: pastikan aturan firewall inbound untuk port tracker (Display Pelanggan
// /display & Papan Antrian /antrian) ada, agar TV/HP lain di jaringan bisa mengaksesnya.
// Windows memblokir inbound di jaringan "Public" secara default.
//
// Kapan meminta: HANYA saat pengguna benar-benar memakai tampilan LAN (membuka Papan
// Antrian, atau menekan "Buka akses jaringan") — BUKAN setiap aplikasi dibuka.
// CEK dulu (tanpa admin); hanya bila aturan belum ada → tambahkan (UAC). Permintaan
// otomatis yang ditolak pengguna TIDAK diulang dalam sesi aplikasi yang sama; tombol
// eksplisit ("paksa") tetap boleh meminta lagi karena itu kehendak pengguna.

const { spawn, execFile } = require('node:child_process')

const PORT = Number(process.env.MPOS_TRACK_PORT || 8791)
const RULE = 'Tuleh LAN'

function ruleExists() {
  return new Promise((resolve) => {
    if (process.platform !== 'win32') return resolve(false)
    try {
      execFile('netsh', ['advfirewall', 'firewall', 'show', 'rule', 'name=' + RULE],
        { windowsHide: true, timeout: 8000 }, (err, stdout) => {
          const out = String(stdout || '')
          if (err && !out) return resolve(false)
          // "No rules match the specified criteria." → belum ada
          resolve(!/No rules match/i.test(out))
        })
    } catch { resolve(false) }
  })
}

function addRuleElevated() {
  return new Promise((resolve) => {
    // Susun ArgumentList netsh (tiap arg dikutip single-quote agar aman di PS).
    const argList = [
      'advfirewall', 'firewall', 'add', 'rule',
      'name=' + RULE, 'dir=in', 'action=allow', 'protocol=TCP',
      'localport=' + PORT, 'profile=any'
    ].map((a) => "'" + String(a).replace(/'/g, "''") + "'").join(',')
    // Start-Process -Verb RunAs → memicu UAC. Sukses (disetujui) → exit 0.
    const psCmd = 'Start-Process -FilePath netsh -Verb RunAs -WindowStyle Hidden -ArgumentList @(' + argList + ')'
    try {
      const ps = spawn('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', psCmd], { windowsHide: true })
      ps.on('exit', (code) => resolve(code === 0))
      ps.on('error', () => resolve(false))
    } catch { resolve(false) }
  })
}

/**
 * Inti keputusan (tersuntik agar teruji): { platform, ruleExists, addRule }.
 * ensure({ paksa }) → { ok, added?, already?, reason? }
 */
function buatFirewall({ platform = process.platform, cekAturan = ruleExists, tambahAturan = addRuleElevated } = {}) {
  let ditolakSesiIni = false
  let sedangMeminta = null

  async function ensure({ paksa = false } = {}) {
    if (platform !== 'win32') return { ok: false, reason: 'not-windows' }
    if (sedangMeminta) return sedangMeminta // satu dialog UAC pada satu waktu
    sedangMeminta = (async () => {
      try {
        if (await cekAturan()) return { ok: true, added: false, already: true }
        if (ditolakSesiIni && !paksa) return { ok: false, reason: 'ditolak-sesi-ini' }
        const added = await tambahAturan()
        if (!added) ditolakSesiIni = true
        return { ok: added, added, already: false }
      } catch {
        return { ok: false }
      } finally {
        sedangMeminta = null
      }
    })()
    return sedangMeminta
  }

  return { ensure, sudahDitolak: () => ditolakSesiIni }
}

const bawaan = buatFirewall()

module.exports = { ensure: bawaan.ensure, buatFirewall, ruleExists, PORT, RULE }
