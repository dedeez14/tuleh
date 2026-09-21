// Persetujuan berbasis PIN (Tahap B §2c): kasir tanpa hak batal/refund tetap bisa melanjutkan
// dengan PIN atasannya, dan server mencatat siapa yang menyetujui. Logika murni di sini; dialognya
// di components/dialog-otorisasi.js.

const LABEL = { 'transaksi.batal': 'Batalkan Transaksi', 'transaksi.refund': 'Refund' }

/** Aksi ini butuh persetujuan orang lain? (aksi di luar daftar tak bisa didelegasikan sama sekali) */
export function perluPersetujuan(aksi, { punyaHak = false } = {}) {
  return !punyaHak && Object.prototype.hasOwnProperty.call(LABEL, aksi)
}

/** Label tombol — kasir harus tahu SEBELUM menekan bahwa atasannya akan diminta. */
export function labelAksi(aksi, punyaHak) {
  const dasar = LABEL[aksi] || aksi
  return punyaHak ? dasar : `${dasar} (perlu persetujuan)`
}

/** Pesan galat isian dialog; string kosong = sah. */
export function validasiIsianOtorisasi({ pemberiId, pin } = {}) {
  if (!pemberiId) return 'Pilih pemberi persetujuan lebih dulu.'
  if (!/^\d{4,8}$/.test(String(pin || ''))) return 'PIN harus 4–8 digit angka.'
  return ''
}

/**
 * Sisa kunci PIN dalam detik dari amplop 429 (server: KeamananController::terkunciPin mengirim
 * `data.terkunci_detik`). 0 = bukan kunci PIN / server tak mengirim angkanya.
 */
export function detikTerkunci(amplop) {
  if (!amplop || amplop.status !== 429) return 0
  const n = Number(amplop.data && amplop.data.terkunci_detik)
  return Number.isFinite(n) && n > 0 ? Math.ceil(n) : 0
}

/**
 * Kalimat hitung mundur untuk 429 kunci PIN; '' bila amplopnya bukan 429 (pemanggil pakai
 * firstError()). Tanpa angka dari server, kalimat server dipakai apa adanya — jangan mengarang
 * durasi: kunci itu milik baris PIN di server, bukan timer lokal.
 */
export function pesanTerkunci(amplop) {
  if (!amplop || amplop.status !== 429) return ''
  const detik = detikTerkunci(amplop)
  return detik
    ? `Terlalu banyak PIN salah. Coba lagi dalam ${detik} detik.`
    : (amplop.message || 'Terlalu banyak PIN salah. Coba lagi sebentar.')
}
