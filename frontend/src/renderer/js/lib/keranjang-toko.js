// Keranjang kasir terikat pada toko tempat item pertama dimasukkan (Tahap B §2a).
//
// Keranjang hidup di level modul `screens/pos.js` dan BERTAHAN saat pindah layar — termasuk saat
// pengguna mengganti toko dari top bar. Tanpa ikatan ini, item toko A bisa dibayar ke toko B
// (server kini menolaknya 409 SESI_BEDA_TOKO, tapi kasir tak tahu kenapa). Modul ini menyimpan
// ringkasan keranjang supaya pemilih toko di app.js bisa bertanya lebih dulu, tanpa app.js perlu
// tahu isi keranjang.

let keranjang = { jumlah: 0, tokoId: null, kosongkan: null }

/** Dipanggil layar kasir tiap keranjang berubah ({jumlah, tokoId, kosongkan?}). */
export function catatKeranjang(info) {
  keranjang = { ...keranjang, ...info }
}

/** Keranjang berisi dan miliknya toko LAIN dari toko yang akan dipilih. */
export function keranjangLain(tokoIdBaru) {
  return keranjang.jumlah > 0 && keranjang.tokoId !== null && String(keranjang.tokoId) !== String(tokoIdBaru)
}

export function ringkasKeranjang() {
  return { jumlah: keranjang.jumlah, tokoId: keranjang.tokoId }
}

/** Kosongkan lewat layar kasir (pengosong yang sama dengan tombol Kosongkan). */
export function kosongkanKeranjang() {
  if (typeof keranjang.kosongkan === 'function') keranjang.kosongkan()
  keranjang = { jumlah: 0, tokoId: null, kosongkan: keranjang.kosongkan }
}

/** Kode mesin galat POS dari amplop server: errors.kode[0] (mis. 'SESI_BEDA_TOKO'). */
export function kodeGalat(hasil) {
  const k = hasil && hasil.errors && hasil.errors.kode
  return Array.isArray(k) && typeof k[0] === 'string' ? k[0] : ''
}

/** Toko sesi dari meta 409 SESI_BEDA_TOKO; null bila server lama tak mengirimkannya. */
export function tokoSesi(hasil) {
  const t = hasil && hasil.meta && hasil.meta.sesi_toko
  return t && t.id ? { id: String(t.id), nama: String(t.nama || 'toko sesi') } : null
}
