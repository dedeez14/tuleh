// Resolver hak akses TUNGGAL untuk seluruh layar (desktop & Android memakai renderer yang sama).
//
// Hak akses adalah MASTER DATA server: katalog fitur (pos_hak_akses) × permission role yang diatur
// pemilik usaha. Login & /auth/me mengirim `akses` (daftar kunci) dan `peran` ({nama}). App tidak
// menanam peran atau matriks apa pun — layar, tombol, dan pemanggilan data bertanya ke `bisa(kunci)`.
// Tanpa `akses` dari server (belum dimuat / respons rusak) = tidak ada hak (gagal-tertutup); server
// tetap menolak endpoint yang tak berhak.
//
// Menu Beranda datang dari manifest server (sudah tersaring per hak); resolver ini untuk fitur di
// DALAM layar dan data yang dimuat di latar.

import { getState } from './state.js'

/**
 * Apakah pengguna aktif memegang hak `kunci`?
 * @param {string} kunci mis. 'transaksi.batal'
 * @param {{akses?: string[]|null}} [opsi] untuk pengujian / pemanggil tanpa state
 */
export function bisa(kunci, opsi) {
  const { akses } = opsi || getState()
  return Array.isArray(akses) && akses.includes(kunci)
}

/** Pemegang laporan — fitur manajemen yang memakai endpoint laporan (keuangan, stok). */
export function isManajemen(opsi) {
  return bisa('laporan.lihat', opsi)
}

/** Nama peran untuk ditampilkan, dari server. */
export function namaPeran(opsi) {
  const { peran } = opsi || getState()
  return (peran && typeof peran.nama === 'string' && peran.nama.trim()) || '—'
}
