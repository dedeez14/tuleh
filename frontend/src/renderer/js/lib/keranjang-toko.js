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
  if (!t || !t.id) return null
  const keluar = { id: String(t.id), nama: String(t.nama || 'toko sesi') }
  // Kode toko (TK-xxx) stabil — satu-satunya penanda yang bisa dicocokkan dengan daftar toko,
  // karena id adalah ciphertext non-deterministik. Belum semua server mengirimnya.
  if (t.kode) keluar.kode = String(t.kode)
  return keluar
}

/** Nama/kode toko yang bisa dibandingkan: rapi, tak peduli huruf besar-kecil. */
function rapi(nilai) {
  return typeof nilai === 'string' ? nilai.trim().toLowerCase() : ''
}

/**
 * Cocokkan toko sesi dari meta 409 dengan daftar toko pengguna.
 *
 * `id` toko adalah ciphertext non-deterministik (encrypt_id): id yang sama dienkripsi berbeda di
 * `/tokos` dan di meta 409, jadi id TIDAK bisa dipakai membandingkan. Urutan pencocokan: `kode`
 * (TK-xxx, stabil) lalu `nama`. Yang ketemu dipakai untuk melengkapi (bidang usaha dll.), tapi
 * `id`-nya tetap id dari 409 — itu yang sah di server saat ini.
 * Tak ketemu → kembalikan toko sesi apa adanya; server yang berhak menolak, bukan app.
 */
export function pilihTokoSesi(tokoList, sesiToko) {
  if (!sesiToko || !sesiToko.id) return null
  const daftar = Array.isArray(tokoList) ? tokoList : []
  const kode = rapi(sesiToko.kode)
  const nama = rapi(sesiToko.nama)
  const cocok = (kode && daftar.find((t) => rapi(t.kode) === kode))
    || (nama && daftar.find((t) => rapi(t.nama) === nama))
  return cocok ? { ...cocok, id: sesiToko.id } : sesiToko
}

/**
 * Tombol apa yang pantas di bawah galat checkout 409.
 * {mode:'pindah', nama} bila sesi kasir ada di toko lain (server mengirim meta.sesi_toko),
 * {mode:'buka-sesi'} bila 409 tanpa meta (belum ada sesi, atau server lama), null bila bukan 409.
 */
export function labelTombol409(hasil) {
  if (!hasil || hasil.ok || hasil.status !== 409) return null
  const toko = kodeGalat(hasil) === 'SESI_BEDA_TOKO' ? tokoSesi(hasil) : null
  return toko ? { mode: 'pindah', nama: toko.nama } : { mode: 'buka-sesi' }
}
