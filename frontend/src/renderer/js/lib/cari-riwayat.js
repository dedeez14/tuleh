// Pencarian di Riwayat Transaksi — dijalankan pada baris yang sudah dimuat
// (tanpa permintaan baru ke server) agar tetap bekerja saat offline dan atas
// struk lokal yang belum sinkron. Padanan `saring_riwayat.dart` di Android.

/** Angka saja: "Rp 25.000" dan "25000" jadi kunci pencarian yang sama. */
export function angkaSaja(teks) {
  return String(teks ?? '').replace(/[^0-9]/g, '')
}

/**
 * Cocokkan satu baris transaksi dengan kata kunci.
 * Mencari di nomor nota, metode bayar, status, dan nominal.
 */
export function cocokRiwayat(trx, kueri) {
  const q = String(kueri ?? '').trim().toLowerCase()
  if (!q) return true
  if (!trx) return false

  const nomor = String(trx.nomor ?? trx.no ?? '').toLowerCase()
  if (nomor.includes(q)) return true

  const metode = String(trx.tipe_pembayaran ?? trx.metode_bayar ?? trx.metode ?? '').toLowerCase()
  if (metode && metode.includes(q)) return true

  const status = String(trx.status ?? '').toLowerCase()
  if (status && status.includes(q)) return true

  const angka = angkaSaja(q)
  if (angka) {
    const total = Math.round(Number(trx.grand_total ?? trx.total) || 0)
    if (String(total).includes(angka)) return true
  }
  return false
}

/** Saring daftar baris (urutan asal dipertahankan). */
export function cariRiwayat(rows, kueri) {
  if (!Array.isArray(rows)) return []
  const q = String(kueri ?? '').trim()
  if (!q) return rows
  return rows.filter((trx) => cocokRiwayat(trx, q))
}
