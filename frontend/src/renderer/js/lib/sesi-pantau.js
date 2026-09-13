// Logika murni layar Sesi Kasir — satu toko banyak kasir, tiap kasir bersesi sendiri.
// Owner/Manager menerima sesi SEMUA kasir toko (dengan `milik_saya`); Kasir hanya miliknya.

const isBuka = (row) => String(row?.status || '').toUpperCase() === 'BUKA'

/**
 * Sesi BUKA milik pengguna ini di daftar sesi (untuk id sesi aktif saat /sesi/aktif tak membawa id).
 * Tidak pernah memilih sesi kasir lain: dulu "satu-satunya sesi buka" bisa milik kasir lain di
 * daftar Manager → Manager tak sengaja menutup sesi kasir.
 */
export function sesiAktifSaya(rows, sesiAktif) {
  if (!Array.isArray(rows)) return null
  const kandidat = rows.filter((row) => isBuka(row) && row.milik_saya !== false)
  if (sesiAktif && sesiAktif.nomor) {
    const cocok = kandidat.find((row) => row.nomor === sesiAktif.nomor)
    if (cocok) return cocok
  }
  const milikSaya = kandidat.filter((row) => row.milik_saya === true)
  return milikSaya.length === 1 ? milikSaya[0] : null
}

/** Ringkasan sesi berjalan di toko: kasir bertugas, transaksi, dan penjualan. */
export function ringkasSesi(rows) {
  const buka = Array.isArray(rows) ? rows.filter(isBuka) : []
  return {
    berjalan: buka.length,
    transaksiBerjalan: buka.reduce((n, row) => n + (Number(row.jumlah_transaksi) || 0), 0),
    penjualanBerjalan: buka.reduce((n, row) => n + (Number(row.total_penjualan) || 0), 0)
  }
}

/** Saring status ('' = semua). */
export function saringStatusSesi(rows, status) {
  if (!Array.isArray(rows)) return []
  if (!status) return rows
  return rows.filter((row) => String(row.status || '').toUpperCase() === status)
}

/**
 * Tombol "Tutup Sesi" di detail daftar: hanya untuk sesi BUKA milik kasir LAIN dan bila pengguna
 * berwenang (`sesi.tutup_lain`). Sesi sendiri ditutup dari kartu sesi aktif (alur hitung laci).
 */
export function bolehTutupDariDaftar(row, berwenang) {
  return !!berwenang && isBuka(row) && row.milik_saya === false
}
