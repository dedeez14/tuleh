// Resolver hak akses TUNGGAL untuk seluruh layar (desktop & Android memakai renderer yang sama).
//
// Layar, tombol, dan pemanggilan data yang bergantung peran WAJIB bertanya ke `bisa(kunci)` — jangan
// menulis `posRole === 'OWNER'` di tempat lain. Urutan sumber:
//   1. `akses` dari server (array kunci, dikirim login/me setelah fitur peran kustom aktif) — satu-satunya
//      sumber bila ada;
//   2. matriks bawaan per `pos_role` di bawah (mencerminkan penegakan server hari ini);
//   3. peran tak dikenal / belum dimuat → KASIR (gagal-tertutup: salah peta memberi akses terlalu sedikit).
//
// Menu Beranda tetap datang dari manifest server (sudah terfilter peran); resolver ini untuk fitur di
// DALAM layar dan data yang dimuat di latar.

import { getState } from './state.js'

const SEMUA = '*'

// Kunci yang tidak dimiliki Manager (wewenang pemilik: lintas toko, uang, keamanan, langganan, akun).
const KHUSUS_OWNER = new Set([
  'toko.buat', 'pengaturan.usaha', 'pengaturan.pembayaran', 'pengaturan.keamanan',
  'langganan.kelola', 'peran.kelola', 'pengguna.kelola'
])

// Kasir: operasional harian saja. Batal/void, riwayat & sesi kasir lain adalah wewenang manajemen
// (pola Loyverse/Toast/Moka) — kasir meminta Manager membatalkannya.
const KASIR = new Set(['kasir.transaksi', 'pesanan.kelola', 'produk.lihat'])

export const MATRIKS_AKSES = {
  OWNER: SEMUA,
  MANAGER: { kecuali: KHUSUS_OWNER },
  KASIR
}

/** Label tampilan peran. */
export function labelPeran(posRole) {
  return { OWNER: 'Owner', MANAGER: 'Manager', KASIR: 'Kasir' }[String(posRole || '').toUpperCase()] || 'Kasir'
}

/**
 * Apakah pengguna aktif boleh memakai fitur `kunci`?
 * @param {string} kunci mis. 'transaksi.riwayat_semua'
 * @param {{posRole?: string|null, akses?: string[]|null}} [opsi] untuk pengujian / pemanggil tanpa state
 */
export function bisa(kunci, opsi) {
  const st = opsi || getState()
  if (Array.isArray(st.akses)) return st.akses.includes(kunci)
  const aturan = MATRIKS_AKSES[String(st.posRole || '').toUpperCase()] || MATRIKS_AKSES.KASIR
  if (aturan === SEMUA) return true
  if (aturan instanceof Set) return aturan.has(kunci)
  return !aturan.kecuali.has(kunci)
}

/** Owner/Manager — pemegang fitur manajemen (laporan, pantau semua kasir). */
export function isManajemen(opsi) {
  return bisa('laporan.lihat', opsi)
}
