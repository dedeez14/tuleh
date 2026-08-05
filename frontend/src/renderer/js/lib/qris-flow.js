// Helper murni untuk alur QRIS dinamis (Midtrans) — dipisah agar mudah diuji.

/** QRIS Otomatis hanya ditawarkan bila Midtrans aktif untuk toko ini. */
export function midtransBoleh(pembayaran) {
  return !!(pembayaran && pembayaran.midtrans_aktif)
}

/** Status tagihan server → aksi klien. */
export function qrisAksi(status) {
  const s = String(status || '').toUpperCase()
  if (s === 'LUNAS') return 'lunas'
  if (s === 'KEDALUWARSA') return 'kedaluwarsa'
  if (s === 'GAGAL') return 'gagal'
  return 'menunggu'
}

/** Detik tersisa → "m:ss" (tidak pernah negatif). */
export function formatSisa(detik) {
  const d = Math.max(0, Math.floor(Number(detik) || 0))
  const m = Math.floor(d / 60)
  const s = d % 60
  return `${m}:${String(s).padStart(2, '0')}`
}

/** Detik tersisa sampai `expiredAtISO` relatif terhadap `now` (ms). */
export function sisaDetik(expiredAtISO, now) {
  const exp = Date.parse(expiredAtISO)
  if (!Number.isFinite(exp)) return 0
  return Math.max(0, Math.round((exp - (now || 0)) / 1000))
}

/** Label metode bayar di struk: "QRIS (terverifikasi)" bila punya qris_tagihan_id. */
export function labelPembayaranStruk(struk) {
  if (struk && struk.qris_tagihan_id) return 'QRIS (terverifikasi)'
  return (struk && struk.tipe_pembayaran) || 'TUNAI'
}

/** 409 dari POST /qris/tagihan = Midtrans mati mendadak → jatuh ke QRIS statis. */
export function harusFallbackStatis(result) {
  return !!(result && result.ok === false && result.status === 409)
}
