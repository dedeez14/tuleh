'use strict'

// Buka akses LAN otomatis: pastikan aturan firewall inbound untuk port tracker
// (Display Pelanggan /display & Papan Antrian /antrian) ada, agar TV/HP lain di
// jaringan bisa mengaksesnya. Windows memblokir inbound di jaringan "Public"
// secara default — inilah penyebab umum "URL tak terbuka di TV".
//
// Strategi anti-UAC-berulang: CEK dulu (tanpa admin); hanya bila aturan belum
// ada → tambahkan (netsh dijalankan elevated via PowerShell → UAC SEKALI).
// Setelah disetujui, aturan permanen → start berikutnya tak memunculkan prompt.

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
 * Pastikan aturan firewall LAN ada. Aman dipanggil tiap start: bila sudah ada,
 * TIDAK ada prompt. Mengembalikan { ok, added, already }.
 */
async function ensure() {
  if (process.platform !== 'win32') return { ok: false, reason: 'not-windows' }
  try {
    if (await ruleExists()) return { ok: true, added: false, already: true }
    const added = await addRuleElevated()
    return { ok: added, added, already: false }
  } catch {
    return { ok: false }
  }
}

module.exports = { ensure, ruleExists, PORT, RULE }
