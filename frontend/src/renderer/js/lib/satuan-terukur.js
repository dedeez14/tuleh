// Aturan barang yang dijual per ukuran (kilo, liter, meter) — bukan per potong.
// Server hanya mengirim `satuan` sebagai teks bebas, jadi klien yang
// menerjemahkannya. Satuan tak dikenal dianggap TIDAK terukur agar perilaku
// lama (klik = tambah 1) tidak berubah diam-diam.
//
// Padanan Dart: `mobile-flutter/lib/core/utils/satuan_terukur.dart` — tabel dan
// pembulatannya harus sama persis di kedua aplikasi.

const LANGKAH = {
  kg: 0.01,
  kilo: 0.01,
  kilogram: 0.01,
  gram: 10,
  gr: 10,
  g: 10,
  ons: 0.1,
  liter: 0.01,
  ltr: 0.01,
  l: 0.01,
  ml: 10,
  meter: 0.1,
  mtr: 0.1,
  m: 0.1
}

const kunci = (satuan) => String(satuan || '').trim().toLowerCase()

/** true bila barang dengan satuan ini dijual per ukuran. */
export function apakahTerukur(satuan) {
  return Object.prototype.hasOwnProperty.call(LANGKAH, kunci(satuan))
}

/** Langkah terkecil untuk satuan (1 = barang hitungan biasa). */
export function langkahSatuan(satuan) {
  return LANGKAH[kunci(satuan)] || 1
}

/**
 * Bulatkan kuantitas ke kelipatan langkah satuannya.
 * `keBawah` dipakai saat kuantitas berasal dari nominal: tagihan tidak boleh
 * melebihi uang yang diminta pelanggan.
 */
export function bulatkanKuantitas(kuantitas, satuan, { keBawah = false } = {}) {
  const langkah = langkahSatuan(satuan)
  const q = Number(kuantitas)
  if (!(langkah > 0) || !(q > 0)) return 0
  const kelipatan = q / langkah
  const bulat = keBawah ? Math.floor(kelipatan) : Math.round(kelipatan)
  // Lewat 6 desimal agar 0.1*3 tidak menjadi 0.30000000000000004.
  return Number((bulat * langkah).toFixed(6))
}

/**
 * Kuantitas yang setara dengan `nominal` rupiah pada `harga` per satuan.
 * 0 = harga tak sah atau nominal belum cukup untuk satu langkah.
 */
export function kuantitasDariNominal(nominal, harga, satuan) {
  const n = Number(nominal)
  const h = Number(harga)
  if (!(h > 0) || !(n > 0)) return 0
  return bulatkanKuantitas(n / h, satuan, { keBawah: true })
}

/** Nominal terkecil yang bisa dilayani (satu langkah). */
export function minimalNominal(harga, satuan) {
  return Math.ceil(Number(harga) * langkahSatuan(satuan))
}

/** Uang untuk kuantitas pada harga — dibulatkan ke rupiah penuh. */
export function totalBaris(kuantitas, harga) {
  return Math.round(Number(kuantitas) * Number(harga))
}

/**
 * "0,74 kg" untuk barang terukur, "2" untuk barang hitungan.
 *
 * Satuan hanya ikut dicetak bila barangnya memang dijual per ukuran: pada
 * barang hitungan "2 pcs" tidak menambah informasi apa pun.
 */
export function labelKuantitas(kuantitas, satuan) {
  const q = new Intl.NumberFormat('id-ID', { maximumFractionDigits: 3 }).format(
    Number(kuantitas) || 0,
  )
  return apakahTerukur(satuan) ? `${q} ${String(satuan).trim()}` : q
}
