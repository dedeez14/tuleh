// Parkir keranjang — kasir menyimpan keranjang yang belum dibayar (pelanggan
// masih mengambil barang / antre bergantian) lalu melanjutkannya nanti.
// Logika murni & tak bergantung DOM; disimpan per toko di localStorage.

import { hargaJual } from '../utils/harga.js'

export const MAKS_PARKIR = 20

export function kunciParkir(tokoId) {
  return `tuleh_parkir_${tokoId || 'default'}`
}

/** Baca daftar parkir dari storage (array kosong bila rusak/kosong). */
export function bacaParkir(storage, tokoId) {
  try {
    const raw = storage.getItem(kunciParkir(tokoId))
    const arr = raw ? JSON.parse(raw) : []
    return Array.isArray(arr) ? arr.filter((p) => p && Array.isArray(p.items)) : []
  } catch {
    return []
  }
}

export function simpanParkir(storage, tokoId, daftar) {
  try {
    storage.setItem(kunciParkir(tokoId), JSON.stringify(daftar))
  } catch { /* storage penuh/ditolak: parkir hanya di memori sesi ini */ }
}

/**
 * Tambahkan satu keranjang ke daftar (tidak mengubah daftar asal).
 * items: [{ produk, kuantitas, diskonPersen }] — produk disalin seperlunya.
 * Mengembalikan { daftar, entri } atau { daftar, entri: null, alasan } bila penuh.
 */
export function tambahParkir(daftar, { items, pelanggan = null, catatan = '' }, now = Date.now()) {
  if (!Array.isArray(items) || !items.length) return { daftar, entri: null, alasan: 'Keranjang kosong.' }
  if (daftar.length >= MAKS_PARKIR) {
    return { daftar, entri: null, alasan: `Maksimal ${MAKS_PARKIR} keranjang terparkir. Selesaikan atau hapus yang lama.` }
  }
  const nomor = (daftar.reduce((m, p) => Math.max(m, Number(p.nomor) || 0), 0) % 999) + 1
  const entri = {
    id: `${now}-${Math.random().toString(36).slice(2, 8)}`,
    nomor,
    waktu: now,
    pelanggan: pelanggan ? { id: pelanggan.id, nama: pelanggan.nama, kode: pelanggan.kode, telepon: pelanggan.telepon } : null,
    catatan: String(catatan || ''),
    items: items.map((l) => ({
      produk: salinProduk(l.produk),
      kuantitas: Number(l.kuantitas) || 0,
      diskonPersen: Number(l.diskonPersen) || 0
    }))
  }
  return { daftar: [...daftar, entri], entri }
}

export function hapusParkir(daftar, id) {
  return daftar.filter((p) => p.id !== id)
}

/**
 * Susun ulang baris keranjang dari entri parkir. Bila produk masih ada di
 * katalog saat ini, dipakai data terbaru (harga/stok); bila tidak, salinan
 * saat diparkir dipakai agar penjualan tetap bisa diselesaikan.
 */
export function pulihkanBaris(entri, katalog = []) {
  const peta = new Map(katalog.map((p) => [String(p.id), p]))
  return entri.items.map((l) => ({
    produk: peta.get(String(l.produk.id)) || l.produk,
    kuantitas: l.kuantitas,
    diskonPersen: l.diskonPersen
  }))
}

/** Ringkasan entri untuk daftar: jumlah baris, total qty, total nilai. */
export function ringkasParkir(entri) {
  let qty = 0
  let total = 0
  for (const l of entri.items) {
    const harga = hargaJual(l.produk)
    const q = Number(l.kuantitas) || 0
    qty += q
    total += harga * q * (1 - (Number(l.diskonPersen) || 0) / 100)
  }
  return { baris: entri.items.length, qty, total }
}

function salinProduk(p) {
  // Simpan bidang yang dibutuhkan kasir & struk; hindari objek besar (gambar base64 dsb).
  const out = {}
  for (const k of ['id', 'nama', 'kode', 'sku', 'barcode', 'satuan', 'harga_jual', 'harga_efektif', 'promo_aktif', 'stok', 'kelola_stok', 'pajak_persen', 'kategori_id', 'kategori']) {
    if (p[k] !== undefined) out[k] = p[k]
  }
  return out
}
