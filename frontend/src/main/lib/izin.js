'use strict'

// Kebijakan izin Chromium (session.setPermissionRequestHandler / CheckHandler):
// TOLAK kecuali yang benar-benar dipakai.
//   - Jendela aplikasi (file://, renderer kita):
//       notifications              → pemantau pesanan meja (pemantau-pesanan.js)
//       clipboard-sanitized-write  → tombol "Salin" (URL LAN, webhook, no. rekening, struk)
//   - Jendela bayar Midtrans (dibuka ipc.js 'langganan:jendelaBayar', https):
//       clipboard-sanitized-write  → salin nomor VA / kode bayar di halaman Snap.
//   Selain itu (kamera, mikrofon, lokasi, MIDI, HID/USB/serial, pointer lock, dll.) ditolak,
//   termasuk halaman https lain yang entah bagaimana termuat.

const IZIN_APLIKASI = new Set(['notifications', 'clipboard-sanitized-write'])
const IZIN_HALAMAN_BAYAR = new Set(['clipboard-sanitized-write'])

const jendelaBayar = new Set() // id webContents jendela bayar yang sedang terbuka

function tandaiJendelaBayar(id) { jendelaBayar.add(id) }
function lepasJendelaBayar(id) { jendelaBayar.delete(id) }

/**
 * @param {string} permission  nama izin Electron
 * @param {{ asalUrl?: string, webContentsId?: number|null }} peminta
 */
function izinkan(permission, { asalUrl = '', webContentsId = null } = {}) {
  const asal = String(asalUrl || '')
  if (asal.startsWith('file://')) return IZIN_APLIKASI.has(permission)
  if (asal.startsWith('https://') && webContentsId !== null && jendelaBayar.has(webContentsId)) {
    return IZIN_HALAMAN_BAYAR.has(permission)
  }
  return false
}

module.exports = { izinkan, tandaiJendelaBayar, lepasJendelaBayar, IZIN_APLIKASI, IZIN_HALAMAN_BAYAR }
