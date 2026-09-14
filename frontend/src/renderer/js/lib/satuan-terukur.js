// Aturan barang yang dijual per ukuran (kilo, liter, meter) — bukan per potong.
//
// Server sejak 2026-09-14 mengirim perilaku jual PER PRODUK: `mode_jual`
// (SATUAN | UKUR | UKUR_NOMINAL, dari master server), `desimal`, `boleh_nominal`,
// `langkah` — hasil pilihan produk, satuan terukur, dan bidang usaha toko. Bila
// ada, itu yang dipakai. Tabel satuan di bawah hanya cadangan untuk server lama
// yang cuma mengirim `satuan` sebagai teks bebas; satuan tak dikenal dianggap
// TIDAK terukur agar perilaku lama (klik = tambah 1) tidak berubah diam-diam.
//
// Setiap fungsi menerima objek produk ATAU teks satuan (pemanggil lama).
//
// Padanan Dart: `mobile-flutter/lib/core/utils/satuan_terukur.dart` dan server
// `Modules/POS/app/Support/PosModeJualProduk.php` — tabel dan pembulatannya
// harus sama persis.

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

/**
 * Perilaku jual satu produk (atau satu teks satuan).
 * @returns {{ terukur: boolean, bolehNominal: boolean, langkah: number, satuan: string }}
 */
export function perilakuJual(produkAtauSatuan) {
  const x = produkAtauSatuan
  if (x && typeof x === 'object') {
    if (x.mode_jual) {
      const langkah = Number(x.langkah)
      const terukur = !!x.desimal
      return {
        terukur,
        bolehNominal: terukur && !!x.boleh_nominal,
        langkah: terukur && langkah > 0 ? langkah : 1,
        satuan: String(x.satuan || '')
      }
    }
    return perilakuJual(x.satuan)
  }
  const terukur = Object.prototype.hasOwnProperty.call(LANGKAH, kunci(x))
  return { terukur, bolehNominal: terukur, langkah: LANGKAH[kunci(x)] || 1, satuan: String(x || '') }
}

/** true bila barang (atau satuan) ini dijual per ukuran. */
export function apakahTerukur(produkAtauSatuan) {
  return perilakuJual(produkAtauSatuan).terukur
}

/** true bila kasir boleh mengisi nominal rupiah ("beli Rp 20.000"). */
export function bolehNominal(produkAtauSatuan) {
  return perilakuJual(produkAtauSatuan).bolehNominal
}

/** Langkah terkecil (1 = barang hitungan biasa). */
export function langkahSatuan(produkAtauSatuan) {
  return perilakuJual(produkAtauSatuan).langkah
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
  // Lewat 6 desimal dulu (sama dengan server): 0.3 / 0.1 = 2.9999999999999996 harus tetap 3.
  const kelipatan = Number((q / langkah).toFixed(6))
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
  const teks = perilakuJual(satuan).satuan.trim()
  return apakahTerukur(satuan) && teks ? `${q} ${teks}` : q
}
