// Jembatan tipis ke main process (window.iposAPI dari preload).
// Semua metode mengembalikan envelope ternormalisasi:
//   { ok: true, data, meta } | { ok: false, status, message, errors }

const bridge = window.iposAPI

if (!bridge) {
  throw new Error('Bridge iposAPI tidak tersedia — preload gagal dimuat.')
}

// Gerbang 403 (Tahap B §2b): hak akses bisa dicabut/ditambah pemilik saat app terbuka. Setiap
// penolakan hak memicu satu kali muat ulang identitas (dipasang app.js) supaya tombol & menu ikut
// menyesuaikan; permintaannya sendiri tetap gagal — server yang berwenang.
let onTolakHak = null

export function pasangTolakHak(fn) {
  onTolakHak = typeof fn === 'function' ? fn : null
}

function bungkusGerbang(permukaan) {
  const keluar = {}
  for (const grup of Object.keys(permukaan)) {
    const isi = permukaan[grup]
    if (!isi || typeof isi !== 'object') {
      keluar[grup] = isi
      continue
    }
    keluar[grup] = {}
    for (const nama of Object.keys(isi)) {
      const fn = isi[nama]
      // Fungsi berlangganan (onStatus, onExpired, …) mengembalikan PELEPAS — jangan dijadikan Promise.
      keluar[grup][nama] = typeof fn === 'function' && !nama.startsWith('on')
        ? async (...args) => {
            const hasil = await fn(...args)
            if (hasil && hasil.ok === false && hasil.status === 403 && onTolakHak) {
              try { await onTolakHak() } catch { /* gagal-terbuka: jangan menutupi galat aslinya */ }
            }
            return hasil
          }
        : fn
    }
  }
  return keluar
}

export const api = bungkusGerbang(bridge)

/** Ambil pesan error pertama dari envelope gagal (termasuk error validasi 422). */
export function firstError(result) {
  if (!result || result.ok) return ''
  if (result.errors && typeof result.errors === 'object') {
    const firstKey = Object.keys(result.errors)[0]
    const messages = firstKey ? result.errors[firstKey] : null
    if (Array.isArray(messages) && messages.length > 0) return messages[0]
  }
  return result.message || 'Terjadi kesalahan.'
}
