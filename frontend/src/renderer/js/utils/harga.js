// Harga yang DITAGIH kasir untuk sebuah produk: harga promo bila promo sedang
// aktif (server: promo_aktif + harga_efektif), selain itu harga jual. Satu
// tempat, dipakai kartu katalog, keranjang, timbangan, dan payload checkout —
// sama dengan aplikasi Android (Product.harga).
export function hargaJual(p) {
  if (!p) return 0
  const promo = p.promo_aktif === true && p.harga_efektif != null && p.harga_efektif !== ''
  const n = Number(promo ? p.harga_efektif : p.harga_jual)
  return Number.isFinite(n) ? n : 0
}

/** Harga normal saat promo aktif (untuk dicoret); null bila tidak promo. */
export function hargaNormalSaatPromo(p) {
  if (!p || p.promo_aktif !== true || p.harga_efektif == null) return null
  const n = Number(p.harga_jual)
  return Number.isFinite(n) && n > hargaJual(p) ? n : null
}
