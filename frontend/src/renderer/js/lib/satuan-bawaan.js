// Mencocokkan `satuan_bawaan` dari GET /pengaturan/usaha dengan daftar GET /satuan.
// Id satuan terenkripsi NON-deterministik (berbeda tiap jawaban server), jadi pencocokan
// memakai `kode` lalu `nama` — id hanya dipakai bila kebetulan sama (mis. Mode Demo).

/** @returns {{id, kode, nama}|null} entri daftar yang sesuai, atau null (belum diatur / tak ada). */
export function cocokkanSatuanBawaan(daftar, bawaan) {
  if (!bawaan || typeof bawaan !== 'object' || !Array.isArray(daftar)) return null
  return daftar.find((x) => x && bawaan.id && x.id === bawaan.id)
    || daftar.find((x) => x && bawaan.kode && x.kode === bawaan.kode)
    || daftar.find((x) => x && bawaan.nama && x.nama === bawaan.nama)
    || null
}
