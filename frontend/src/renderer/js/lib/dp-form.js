// Uang muka (DP) pesanan bayar-nanti — logika murni (tanpa DOM/state), dipakai layar kasir & papan pesanan.
// Server menghitung total pesanan dari harga katalog × kuantitas (tanpa diskon & pajak), jadi batas DP di sini
// memakai hitungan yang sama agar pesan galat app = keputusan server.

/** Kasir selalu bisa Lunas; Bayar nanti & Uang muka hanya bila alur toko PAYMENT_OR_LATER. */
export function modeBayarTersedia(manifest) {
  // Manifest desktop memakai transactionFlow; Mode Demo & jawaban mentah server memakai transaction_flow.
  const alur = (manifest && (manifest.transactionFlow || manifest.transaction_flow)) || []
  return alur.includes('PAYMENT_OR_LATER') ? ['LUNAS', 'NANTI', 'DP'] : ['LUNAS']
}

export function totalNota(items) {
  return (items || []).reduce((s, i) => s + (Number(i.harga) || 0) * (Number(i.kuantitas) || 0), 0)
}

/** @returns {string|null} pesan galat untuk kasir, atau null bila sah. */
export function validasiUangMuka({ jumlah, total, metode }) {
  const n = Number(jumlah)
  if (!Number.isFinite(n) || n <= 0) return 'Isi uang muka lebih dari Rp0.'
  if (n >= Number(total)) return 'Uang muka harus kurang dari total pesanan. Untuk bayar penuh pilih Lunas.'
  if (!metode) return 'Pilih metode pembayaran uang muka.'
  return null
}

/** Payload kanal order:simpanNota. */
export function susunNota({ mode, items, idPelanggan, catatan, uangMuka, metodeUangMuka, clientRef }) {
  if (mode !== 'NANTI' && mode !== 'DP') throw new Error('Nota hanya untuk Bayar nanti atau Uang muka.')
  const nota = { bayar: mode, items, idPelanggan, catatan, clientRef }
  if (mode === 'DP') nota.dp = { jumlah: Number(uangMuka), tipePembayaran: metodeUangMuka }
  return nota
}

/** Teks ringkas kartu papan: "DP Rp10.000 · sisa Rp18.000" / "Belum bayar · Rp28.000" / '' (lunas, bon). */
export function ringkasBayar(order, fmt) {
  if (!order) return ''
  if (order.bayar === 'DP') return `DP ${fmt(Number(order.dibayar) || 0)} · sisa ${fmt(Number(order.sisa) || 0)}`
  if (order.bayar === 'BELUM') return `Belum bayar · ${fmt(Number(order.sisa) || Number(order.total) || 0)}`
  return ''
}

/** Pesanan yang masih punya tagihan (tombol Lunasi). BON dilunasi lewat bill, bukan di papan. */
export function perluDilunasi(order) {
  return !!order && (order.bayar === 'BELUM' || order.bayar === 'DP')
}

/**
 * Harga satuan untuk nota bayar-nanti / uang muka = harga katalog `harga_jual`. Server (dan Mode Demo)
 * menghargai pesanan dari katalog; harga promo kasir (`hargaJual`) tidak ikut, jadi total & batas DP di layar
 * dihitung dari angka yang sama dengan server.
 */
export function hargaNota(produk) {
  const n = Number(produk && produk.harga_jual)
  return Number.isFinite(n) ? n : 0
}

/** Blok bantu uang muka per metode: QR statis (QRIS) / daftar rekening (TRANSFER); tunai & QRIS Otomatis tanpa blok. */
export function blokUangMuka(metode) {
  return metode === 'QRIS' || metode === 'TRANSFER' ? metode : null
}

/** Tombol metode yang terlihat, urut tampil (pintasan F5–F7 & judulnya mengikuti daftar ini). */
export function tombolMetodeTerlihat(list, tersembunyi = (b) => !!(b && b.hidden)) {
  return (list || []).filter((b) => !tersembunyi(b))
}

/** Tombol metode ke-`idx` di antara yang terlihat — tombol tersembunyi (mis. QRIS Otomatis saat uang muka) dilewati. */
export function pilihTombolMetode(list, idx, tersembunyi) {
  return tombolMetodeTerlihat(list, tersembunyi)[idx] || null
}

/** Jumlah tagihan pelunasan: sisa, jatuh ke total (server lama tanpa `sisa`); null bila tak diketahui — jangan tampilkan Rp0. */
export function tagihanPelunasan(order) {
  const sisa = Number(order && order.sisa)
  if (Number.isFinite(sisa) && sisa > 0) return sisa
  const total = Number(order && order.total)
  return Number.isFinite(total) && total > 0 ? total : null
}

/**
 * Sidik isi nota (tanpa client_ref) — kunci pengikat client_ref. Server memutar ulang jawaban lama per
 * (pengguna, endpoint, client_ref) TANPA melihat isi body, jadi ref hanya boleh dipakai ulang untuk isi yang sama.
 * Harga tak ikut: server menghargai pesanan dari katalog.
 */
export function sidikNota(nota) {
  const n = nota || {}
  return JSON.stringify({
    bayar: n.bayar || null,
    items: (n.items || []).map((i) => ({ idProduk: i.idProduk, kuantitas: Number(i.kuantitas) || 0 })),
    idPelanggan: n.idPelanggan ?? null,
    catatan: n.catatan ?? null,
    dp: n.dp ? { jumlah: Number(n.dp.jumlah) || 0, tipePembayaran: n.dp.tipePembayaran || null } : null
  })
}

/**
 * client_ref untuk kiriman nota berikutnya. Sidik sama dengan kiriman terakhir → ref lama (kirim ulang sesudah
 * timeout aman: server memutar ulang pesanan yang sama); sidik beda → ref baru dari `buatRef()`.
 * @returns {{ ref: string, sidik: string }} keadaan baru — simpan pemanggil untuk kiriman berikutnya.
 */
export function refUntuk(state, sidik, buatRef) {
  if (state && state.ref && state.sidik === sidik) return { ref: state.ref, sidik }
  return { ref: buatRef(), sidik }
}
