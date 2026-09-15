// Galat validasi per kolom dari amplop gagal server ({ errors: { kolom: [pesan…] } }).
// Murni (tanpa DOM) agar teruji; dipakai formulir untuk menampilkan galat di bawah kolomnya.

/** Pesan pertama untuk `kolom`, '' bila tidak ada. */
export function galatKolom(result, kolom) {
  if (!result || result.ok || !result.errors || typeof result.errors !== 'object') return ''
  const v = result.errors[kolom]
  if (Array.isArray(v) && v.length) return String(v[0])
  return typeof v === 'string' ? v : ''
}
