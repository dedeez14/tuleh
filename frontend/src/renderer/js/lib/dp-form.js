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
