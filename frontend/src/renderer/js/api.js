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

// Gerbang dijalankan TERPISAH dari permintaan yang memicunya. Muat ulang identitas bisa
// menggambar ulang kerangka & layar, dan itu tak boleh terjadi di tengah `await` pemanggil: elemen
// DOM yang ia pegang sebelum await akan basi, dan modalnya bisa tertinggal di atas layar baru.
// Hasilnya tak dipakai siapa pun, jadi sengaja tidak di-await.
function picuTolakHak() {
  const fn = onTolakHak
  if (!fn) return
  setTimeout(() => {
    try { Promise.resolve(fn()).catch(() => { /* gagal-terbuka */ }) } catch { /* gagal-terbuka */ }
  }, 0)
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
            // Permintaannya sendiri tetap gagal - server yang berwenang; app hanya menyegarkan hak.
            if (hasil && hasil.ok === false && hasil.status === 403) picuTolakHak()
            return hasil
          }
        : fn
    }
  }
  return keluar
}

export const api = bungkusGerbang(bridge)

// Nilai yang bentuknya kode mesin ('SESI_BEDA_TOKO', 'BERAKHIR') — untuk dibaca program, bukan
// dipampang ke kasir. Amplop 409 sesi-beda-toko hanya berisi errors.kode, kalimatnya di `message`.
const KODE_MESIN = /^[A-Z][A-Z0-9_]*$/

/** Ambil pesan error pertama dari envelope gagal (termasuk error validasi 422). */
export function firstError(result) {
  if (!result || result.ok) return ''
  if (result.errors && typeof result.errors === 'object') {
    for (const kunci of Object.keys(result.errors)) {
      if (kunci === 'kode') continue
      const pesan = result.errors[kunci]
      if (!Array.isArray(pesan) || pesan.length === 0) continue
      if (typeof pesan[0] === 'string' && KODE_MESIN.test(pesan[0])) continue
      return pesan[0]
    }
  }
  return result.message || 'Terjadi kesalahan.'
}
