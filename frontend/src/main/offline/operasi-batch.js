'use strict'

// Operasi /sync/v2/batch (Fase 4) dari baris antrean desktop — padanan Flutter `operasi_batch.dart`.
// Kontrak: rancangan Fase 4 §B–§C (server KontrakSync). Murni (tanpa HTTP/berkas) agar bisa diuji.

const crypto = require('node:crypto')
const { waktuKlienZona, refIndukLokal } = require('./antrean')

// Rute BARU (bukan /sync/batch): server lama menjawab 404 → app kembali ke kiriman per baris, alih-alih
// server v1 memproses amplop v2 dengan aturan lama (diskon & toko dibuang).
const JALUR_SYNC_BATCH = '/sync/v2/batch'

const JENIS_BATCH = Object.freeze({
  CHECKOUT: 'checkout',
  REFUND: 'refund',
  BATAL: 'batal',
  BILL_BAYAR: 'bills.settle',
  ORDER_TRANSISI: 'orders.transition'
})

// Segmen kecil: satu batch selesai jauh di bawah anggaran waktu server dan tidak menahan worker PHP lama.
const BATAS_OP_SEGMEN = 25
const BATAS_BYTE_SEGMEN = 1500000

// Istilah untuk kasir (panel Sinkronisasi). Kode server §B.4 + kode lokal app.
const LABEL_KODE = Object.freeze({
  OK: 'Terkirim',
  VALIDASI: 'Data ditolak',
  HAK_AKSES: 'Di luar akses toko Anda',
  OTORISASI_WAJIB: 'Butuh persetujuan atasan — ulangi saat online',
  SESI_TIDAK_ADA: 'Buka sesi kasir di toko ini',
  SESI_BEDA_TOKO: 'Sesi kasir terbuka di toko lain',
  STOK_KURANG: 'Stok tidak cukup',
  PRASYARAT: 'Menunggu transaksi asal tercatat',
  TIDAK_DITEMUKAN: 'Tidak ditemukan di server',
  KONFLIK: 'Bentrok dengan data di server',
  PELUNASAN_HARUS_REFUND: 'Transaksi pelunasan — gunakan Refund',
  DITUNDA: 'Ditunda server',
  LANGGANAN: 'Langganan berakhir',
  GALAT_SERVER: 'Galat server',
  INDUK_TINJAU: 'Menunggu transaksi asal ditinjau',
  INDUK_TIDAK_DIKENAL: 'Transaksi asal tidak bisa dirujuk',
  BATCH_TERLALU_BESAR: 'Data terlalu besar',
  BATCH_BERJALAN: 'Server masih memproses kiriman sebelumnya'
})

const LABEL_PERINGATAN = Object.freeze({
  SELISIH_STOK: 'Selisih stok',
  SESI_TUTUP: 'Masuk sesi yang sudah ditutup',
  SUDAH_DIBATALKAN: 'Sudah dibatalkan sebelumnya',
  SUDAH_DI_TAHAP: 'Pesanan sudah di tahap itu',
  SESI_BERBEDA: 'Masuk sesi yang dibuka setelahnya',
  JAM_PERANGKAT: 'Jam perangkat tidak tepat'
})

function labelKode(kode) { return LABEL_KODE[kode] || String(kode || 'Ditolak server') }

function labelPeringatan(daftar) {
  return (Array.isArray(daftar) ? daftar : []).map((k) => LABEL_PERINGATAN[k] || String(k))
}

/**
 * Segmen id pada jalur "/<grup>/<id>/…" (sudah di-decode); null bila bukan grup itu ATAU gagal di-decode
 * (mis. "%ZZ") — id rusak tidak dikirim mentah (acuan paritas Flutter `idDariJalur`).
 */
function idDariJalur(jalur, grup) {
  const seg = String(jalur || '').split('/')
  if (seg[1] !== grup || !seg[2]) return null
  try { return decodeURIComponent(seg[2]) } catch { return null }
}

/**
 * Baris antrean → satu operasi v2. Badan tersimpan dipakai apa adanya (sudah divalidasi kontrak saat
 * diantrekan) + field batch: waktu ber-zona, toko kejadian, rujukan dokumen dari jalur.
 */
function opDariBaris(p, { deviceId, kini = Date.now(), nomorLokal = null } = {}) {
  const type = JENIS_BATCH[p.jenis]
  if (!type) throw new Error(`Jenis ${p.jenis} tidak dikirim lewat batch.`)
  const body = p.body && typeof p.body === 'object' ? p.body : {}
  const dibuat = Number(p.dibuat) || kini
  // waktu_klien di badan yang tak terurai → waktu baris dibuat (acuan paritas Flutter).
  const mentah = typeof body.waktu_klien === 'string' && body.waktu_klien ? new Date(body.waktu_klien) : null
  const payload = {
    ...body,
    // Server menolak item bila client_ref payload ≠ idempotency_key.
    client_ref: p.clientRef,
    waktu_klien: waktuKlienZona(mentah && !Number.isNaN(mentah.getTime()) ? mentah : new Date(dibuat))
  }
  // Toko tempat kejadian (disimpan per baris) untuk SEMUA tipe — bukan toko aktif saat kirim.
  if (p.tokoId) payload.toko_id = p.tokoId
  if (type === 'checkout') {
    // Penjualan yang diantrekan sudah terjadi fisik: server menerimanya walau stok kurang (selisih dicatat).
    payload.offline = true
    const nomor = body.nomor_lokal || nomorLokal
    if (nomor) payload.nomor_lokal = String(nomor).slice(0, 30)
  } else if (type === 'refund' || type === 'batal') {
    const ref = refIndukLokal(p.path)
    if (ref) payload.transaksi_ref = ref
    else payload.transaksi_id = idDariJalur(p.path, 'transaksi')
  } else if (type === 'bills.settle') {
    payload.bon_id = idDariJalur(p.path, 'bills')
  } else {
    payload.order_id = idDariJalur(p.path, 'orders')
  }
  const op = { idempotency_key: p.clientRef, device_id: deviceId || undefined, type, payload }
  if (Number.isInteger(p.deviceSeq) && p.deviceSeq >= 0) op.device_seq = p.deviceSeq
  // Umur baris menurut jam perangkat sendiri: kebal jam absolut yang salah (tablet tanpa RTC).
  op.umur_detik = Math.max(0, Math.floor((kini - dibuat) / 1000))
  return op
}

/**
 * Bilangan bulat untuk sidik (acuan paritas Flutter): angka hingga → dipotong ke arah nol (Math.trunc,
 * -0 → 0); teks bilangan bulat ("2", " +3 ") → nilainya; selain itu (null, NaN, ∞, "1.5", boolean) → 0.
 */
function bulatSidik(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? Math.trunc(v) || 0 : 0
  if (typeof v === 'string' && /^\s*[+-]?\d+\s*$/.test(v)) return parseInt(v, 10) || 0
  return 0
}

/**
 * Komposisi segmen urutan kirim: "<type>:<clientRef>:<kirimUlangKe>" per baris. Baris berjenis
 * non-batch DIKECUALIKAN (tidak pernah ikut segmen) — bukan ditulis "undefined:…".
 */
function sidikKomposisi(baris) {
  return baris
    .filter((p) => p && JENIS_BATCH[p.jenis])
    .map((p) => `${JENIS_BATCH[p.jenis]}:${p.clientRef}:${bulatSidik(p.kirimUlangKe)}`)
    .join('\n')
}

/**
 * `client_ref` batch deterministik: kiriman ulang identik setelah putus jaringan = ref sama = replay
 * server; komposisi / generasi kirim ulang berbeda = ref berbeda. Garam hanya untuk 409 BATCH_REF_BENTROK;
 * garam ≤ 0 (termasuk negatif / bukan angka) = tanpa akhiran, pecahan dipotong.
 */
function clientRefBatch(deviceId, baris, garam = 0) {
  const g = bulatSidik(garam)
  const isi = `${deviceId || ''}|${sidikKomposisi(baris)}${g > 0 ? `|${g}` : ''}`
  return crypto.createHash('sha256').update(isi).digest('hex')
}

function ukuranJson(nilai) { return Buffer.byteLength(JSON.stringify(nilai), 'utf8') }

/** Hasil item diterima → `hasil` baris TERKIRIM. */
function hasilDariItem(item) {
  const it = item || {}
  return {
    id: it.server_id ?? null,
    nomor: it.nomor ?? null,
    kode: it.kode || 'OK',
    tipe: it.type || null,
    peringatan: Array.isArray(it.peringatan) ? it.peringatan.slice() : [],
    idempoten: it.idempoten === true,
    _idempoten: it.idempoten === true,
    data: it.data && typeof it.data === 'object' ? it.data : null
  }
}

/** Id item transaksi server dari hasil induk: ringkasan batch (data.items[{baris,id}]) atau struk per baris (items[i].id). */
function idItemDariHasil(hasil, baris) {
  if (!hasil || typeof hasil !== 'object') return null
  const n = Number(baris)
  if (!Number.isInteger(n) || n < 0) return null
  const ringkas = hasil.data && Array.isArray(hasil.data.items) ? hasil.data.items.find((x) => Number(x && x.baris) === n) : null
  if (ringkas && ringkas.id) return String(ringkas.id)
  const struk = Array.isArray(hasil.items) ? hasil.items[n] : null
  return struk && struk.id ? String(struk.id) : null
}

/**
 * Baris REFUND/BATAL atas transaksi lokal yang induknya SUDAH terkirim → jalur & badan berujukan id server,
 * untuk kiriman per baris ke endpoint tunggal (yang tidak mengenal "lokal:"). null bila tak bisa dirujuk.
 */
function gantiRujukanLokal(p, induk) {
  const idServer = induk && induk.hasil && induk.hasil.id ? String(induk.hasil.id) : null
  if (!idServer) return null
  const seg = String(p.path || '').split('/')
  if (seg.length < 3) return null
  seg[2] = encodeURIComponent(idServer)
  const body = { ...(p.body || {}) }
  if (Array.isArray(body.items)) {
    const items = []
    for (const it of body.items) {
      if (it && it.baris !== undefined && it.baris !== null) {
        const id = idItemDariHasil(induk.hasil, it.baris)
        if (!id) return null
        items.push({ id, kuantitas: it.kuantitas })
      } else {
        items.push(it)
      }
    }
    body.items = items
  }
  return { path: seg.join('/'), body }
}

module.exports = {
  JALUR_SYNC_BATCH,
  JENIS_BATCH,
  BATAS_OP_SEGMEN,
  BATAS_BYTE_SEGMEN,
  LABEL_KODE,
  LABEL_PERINGATAN,
  labelKode,
  labelPeringatan,
  opDariBaris,
  sidikKomposisi,
  clientRefBatch,
  ukuranJson,
  hasilDariItem,
  idItemDariHasil,
  gantiRujukanLokal
}
