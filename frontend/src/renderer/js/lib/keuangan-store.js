// Penyimpanan keuangan lokal (Pengeluaran + HPP/modal) per toko via localStorage.
// Interim klien sampai server MOVERA menyediakan /pengeluaran & field harga_beli.
// Bekerja sama di desktop & Android, mode demo & produksi. Kunci per toko_id
// (toko demo = TOKO-1/2/3; produksi = id terenkripsi) → tidak saling bercampur.

export const KATEGORI_PENGELUARAN = [
  { kode: 'BAHAN_BAKU', label: 'Bahan Baku / Belanja' },
  { kode: 'GAJI', label: 'Gaji / Upah' },
  { kode: 'SEWA', label: 'Sewa Tempat' },
  { kode: 'LISTRIK_AIR', label: 'Listrik & Air' },
  { kode: 'TRANSPORT', label: 'Transport / Bensin' },
  { kode: 'PERALATAN', label: 'Peralatan' },
  { kode: 'LAIN', label: 'Lain-lain' }
]
const LABEL_KATEGORI = Object.fromEntries(KATEGORI_PENGELUARAN.map((k) => [k.kode, k.label]))
export const labelKategori = (kode) => LABEL_KATEGORI[kode] || 'Lain-lain'

const keyExp = (tokoId) => `tuleh.pengeluaran.${tokoId || 'default'}`
const keyHpp = (tokoId) => `tuleh.hpp.${tokoId || 'default'}`

function read(key, fallback) {
  try { const v = localStorage.getItem(key); return v ? JSON.parse(v) : fallback } catch { return fallback }
}
function write(key, val) {
  try { localStorage.setItem(key, JSON.stringify(val)) } catch { /* penyimpanan penuh/nonaktif */ }
}

// ---------- Pengeluaran ----------

export function listPengeluaran(tokoId, { dari, sampai } = {}) {
  let rows = read(keyExp(tokoId), [])
  if (dari) rows = rows.filter((r) => r.tanggal >= dari)
  if (sampai) rows = rows.filter((r) => r.tanggal <= sampai)
  return rows.sort((a, b) => b.tanggal.localeCompare(a.tanggal) || String(b.dibuat_at).localeCompare(String(a.dibuat_at)))
}

export function addPengeluaran(tokoId, { tanggal, kategori, nominal, catatan }) {
  const rows = read(keyExp(tokoId), [])
  const row = {
    id: `EXP-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
    tanggal, kategori,
    nominal: Math.round(Number(nominal) || 0),
    catatan: catatan || null,
    dibuat_at: new Date().toISOString()
  }
  rows.push(row); write(keyExp(tokoId), rows); return row
}

export function removePengeluaran(tokoId, id) {
  write(keyExp(tokoId), read(keyExp(tokoId), []).filter((r) => r.id !== id))
}

/** Ringkasan biaya periode: { total, perKategori:[{kode,label,total}], rows }. */
export function ringkasPengeluaran(tokoId, range) {
  const rows = listPengeluaran(tokoId, range)
  const per = {}
  let total = 0
  for (const r of rows) { const n = Number(r.nominal) || 0; total += n; per[r.kategori] = (per[r.kategori] || 0) + n }
  const perKategori = KATEGORI_PENGELUARAN
    .map((k) => ({ kode: k.kode, label: k.label, total: per[k.kode] || 0 }))
    .filter((x) => x.total > 0)
    .sort((a, b) => b.total - a.total)
  return { total: Math.round(total), perKategori, rows }
}

// ---------- HPP / harga modal (map produkId → modal) ----------

export function getHppMap(tokoId) { return read(keyHpp(tokoId), {}) }

export function setHpp(tokoId, produkId, modal) {
  const m = getHppMap(tokoId)
  const n = Math.round(Number(modal) || 0)
  if (n > 0) m[produkId] = n; else delete m[produkId]
  write(keyHpp(tokoId), m); return m
}

// ---------- Seeding contoh (khusus toko DEMO: TOKO-1/2/3) ----------

export function seedDemoKeuangan(tokoId, produk) {
  if (!/^TOKO-\d+$/.test(String(tokoId || ''))) return // hanya toko demo
  // HPP: modal ≈ 65% harga jual bila belum diisi
  if (Object.keys(getHppMap(tokoId)).length === 0 && Array.isArray(produk) && produk.length) {
    const m = {}
    for (const p of produk) { const h = Number(p.harga_jual) || 0; if (h > 0) m[p.id] = Math.round(h * 0.65) }
    write(keyHpp(tokoId), m)
  }
  // Pengeluaran contoh 7 hari bila belum ada
  if (read(keyExp(tokoId), []).length === 0) {
    const contoh = [
      { kategori: 'BAHAN_BAKU', nominal: 70000 }, { kategori: 'LISTRIK_AIR', nominal: 15000 },
      { kategori: 'GAJI', nominal: 50000 }, { kategori: 'SEWA', nominal: 25000 },
      { kategori: 'TRANSPORT', nominal: 12000 }, { kategori: 'PERALATAN', nominal: 20000 }
    ]
    const rows = []
    for (let h = 6; h >= 0; h--) {
      const d = new Date(); d.setDate(d.getDate() - h)
      const tgl = toIso(d)
      const c1 = contoh[h % contoh.length]
      rows.push({ id: `EXP-seed-${tgl}-a`, tanggal: tgl, kategori: c1.kategori, nominal: c1.nominal, catatan: '(contoh demo)', dibuat_at: d.toISOString() })
      if (h % 2 === 0) {
        const c2 = contoh[(h + 3) % contoh.length]
        rows.push({ id: `EXP-seed-${tgl}-b`, tanggal: tgl, kategori: c2.kategori, nominal: c2.nominal, catatan: '(contoh demo)', dibuat_at: d.toISOString() })
      }
    }
    write(keyExp(tokoId), rows)
  }
}

function toIso(d) {
  const y = d.getFullYear(); const m = String(d.getMonth() + 1).padStart(2, '0'); const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

// ---------- Perhitungan HPP total & Laba Rugi ----------

/**
 * hitungHPP(penjualanProduk, produk, hppMap) → { hpp, lengkap, tanpaModal:[nama] }
 * penjualanProduk: [{produk(nama), qty_terjual, total_nilai}] (grup per NAMA)
 * produk: [{id, nama, harga_jual}] — untuk memetakan nama→id→modal
 */
export function hitungHPP(penjualanProduk, produk, hppMap) {
  const modalByNama = {}
  for (const p of produk || []) { if (hppMap[p.id] != null) modalByNama[p.nama] = hppMap[p.id] }
  let hpp = 0; let lengkap = true; const tanpaModal = []
  for (const r of penjualanProduk || []) {
    const modal = modalByNama[r.produk]
    if (modal == null) { lengkap = false; if (Number(r.qty_terjual) > 0) tanpaModal.push(r.produk); continue }
    hpp += modal * (Number(r.qty_terjual) || 0)
  }
  return { hpp: Math.round(hpp), lengkap, tanpaModal }
}

/**
 * labaRugi({ omzet, hpp, biaya }) → view-model P&L.
 */
export function labaRugi({ omzet, hpp, biaya }) {
  const o = Math.round(Number(omzet) || 0)
  const h = Math.round(Number(hpp) || 0)
  const b = Math.round(Number(biaya) || 0)
  const labaKotor = o - h
  const labaBersih = labaKotor - b
  const pct = (part) => (o > 0 ? Math.round((part / o) * 1000) / 10 : 0)
  return {
    omzet: o, hpp: h, labaKotor, biaya: b, labaBersih,
    marginKotor: pct(labaKotor), marginBersih: pct(labaBersih)
  }
}
