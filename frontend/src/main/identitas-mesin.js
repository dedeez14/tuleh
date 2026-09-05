'use strict'

// Identitas mesin untuk masa coba Mode Demo (lapis 2, pendaftaran perangkat
// di server MOVERA — lihat dokumen "Kontrak Masa Coba Tuléh").
//
//  - perangkatId: SHA-256(MachineGuid | nama pengguna | "tuleh"). MachineGuid
//    (HKLM\SOFTWARE\Microsoft\Cryptography) dibuat saat Windows dipasang dan
//    bertahan saat aplikasi dihapus/dipasang ulang atau folder data dihapus.
//    Bila registry tak terbaca, jatuh ke hostname (lebih lemah, tetap stabil).
//  - sidikJari: hash model/OS/arsitektur — hanya untuk deteksi keanehan.
//  - identitasHmac: kunci lokal untuk tanda catatan (lapis 1).

const crypto = require('node:crypto')
const os = require('node:os')
const { execFileSync } = require('node:child_process')

const sha256 = (s) => crypto.createHash('sha256').update(String(s)).digest('hex')

let cacheGuid = null

function namaPengguna() {
  try { return os.userInfo().username || '' } catch { return '' }
}

/** MachineGuid Windows; '' di OS lain atau bila gagal dibaca. */
function machineGuid() {
  if (cacheGuid !== null) return cacheGuid
  cacheGuid = ''
  if (process.platform !== 'win32') return cacheGuid
  try {
    const out = execFileSync(
      'reg',
      ['query', 'HKLM\\SOFTWARE\\Microsoft\\Cryptography', '/v', 'MachineGuid'],
      { encoding: 'utf8', windowsHide: true, timeout: 3000 }
    )
    const m = out.match(/MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]{36})/)
    cacheGuid = m ? m[1].toLowerCase() : ''
  } catch {
    cacheGuid = ''
  }
  return cacheGuid
}

function perangkatId() {
  const dasar = machineGuid() || os.hostname()
  return sha256(`${dasar}|${namaPengguna()}|tuleh`)
}

function sidikJari() {
  const cpu = (os.cpus()[0] && os.cpus()[0].model) || ''
  return sha256(`${os.platform()}|${os.release()}|${os.arch()}|${cpu}`)
}

/** Identitas untuk HMAC catatan lokal (lapis 1). */
function identitasHmac() {
  return `${os.hostname()}|${namaPengguna()}`
}

module.exports = { perangkatId, sidikJari, identitasHmac, machineGuid, sha256 }
