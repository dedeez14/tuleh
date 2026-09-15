// Model ajakan migrasi aplikasi Android lama (Capacitor) → aplikasi utama (kontrak #4).
// Murni (tanpa DOM/jembatan) agar teruji; dirender oleh update.js.

/** Model pita migrasi dari jawaban /app/versi; null bila tidak perlu tampil. */
export function modelMigrasi(info, platformApiAktif) {
  if (platformApiAktif !== 'android-legacy') return null
  const m = info && info.migrasi
  if (!m || m.aktif !== true) return null
  let url = null
  if (typeof m.url === 'string') {
    try {
      const u = new URL(m.url)
      if (u.protocol === 'https:' && u.hostname && !u.username && !u.password) url = u.toString()
    } catch { url = null }
  }
  return {
    judul: typeof m.judul === 'string' ? m.judul.trim() : '',
    pesan: typeof m.pesan === 'string' ? m.pesan.trim() : '',
    url
  }
}

