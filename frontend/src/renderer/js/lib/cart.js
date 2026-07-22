// Kalkulasi keranjang & pembayaran — fungsi murni (unit-tested).
// Angka server tetap sumber kebenaran; ini untuk pratinjau real-time di UI.
//
// Model per baris: bruto = harga × qty
//                  diskon = bruto × diskon% / 100
//                  dpp    = bruto − diskon
//                  pajak  = dpp × pajak% / 100

function round2(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100
}

/** Rincian satu baris keranjang: { harga, kuantitas, diskonPersen, pajakPersen } */
export function lineTotals(item) {
  const harga = Number(item.harga) || 0
  const qty = Number(item.kuantitas) || 0
  const diskonPersen = Number(item.diskonPersen) || 0
  const pajakPersen = Number(item.pajakPersen) || 0

  const bruto = round2(harga * qty)
  const diskon = round2((bruto * diskonPersen) / 100)
  const dpp = round2(bruto - diskon)
  const pajak = round2((dpp * pajakPersen) / 100)
  const total = round2(dpp + pajak)

  return { bruto, diskon, dpp, pajak, total }
}

/** Total keranjang: { subtotal, totalDiskon, totalPajak, grandTotal, itemCount, qtyCount } */
export function cartTotals(items) {
  let subtotal = 0
  let totalDiskon = 0
  let totalPajak = 0
  let qtyCount = 0

  for (const item of items) {
    const line = lineTotals(item)
    subtotal += line.bruto
    totalDiskon += line.diskon
    totalPajak += line.pajak
    qtyCount += Number(item.kuantitas) || 0
  }

  return {
    subtotal: round2(subtotal),
    totalDiskon: round2(totalDiskon),
    totalPajak: round2(totalPajak),
    grandTotal: round2(subtotal - totalDiskon + totalPajak),
    itemCount: items.length,
    qtyCount: round2(qtyCount)
  }
}

/** Kembalian (≥ 0). Bila kurang bayar, gunakan shortfall(). */
export function kembalian(dibayar, grandTotal) {
  const diff = round2((Number(dibayar) || 0) - (Number(grandTotal) || 0))
  return diff > 0 ? diff : 0
}

/** Kekurangan pembayaran (≥ 0). */
export function shortfall(dibayar, grandTotal) {
  const diff = round2((Number(grandTotal) || 0) - (Number(dibayar) || 0))
  return diff > 0 ? diff : 0
}

/** Saran tombol uang cepat berdasarkan total (uang pas, pecahan wajar). */
export function quickCashOptions(grandTotal) {
  const total = Number(grandTotal) || 0
  if (total <= 0) return []
  const options = new Set([total])
  const denominations = [5000, 10000, 20000, 50000, 100000]
  for (const denom of denominations) {
    const rounded = Math.ceil(total / denom) * denom
    if (rounded > total) options.add(rounded)
  }
  return [...options].sort((a, b) => a - b).slice(0, 5)
}

/** Validasi qty terhadap stok (bila produk mengelola stok). */
export function clampQty(qty, { kelolaStok = false, stok = Infinity } = {}) {
  const n = Number(qty)
  if (!Number.isFinite(n) || n < 0) return 0
  if (kelolaStok && Number.isFinite(stok)) return Math.min(n, Math.max(stok, 0))
  return n
}
