// Mencocokkan toko yang SAMA antar respons server — satu-satunya tempat aturannya ditulis.
//
// `id` toko adalah ciphertext non-deterministik (encrypt_id → Crypt::encryptString, IV acak):
// toko yang sama punya id berbeda di `/tokos`, di `/auth/me`, dan di `meta.sesi_toko` sebuah 409.
// Membandingkan id karena itu SELALU meleset. Urutan pencocokan:
//   1. `kode` (TK-xxx) — stabil, tapi belum dikirim semua endpoint,
//   2. `nama` — dirapikan & tak peduli huruf besar-kecil,
//   3. `id` — hanya menolong bila jembatannya memang memakai id stabil (Mode Demo, server lama);
//      id yang sama tidak pernah menunjuk toko yang berbeda, jadi aman sebagai cadangan terakhir.

/** Nama/kode yang bisa dibandingkan: rapi, tak peduli huruf besar-kecil. */
export function rapi(nilai) {
  return typeof nilai === 'string' ? nilai.trim().toLowerCase() : ''
}

/**
 * Cari entri `daftar` yang menunjuk toko yang sama dengan `acuan`.
 * @returns {object|null} entri dari daftar, atau null bila tak ada yang cocok.
 */
export function cocokkanToko(daftar, acuan) {
  if (!acuan) return null
  const list = Array.isArray(daftar) ? daftar : []
  const kode = rapi(acuan.kode)
  const nama = rapi(acuan.nama)
  const id = acuan.id == null ? '' : String(acuan.id)
  return (kode && list.find((t) => rapi(t.kode) === kode))
    || (nama && list.find((t) => rapi(t.nama) === nama))
    || (id && list.find((t) => t.id != null && String(t.id) === id))
    || null
}

/**
 * Toko sesi dari meta 409 dilengkapi data dari daftar toko pengguna (bidang usaha dll.).
 * `id`-nya tetap id dari 409 — itu yang sah di server saat ini.
 * Tak ketemu → kembalikan toko sesi apa adanya; server yang berhak menolak, bukan app.
 */
export function pilihTokoSesi(tokoList, sesiToko) {
  if (!sesiToko || !sesiToko.id) return null
  const cocok = cocokkanToko(tokoList, sesiToko)
  return cocok ? { ...cocok, id: sesiToko.id } : sesiToko
}
