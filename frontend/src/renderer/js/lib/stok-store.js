// Ambang stok minimum per produk (localStorage per toko) + analisis peringatan.
// Interim klien: default ambang DEFAULT_MIN; user bisa atur per produk.

export const DEFAULT_MIN = 5

const keyMin = (tokoId) => `tuleh.stokmin.${tokoId || 'default'}`
function read(k, f) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : f } catch { return f } }
function write(k, v) { try { localStorage.setItem(k, JSON.stringify(v)) } catch { /* nonaktif */ } }

export function getMinMap(tokoId) { return read(keyMin(tokoId), {}) }
export function getMin(tokoId, id) { const m = getMinMap(tokoId); return m[id] != null ? m[id] : DEFAULT_MIN }
export function setMin(tokoId, id, min) {
  const m = getMinMap(tokoId)
  m[id] = Math.max(0, Math.round(Number(min) || 0))
  write(keyMin(tokoId), m)
  return m
}

/**
 * analisisStok(rows, tokoId) → { habis, menipis, aman, alerts }
 * rows: [{id, kode, produk, stok}] dari laporan:stok. alerts = habis + menipis,
 * tiap item + { status, min, saran (qty restok utk capai 2× min) }.
 */
export function analisisStok(rows, tokoId) {
  const minMap = getMinMap(tokoId)
  const habis = []; const menipis = []; const aman = []
  for (const r of rows || []) {
    const stok = Number(r.stok) || 0
    const min = minMap[r.id] != null ? minMap[r.id] : DEFAULT_MIN
    const item = { id: r.id, kode: r.kode, produk: r.produk, stok, min }
    if (stok <= 0) { item.status = 'habis'; item.saran = Math.max(min * 2, 1); habis.push(item) }
    else if (stok <= min) { item.status = 'menipis'; item.saran = Math.max(min * 2 - stok, 1); menipis.push(item) }
    else { item.status = 'aman'; aman.push(item) }
  }
  // Peringatan diurut paling kritis dulu (stok terkecil)
  const alerts = [...habis, ...menipis].sort((a, b) => a.stok - b.stok)
  return { habis, menipis, aman, alerts }
}
