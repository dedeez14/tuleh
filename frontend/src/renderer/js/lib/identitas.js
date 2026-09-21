// Identitas sesi (hak akses, peran, perusahaan, sesi kasir, versi manifest) ikut berubah saat app
// terbuka: pemilik mencabut hak dari ERP, manajer menutup sesi kasir dari perangkat lain, menu toko
// diubah. /auth/me tidak ber-ETag, jadi app memanggilnya ulang saat kembali ke depan dengan throttle
// agar berpindah jendela bolak-balik tidak membanjiri server. Fungsi di sini murni (diuji), efeknya
// dijalankan app.js.

export const JEDA_IDENTITAS_MS = 60000

export function perluMuatUlang(terakhirMs, sekarangMs, { jeda = JEDA_IDENTITAS_MS, paksa = false } = {}) {
  if (paksa) return true
  const terakhir = Number(terakhirMs) || 0
  if (terakhir <= 0) return true // belum pernah dimuat (mis. sesudah keluar akun)
  return (Number(sekarangMs) || 0) - terakhir >= jeda
}

/** Patch state dari jawaban /auth/me. `akses` bukan array = tanpa hak (gagal-tertutup). */
export function patchIdentitas(me) {
  const sesi = (me && me.sesi_aktif) || null
  return {
    user: (me && me.user) || null,
    akses: Array.isArray(me && me.akses) ? me.akses : null,
    peran: (me && me.peran) || null,
    company: (me && me.company) || null,
    branch: (me && me.branch) || null,
    session: sesi,
    sessionId: sesi && sesi.id ? sesi.id : null
  }
}

/** Versi manifest toko aktif berbeda dari yang sedang dipakai → manifest perlu dimuat ulang. */
export function manifestBerubah(tokoAktif, tokos) {
  if (!tokoAktif || !Array.isArray(tokos)) return false
  const baru = tokos.find((t) => String(t.id) === String(tokoAktif.id))
  if (!baru) return false
  return Number(baru.manifest_version || 0) !== Number(tokoAktif.manifest_version || 0)
}
