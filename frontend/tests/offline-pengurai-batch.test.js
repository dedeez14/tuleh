'use strict'

// Pengurai mode batch (Fase 4, rancangan §B.4/§B.6/§I.1 + kritik A-02/A-03/A-11/B-1/B-3): segmen
// berurutan dengan baris per baris di tengah, pemetaan semua kode dari fikstur kontrak bersama,
// jawaban batch non-200, jalur kembali ke per baris, pemilik, kirim ulang, start dingin.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const { Antrean, STATUS } = require('../src/main/offline/antrean')
const { Pengurai, mundur, syncBatchDariConfig, JEDA_LAMA_MS, JEDA_TUNDA_MS, JEDA_BERJALAN_MS } = require('../src/main/offline/pengurai')
const { Koneksi } = require('../src/main/offline')

const fikstur = () => JSON.parse(fs.readFileSync(path.join(__dirname, 'fikstur', 'sync-batch-v2.json'), 'utf8'))
const antreanMemori = () => new Antrean({ berkas: null, sekarang: () => 0, buatId: () => 'dev-uji' })
const JALUR = {
  CHECKOUT: () => '/transaksi/checkout',
  REFUND: (i) => `/transaksi/T${i}/refund`,
  BATAL: (i) => `/transaksi/T${i}/batal`,
  BILL_BAYAR: (i) => `/bills/B${i}/settle`,
  ORDER_TRANSISI: (i) => `/orders/O${i}/transition`,
  PENGELUARAN: () => '/pengeluaran',
  STOK_MASUK: () => '/inventory/stok-masuk'
}

function baris(a, ref, jenis = 'CHECKOUT', ekstra = {}) {
  return a.antrekan({ clientRef: ref, jenis, tokoId: 'T1', path: JALUR[jenis](ref), body: { client_ref: ref }, ...ekstra })
}

function terimaSemua(badan) {
  return {
    ok: true, status: 200, message: 'Sinkronisasi selesai.', meta: { sidik: 'x' },
    data: {
      versi: 2, accepted: badan.operations.length, rejected: 0, ditunda: 0,
      results: badan.operations.map((op) => ({
        idempotency_key: op.idempotency_key, device_id: op.device_id, device_seq: op.device_seq ?? null, type: op.type,
        accepted: true, server_id: `srv-${op.idempotency_key}`, nomor: `N-${op.idempotency_key}`, kode: 'OK', retriable: false,
        message: 'Sinkronisasi diterima.', reason: null, idempoten: false, peringatan: [], data: null
      }))
    }
  }
}

function pengurai(a, o = {}) {
  const log = []
  const pg = new Pengurai({
    antrean: a,
    kirim: o.kirim || (async (jalur, body, p) => { log.push(`baris:${p.clientRef}`); return { ok: true, status: 201, data: { nomor: `B-${p.clientRef}` } } }),
    kirimBatch: async (badan) => { log.push(`batch:${badan.operations.map((op) => op.idempotency_key).join(',')}`); return (o.kirimBatch || terimaSemua)(badan) },
    koneksi: o.koneksi || null,
    kebijakan: o.kebijakan || (() => null),
    pemilikAktif: o.pemilikAktif,
    laporGalat: o.laporGalat || null,
    sekarang: o.sekarang || (() => 1000),
    jadwal: () => null,
    batalJadwal: () => {}
  })
  if (o.versi !== 0) pg.aturSyncBatch({ versi: o.versi || 2, maksOperasi: o.maksOperasi || null, maksByte: o.maksByte || null })
  return { pg, log }
}

test('syncBatchDariConfig: versi & batas dari /config; tanpa blok = versi 0 (server lama / Mode Demo)', () => {
  assert.deepEqual(syncBatchDariConfig({ sync_batch: { versi: 2, maks_operasi: 200, maks_byte: 2097152, tipe: ['checkout'] } }), { versi: 2, maksOperasi: 200, maksByte: 2097152 })
  assert.equal(syncBatchDariConfig({ sync_batch: { versi: 2, maks_operasi: 200, saran_operasi_per_segmen: 10 } }).maksOperasi, 10, 'saran segmen server yang lebih kecil dipakai (paritas Flutter)')
  assert.deepEqual(syncBatchDariConfig({ antrean_maks_umur_jam: 48 }), { versi: 0, maksOperasi: null, maksByte: null })
  assert.deepEqual(syncBatchDariConfig(null), { versi: 0, maksOperasi: null, maksByte: null })
})

test('versi < 2 atau tanpa kirimBatch → jalur per baris lama tanpa perubahan', async () => {
  const a = antreanMemori()
  baris(a, 'c1'); baris(a, 'c2')
  const { pg, log } = pengurai(a, { versi: 1 })
  assert.equal(pg.modeBatch(), false)
  assert.equal(await pg.jalankan(), 2)
  assert.deepEqual(log, ['baris:c1', 'baris:c2'])
})

test('segmen berurutan: baris non-batch memotong segmen dan dikirim per baris di posisinya', async () => {
  const a = antreanMemori()
  baris(a, 'c1'); baris(a, 'r1', 'REFUND'); baris(a, 'x1', 'PENGELUARAN'); baris(a, 'c2')
  const badanTerkirim = []
  const { pg, log } = pengurai(a, { kirimBatch: (b) => { badanTerkirim.push(b); return terimaSemua(b) } })
  assert.equal(await pg.jalankan(), 4)
  assert.deepEqual(log, ['batch:c1,r1', 'baris:x1', 'batch:c2'])
  const b = badanTerkirim[0]
  assert.match(b.client_ref, /^[0-9a-f]{64}$/)
  assert.equal(b.device_id, 'dev-uji')
  assert.deepEqual(b.operations.map((op) => [op.idempotency_key, op.type, op.device_seq]), [['c1', 'checkout', 1], ['r1', 'refund', 2]])
  assert.equal(b.operations[0].payload.offline, true)
  assert.equal(b.operations[0].payload.toko_id, 'T1')
  assert.equal(b.operations[1].payload.transaksi_id, 'Tr1')
  assert.equal(a.cari('c1').status, STATUS.TERKIRIM)
  assert.equal(a.cari('c1').hasil.id, 'srv-c1')
  assert.equal(a.cari('x1').hasil.nomor, 'B-x1')
  assert.equal(pg.status().modeBatch, true)
})

const JENIS_DARI = { checkout: 'CHECKOUT', refund: 'REFUND', batal: 'BATAL', 'bills.settle': 'BILL_BAYAR', 'orders.transition': 'ORDER_TRANSISI' }

/** Sikap app per kode (kontrak §13.4) — dipakai tes fikstur & tes semua kode. */
function cekPemetaan(p, it, jam) {
  const pesan = `${it.idempotency_key} (${it.kode})`
  if (it.accepted) {
    assert.equal(p.status, STATUS.TERKIRIM, pesan)
    assert.equal(p.hasil.id, it.server_id, pesan)
    assert.equal(p.hasil.nomor, it.nomor, pesan)
    assert.deepEqual(p.hasil.peringatan, it.peringatan, pesan)
    assert.equal(p.hasil.idempoten, it.idempoten, pesan)
  } else if (it.kode === 'DITUNDA') {
    assert.equal(p.status, STATUS.MENUNGGU, pesan)
    assert.equal(p.sebabTunda, 'BATCH', pesan)
    assert.equal(p.cobaLagiSetelah, jam + JEDA_TUNDA_MS, pesan)
    assert.equal(p.percobaan, 0, `${pesan}: tidak menaikkan percobaan`)
  } else if (it.kode === 'GALAT_SERVER') {
    assert.equal(p.status, STATUS.MENUNGGU, pesan)
    assert.equal(p.sebabTunda, 'SERVER', pesan)
    assert.equal(p.galatServer, 1, pesan)
    assert.equal(p.cobaLagiSetelah, jam + mundur(1), pesan)
  } else if (it.kode === 'LANGGANAN') {
    assert.equal(p.status, STATUS.MENUNGGU, pesan)
    assert.equal(p.sebabTunda, 'LANGGANAN', pesan)
    assert.equal(p.kode, 'LANGGANAN', pesan)
  } else if (it.retriable) {
    assert.equal(p.status, STATUS.MENUNGGU, pesan)
    assert.equal(p.sebabTunda, 'BATCH', pesan)
    assert.equal(p.kode, it.kode, pesan)
    assert.equal(p.cobaLagiSetelah, jam + JEDA_LAMA_MS[0], pesan)
    assert.equal(p.percobaan, 1, pesan)
  } else {
    assert.equal(p.status, STATUS.TINJAU, pesan)
    assert.equal(p.kode, it.kode, pesan)
    assert.ok(p.galat.includes(it.message), pesan)
  }
}

test('pemetaan hasil fikstur kontrak bersama (POS_DOCS/fikstur/sync-batch-v2.json, bagian respons)', async () => {
  const f = fikstur()
  assert.equal(f.versi, 2)
  const r = f.respons
  assert.equal(r.data.versi, 2)
  const dipakai = r.data.results.filter((it) => JENIS_DARI[it.type]) // tipe `keep` tidak diantrekan desktop
  assert.ok(dipakai.length > 0)
  const a = antreanMemori()
  dipakai.forEach((it) => baris(a, it.idempotency_key, JENIS_DARI[it.type]))
  const jam = 1000000
  const { pg } = pengurai(a, { kirimBatch: () => ({ ok: true, status: 200, data: r.data, meta: r.meta, message: r.message }), sekarang: () => jam })
  await pg.jalankan()
  for (const it of dipakai) cekPemetaan(a.cari(it.idempotency_key), it, jam)
})

test('semua kode kontrak (tabel kode fikstur) + hasil hilang dipetakan sesuai sikap app', async () => {
  const kode = fikstur().kode
  for (const k of ['OK', 'VALIDASI', 'OTORISASI_WAJIB', 'PRASYARAT', 'DITUNDA', 'LANGGANAN', 'GALAT_SERVER', 'PELUNASAN_HARUS_REFUND']) assert.ok(k in kode, k)
  const a = antreanMemori()
  Object.keys(kode).forEach((k) => baris(a, `k-${k}`))
  baris(a, 'k-hilang')
  const hasil = new Map()
  const jam = 1000000
  const { pg } = pengurai(a, {
    sekarang: () => jam,
    kirimBatch: (b) => {
      const results = []
      for (const op of b.operations) {
        const k = op.idempotency_key.slice(2)
        if (k === 'hilang') continue
        const diterima = k === 'OK'
        const it = {
          idempotency_key: op.idempotency_key, device_id: op.device_id, device_seq: op.device_seq ?? null, type: op.type,
          accepted: diterima, server_id: diterima ? `srv-${k}` : null, nomor: diterima ? `N-${k}` : null, kode: k,
          retriable: diterima ? false : kode[k], message: diterima ? 'Sinkronisasi diterima.' : `Ditolak (${k}).`,
          reason: diterima ? null : `Ditolak (${k}).`, idempoten: false, peringatan: [], data: null
        }
        hasil.set(op.idempotency_key, it)
        results.push(it)
      }
      return { ok: true, status: 200, message: 'Sinkronisasi selesai.', meta: { sidik: 'x' }, data: { versi: 2, accepted: 1, rejected: results.length - 1, ditunda: 1, results } }
    }
  })
  await pg.jalankan()
  assert.equal(hasil.size, Object.keys(kode).length)
  for (const [ref, it] of hasil) cekPemetaan(a.cari(ref), it, jam)
  const hilang = a.cari('k-hilang')
  assert.equal(hilang.status, STATUS.MENUNGGU)
  assert.equal(hilang.sebabTunda, 'SERVER')
  assert.equal(hilang.kode, 'GALAT_SERVER')
  assert.equal(hilang.galatServer, 1)
})

test('jeda panjang naik bertingkat untuk kode retriable yang berulang; umur baris lewat batas → TINJAU', async () => {
  // dibuat = 1 (bukan 0): umur baris dihitung dari `dibuat`, dan 0 dianggap "tak diketahui".
  const a = new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-uji' })
  baris(a, 'k')
  let jam = 0
  const tolak = (b) => ({ ok: true, status: 200, data: { versi: 2, results: [{ idempotency_key: 'k', type: 'checkout', accepted: false, kode: 'PRASYARAT', retriable: true, message: 'Belum.' }] } })
  const { pg } = pengurai(a, { kirimBatch: tolak, sekarang: () => jam, kebijakan: () => ({ maksPercobaanGalatServer: null, maksUmurJam: 1 }) })
  await pg.jalankan()
  assert.equal(a.cari('k').cobaLagiSetelah, JEDA_LAMA_MS[0])
  jam = JEDA_LAMA_MS[0]
  await pg.jalankan()
  assert.equal(a.cari('k').cobaLagiSetelah, jam + JEDA_LAMA_MS[1])
  jam = 3600001
  await pg.jalankan()
  assert.equal(a.cari('k').status, STATUS.TINJAU)
  assert.match(a.cari('k').galat, /lebih dari 1 jam/)
})

test('HTTP batch 401/402/426/jaringan/timeout/5xx: semua baris segmen diperlakukan sama', async () => {
  const kasus = [
    { res: { ok: false, status: 401, message: 'Sesi berakhir' }, cek: (p, pg) => { assert.equal(p.status, STATUS.MENUNGGU); assert.equal(p.percobaan, 0) } },
    { res: { ok: false, status: 402, message: 'Langganan berakhir' }, cek: (p, pg) => { assert.equal(p.sebabTunda, 'LANGGANAN'); assert.equal(pg.status().jeda.sebab, 'LANGGANAN') } },
    { res: { ok: false, status: 426, message: 'Perbarui' }, cek: (p, pg) => { assert.equal(p.sebabTunda, 'UPDATE'); assert.equal(pg.status().jeda.sebab, 'UPDATE') } },
    { res: { ok: false, status: 0, gangguan: true, message: 'putus' }, cek: (p, pg, k) => { assert.equal(p.sebabTunda, 'JARINGAN'); assert.equal(p.percobaan, 1); assert.equal(k.online, false) } },
    // 429 tanpa kode (batas laju pos-sync) = jeda jaringan untuk seluruh segmen, pita offline (kontrak §13.5, P-3d).
    { res: { ok: false, status: 429, gangguan: true, message: 'Terlalu banyak permintaan.' }, cek: (p, pg, k) => { assert.equal(p.sebabTunda, 'JARINGAN'); assert.equal(p.percobaan, 1); assert.match(p.galat, /membatasi/); assert.equal(pg.status().jeda.sebab, 'JARINGAN'); assert.equal(k.online, false) } },
    { res: { ok: false, status: -1, gangguan: true, timeout: true }, cek: (p) => { assert.equal(p.sebabTunda, 'TIMEOUT'); assert.equal(p.cobaLagiSetelah, 1000 + mundur(1)) } },
    { res: { ok: false, status: 503, gangguan: true, message: 'Pemeliharaan' }, cek: (p) => { assert.equal(p.sebabTunda, 'SERVER'); assert.equal(p.galatServer, 1); assert.match(p.galat, /HTTP 503/) } }
  ]
  for (const { res, cek } of kasus) {
    const a = antreanMemori()
    baris(a, 'c1'); baris(a, 'c2')
    // Kode basi dari hasil item sebelumnya tidak boleh tertinggal di panel setelah jawaban non-item.
    a.perbarui('c1', { kode: 'PRASYARAT' })
    const koneksi = new Koneksi()
    const { pg, log } = pengurai(a, { kirimBatch: () => res, koneksi })
    assert.equal(await pg.jalankan(), 0, `HTTP ${res.status}`)
    assert.deepEqual(log, ['batch:c1,c2'], `HTTP ${res.status}: satu kiriman`)
    for (const r of ['c1', 'c2']) {
      cek(a.cari(r), pg, koneksi)
      assert.equal(a.cari(r).kode, null, `HTTP ${res.status}: kode dibersihkan (${r})`)
    }
    assert.equal(a.ringkas().tinjau, 0, `HTTP ${res.status}: tidak ada yang ditinjau`)
  }
})

test('422 amplop cacat → mundur per baris sebagai galat server + laporan diagnostik', async () => {
  const a = antreanMemori()
  baris(a, 'c1')
  const laporan = []
  const { pg } = pengurai(a, { kirimBatch: () => ({ ok: false, status: 422, message: 'Data tidak valid.', errors: { operations: ['Wajib.'] } }), laporGalat: (l) => laporan.push(l) })
  await pg.jalankan()
  assert.equal(a.cari('c1').sebabTunda, 'SERVER')
  assert.equal(laporan.length, 1)
  assert.match(laporan[0].pesan, /422/)
})

test('413 → segmen dibelah dua; satu baris yang tetap terlalu besar → TINJAU', async () => {
  const a = antreanMemori()
  for (const r of ['a', 'b', 'c', 'd']) baris(a, r)
  a.perbarui('a', { kode: 'PRASYARAT' })
  const ukuran = []
  const { pg } = pengurai(a, { kirimBatch: (b) => { ukuran.push(b.operations.length); return b.operations.length > 2 ? { ok: false, status: 413, message: 'Terlalu besar', errors: { kode: ['BATCH_TERLALU_BESAR'] } } : terimaSemua(b) } })
  await pg.jalankan()
  assert.deepEqual(a.semua().map((p) => p.status), ['MENUNGGU', 'MENUNGGU', 'MENUNGGU', 'MENUNGGU'])
  assert.equal(a.cari('a').kode, null, 'kode basi dibersihkan saat segmen dibelah')
  await pg.jalankan()
  assert.deepEqual(ukuran, [4, 2, 2])
  assert.equal(a.ringkas().total, 0)

  const b = antreanMemori()
  baris(b, 'raksasa')
  const { pg: pg2 } = pengurai(b, { kirimBatch: () => ({ ok: false, status: 413, gateway: 'body-too-large' }) })
  await pg2.jalankan()
  assert.equal(b.cari('raksasa').status, STATUS.TINJAU)
  assert.equal(b.cari('raksasa').kode, 'BATCH_TERLALU_BESAR')
})

test('409 BATCH_REF_BENTROK → kirim ulang SEKALI dengan ref bergaram', async () => {
  const a = antreanMemori()
  baris(a, 'c1')
  const ref = []
  const { pg } = pengurai(a, { kirimBatch: (b) => { ref.push(b.client_ref); return ref.length === 1 ? { ok: false, status: 409, errors: { kode: ['BATCH_REF_BENTROK'] }, message: 'Bentrok' } : terimaSemua(b) } })
  await pg.jalankan()
  assert.equal(ref.length, 2)
  assert.notEqual(ref[0], ref[1])
  assert.equal(a.cari('c1').status, STATUS.TERKIRIM)
})

test('429 BATCH_BERJALAN tanpa Retry-After → tunda 5 dtk (kontrak §13.5/K-7) tanpa menaikkan percobaan, putaran berhenti', async () => {
  const a = antreanMemori()
  baris(a, 'c1'); baris(a, 'x1', 'PENGELUARAN')
  const { pg, log } = pengurai(a, { kirimBatch: () => ({ ok: false, status: 429, errors: { kode: ['BATCH_BERJALAN'] }, message: 'Masih diproses' }) })
  await pg.jalankan()
  assert.deepEqual(log, ['batch:c1'], 'baris sesudahnya tidak dikirim di putaran ini')
  const p = a.cari('c1')
  assert.equal(p.status, STATUS.MENUNGGU)
  assert.equal(p.sebabTunda, 'BATCH')
  assert.equal(JEDA_BERJALAN_MS, 5000)
  assert.equal(p.cobaLagiSetelah, 1000 + JEDA_BERJALAN_MS)
  assert.equal(p.percobaan, 0)
  assert.equal(p.kode, 'BATCH_BERJALAN')
})

test('404 rute / 503 BATCH_TIDAK_TERSEDIA → kembali per baris di putaran yang sama sampai /config berikutnya', async () => {
  for (const res of [
    { ok: false, status: 404, gateway: 'route-unknown', message: 'Endpoint tidak dikenal.' },
    { ok: false, status: 503, gangguan: true, errors: { kode: ['BATCH_TIDAK_TERSEDIA'] }, message: 'Tidak tersedia' }
  ]) {
    const a = antreanMemori()
    baris(a, 'c1'); baris(a, 'c2')
    a.perbarui('c1', { kode: 'PRASYARAT' })
    const kodeSaatPerBaris = []
    const { pg, log } = pengurai(a, {
      kirimBatch: () => res,
      kirim: async (jalur, body, p) => { log.push(`baris:${p.clientRef}`); kodeSaatPerBaris.push(a.cari(p.clientRef).kode); return { ok: true, status: 201, data: {} } }
    })
    assert.equal(await pg.jalankan(), 2, `HTTP ${res.status}`)
    assert.deepEqual(kodeSaatPerBaris, [null, null], `HTTP ${res.status}: kode basi dibersihkan`)
    assert.deepEqual(log, ['batch:c1,c2', 'baris:c1', 'baris:c2'])
    assert.equal(pg.modeBatch(), false)
    assert.equal(pg.aturSyncBatch({ versi: 2 }), true, '/config berikutnya mencoba batch lagi')
  }
})

test('jawaban 200 tanpa data.versi = server lama: yang diterima dicatat, sisanya per baris', async () => {
  const a = antreanMemori()
  baris(a, 'c1'); baris(a, 'c2')
  const { pg, log } = pengurai(a, { kirimBatch: () => ({ ok: true, status: 200, data: { results: [{ idempotency_key: 'c1', accepted: true, server_id: 'v1-1', nomor: 'N1' }] } }) })
  await pg.jalankan()
  assert.deepEqual(log, ['batch:c1,c2', 'baris:c2'])
  assert.equal(a.cari('c1').hasil.nomor, 'N1')
  assert.equal(a.cari('c2').status, STATUS.TERKIRIM)
  assert.equal(pg.modeBatch(), false)
})

test('hasil hilang dari jawaban → galat server untuk baris itu saja', async () => {
  const a = antreanMemori()
  baris(a, 'c1'); baris(a, 'c2')
  const { pg } = pengurai(a, { kirimBatch: (b) => { const r = terimaSemua(b); r.data.results = r.data.results.slice(0, 1); return r } })
  await pg.jalankan()
  assert.equal(a.cari('c1').status, STATUS.TERKIRIM)
  assert.equal(a.cari('c2').sebabTunda, 'SERVER')
  assert.equal(a.cari('c2').kode, 'GALAT_SERVER')
})

test('pemilik: hanya baris akun aktif yang dikirim; akun lain tidak dijadwalkan', async () => {
  const a = antreanMemori()
  baris(a, 'milik', 'CHECKOUT', { pemilik: 'a@t' })
  baris(a, 'lain', 'CHECKOUT', { pemilik: 'b@t' })
  const { pg, log } = pengurai(a, { pemilikAktif: () => 'a@t' })
  await pg.jalankan()
  assert.deepEqual(log, ['batch:milik'])
  assert.equal(a.cari('lain').status, STATUS.MENUNGGU)
})

test('kirim ulang dari TINJAU: kirimUlangKe naik → client_ref batch berbeda → dinilai ulang server', async () => {
  const a = antreanMemori()
  baris(a, 'k')
  const ref = []
  let tolak = true
  const { pg } = pengurai(a, {
    kirimBatch: (b) => {
      ref.push(b.client_ref)
      return tolak
        ? { ok: true, status: 200, data: { versi: 2, results: [{ idempotency_key: 'k', type: 'checkout', accepted: false, kode: 'VALIDASI', retriable: false, message: 'Produk belum punya satuan.' }] } }
        : terimaSemua(b)
    }
  })
  await pg.jalankan()
  assert.equal(a.cari('k').status, STATUS.TINJAU)
  tolak = false
  await pg.kirimUlang('k')
  assert.equal(a.cari('k').kirimUlangKe, 1)
  assert.equal(a.cari('k').status, STATUS.TERKIRIM)
  assert.notEqual(ref[0], ref[1])
})

test('batas segmen: 25 op bawaan, maks_operasi /config bila lebih kecil', async () => {
  const a = antreanMemori()
  for (let i = 0; i < 30; i++) baris(a, `c${i}`)
  const ukuran = []
  const { pg } = pengurai(a, { kirimBatch: (b) => { ukuran.push(b.operations.length); return terimaSemua(b) } })
  await pg.jalankan()
  assert.deepEqual(ukuran, [25, 5])

  const b = antreanMemori()
  for (let i = 0; i < 12; i++) baris(b, `d${i}`)
  const ukuran2 = []
  const { pg: pg2 } = pengurai(b, { maksOperasi: 5, kirimBatch: (x) => { ukuran2.push(x.operations.length); return terimaSemua(x) } })
  await pg2.jalankan()
  assert.deepEqual(ukuran2, [5, 5, 2])
})

test('start dingin: versi batch tersimpan di antrean → pengurai baru langsung mode batch', () => {
  const a = antreanMemori()
  const { pg } = pengurai(a)
  assert.equal(a.perangkat().syncBatchVersi, 2)
  const baru = new Pengurai({ antrean: a, kirim: async () => ({ ok: true }), kirimBatch: async () => ({ ok: true }), jadwal: () => null, batalJadwal: () => {} })
  assert.equal(baru.modeBatch(), true)
  assert.equal(pg.aturSyncBatch({ versi: 0 }), false)
  assert.equal(a.perangkat().syncBatchVersi, 0)
})

// ── Tambahan pelaksana Task 17 (carry-over pengendali) ──

// Gateway lokal menjawab 504 `X-Tuleh-Gateway: upstream-timeout` (353b855): permintaan SUDAH terkirim tetapi
// server lambat menjawab — sama dengan timeout klien: mundur per baris, tanpa pita offline, tidak dihitung
// sebagai galat server menuju batas tinjau.
const GATEWAY_TIMEOUT = Object.freeze({ ok: false, status: 504, gangguan: true, gateway: 'upstream-timeout', message: 'Server terlalu lama menjawab. Coba lagi beberapa saat lagi.' })

test('504 upstream-timeout (per baris): TIMEOUT per baris, lanjut ke baris berikut, tetap online, tak dihitung galat server', async () => {
  const a = antreanMemori()
  baris(a, 'c1'); baris(a, 'c2')
  const koneksi = new Koneksi()
  const { pg, log } = pengurai(a, {
    versi: 0,
    koneksi,
    kebijakan: () => ({ maksPercobaanGalatServer: 1, maksUmurJam: null }),
    kirim: async (jalur, body, p) => { log.push(`baris:${p.clientRef}`); return { ...GATEWAY_TIMEOUT } }
  })
  assert.equal(pg.modeBatch(), false)
  assert.equal(await pg.jalankan(), 0)
  assert.deepEqual(log, ['baris:c1', 'baris:c2'], 'bukan jeda global — baris berikut tetap dicoba')
  for (const r of ['c1', 'c2']) {
    const p = a.cari(r)
    assert.equal(p.status, STATUS.MENUNGGU, r)
    assert.equal(p.sebabTunda, 'TIMEOUT', r)
    assert.equal(p.percobaan, 1, r)
    assert.equal(p.galatServer || 0, 0, `${r}: tidak dihitung galat server`)
    assert.equal(p.cobaLagiSetelah, 1000 + mundur(1), r)
  }
  assert.equal(koneksi.online, true, 'tanpa pita offline')
  assert.equal(pg.status().jeda, null)
})

test('504 upstream-timeout (batch): semua baris segmen TIMEOUT, tetap online, batas tinjau galat server tak tersentuh', async () => {
  const a = antreanMemori()
  baris(a, 'c1'); baris(a, 'c2')
  const koneksi = new Koneksi()
  const { pg, log } = pengurai(a, { koneksi, kirimBatch: () => ({ ...GATEWAY_TIMEOUT }), kebijakan: () => ({ maksPercobaanGalatServer: 1, maksUmurJam: null }) })
  assert.equal(await pg.jalankan(), 0)
  assert.deepEqual(log, ['batch:c1,c2'])
  for (const r of ['c1', 'c2']) {
    const p = a.cari(r)
    assert.equal(p.status, STATUS.MENUNGGU, r)
    assert.equal(p.sebabTunda, 'TIMEOUT', r)
    assert.equal(p.galatServer || 0, 0, r)
    assert.equal(p.cobaLagiSetelah, 1000 + mundur(1), r)
  }
  assert.equal(koneksi.online, true)
  assert.equal(pg.modeBatch(), true, 'tetap mode batch')
  assert.equal(a.ringkas().tinjau, 0)
})

test('jenis antrean bernama properti Object ("constructor"/"toString") tidak pernah masuk segmen batch', async () => {
  const a = antreanMemori()
  baris(a, 'c1')
  a.antrekan({ clientRef: 'aneh', jenis: 'constructor', tokoId: 'T1', path: '/aneh', body: {} })
  a.antrekan({ clientRef: 'aneh2', jenis: 'toString', tokoId: 'T1', path: '/aneh2', body: {} })
  const { pg, log } = pengurai(a)
  await pg.jalankan()
  assert.deepEqual(log, ['batch:c1', 'baris:aneh', 'baris:aneh2'])
})

test('pemilik aktif belum diketahui (null) → tidak ada baris yang dikirim', async () => {
  const a = antreanMemori()
  baris(a, 'c1', 'CHECKOUT', { pemilik: 'a@t' })
  const { pg, log } = pengurai(a, { pemilikAktif: () => null })
  assert.equal(await pg.jalankan(), 0)
  assert.deepEqual(log, [])
})

// ── Tambahan pelaksana Task 18 (carry-over pengendali Task 17) ──

test('429 BATCH_BERJALAN menghormati Retry-After (angka, header objek, Headers); nilai tak sah → 5 dtk', async () => {
  const kasus = [
    { tambahan: { retryAfter: 12 }, harap: 12000 },
    { tambahan: { headers: { 'Retry-After': '7' } }, harap: 7000 },
    { tambahan: { headers: new Headers({ 'Retry-After': '9' }) }, harap: 9000 },
    { tambahan: { retryAfter: 'nanti' }, harap: JEDA_BERJALAN_MS },
    { tambahan: { retryAfter: 0 }, harap: JEDA_BERJALAN_MS }
  ]
  for (const { tambahan, harap } of kasus) {
    const a = antreanMemori()
    baris(a, 'c1')
    const { pg } = pengurai(a, { kirimBatch: () => ({ ok: false, status: 429, errors: { kode: ['BATCH_BERJALAN'] }, message: 'Masih diproses', ...tambahan }) })
    await pg.jalankan()
    assert.equal(a.cari('c1').cobaLagiSetelah, 1000 + harap, JSON.stringify(tambahan))
    assert.equal(a.cari('c1').percobaan, 0)
  }
})

test('per baris: jawaban non-item (jaringan/429/timeout/402/426/401/5xx/4xx) membersihkan kode basi', async () => {
  const kasus = [
    { res: { ok: false, status: 0, gangguan: true }, sebab: 'JARINGAN' },
    { res: { ok: false, status: 429, gangguan: true }, sebab: 'JARINGAN' },
    { res: { ok: false, status: -1, gangguan: true, timeout: true }, sebab: 'TIMEOUT' },
    { res: { ok: false, status: 402, message: 'Langganan berakhir' }, sebab: 'LANGGANAN' },
    { res: { ok: false, status: 426, message: 'Perbarui' }, sebab: 'UPDATE' },
    { res: { ok: false, status: 401, message: 'Sesi berakhir' }, sebab: undefined },
    { res: { ok: false, status: 503, gangguan: true, message: 'Pemeliharaan' }, sebab: 'SERVER' },
    { res: { ok: false, status: 422, message: 'Data tidak valid.' }, sebab: null }
  ]
  for (const { res, sebab } of kasus) {
    const a = antreanMemori()
    baris(a, 'c1')
    a.perbarui('c1', { kode: 'PRASYARAT' })
    const { pg } = pengurai(a, { versi: 0, kirim: async () => ({ ...res }) })
    await pg.jalankan()
    const p = a.cari('c1')
    assert.equal(p.kode, null, `HTTP ${res.status}`)
    assert.equal(p.sebabTunda, sebab, `HTTP ${res.status}`)
  }
})

test('TIMEOUT kena batas umur /config: baris terlalu tua → TINJAU "mungkin sudah sampai" (per baris & batch), turunan ikut', async () => {
  const kebijakan = () => ({ maksPercobaanGalatServer: null, maksUmurJam: 1 })
  const TIMEOUT = { ok: false, status: -1, gangguan: true, timeout: true }
  for (const mode of ['perBaris', 'batch']) {
    // dibuat = 1 (0 dianggap "tak diketahui" oleh hitungan umur); anak dibuat belakangan (masih muda) sehingga
    // di batch ia mundur TIMEOUT sendiri lalu ikut TINJAU lewat kaskade induk.
    let buat = 1
    const a = new Antrean({ berkas: null, sekarang: () => buat, buatId: () => 'dev-uji' })
    baris(a, 'tua')
    buat = 3000000
    a.antrekan({ clientRef: 'anak', jenis: 'REFUND', tokoId: 'T1', path: '/transaksi/lokal%3Atua/refund', body: { client_ref: 'anak', items: [{ baris: 0, kuantitas: 1 }] } })
    const { pg } = pengurai(a, {
      versi: mode === 'batch' ? 2 : 0,
      kebijakan,
      sekarang: () => 3600001,
      kirim: async () => ({ ...TIMEOUT }),
      kirimBatch: () => ({ ...TIMEOUT })
    })
    await pg.jalankan()
    const p = a.cari('tua')
    assert.equal(p.status, STATUS.TINJAU, mode)
    assert.equal(p.kode, null, mode)
    assert.equal(p.percobaan, 1, mode)
    assert.match(p.galat, /setelah data dikirim/, `${mode}: layak dipulihkan pemulih`)
    assert.match(p.galat, /lebih dari 1 jam/, mode)
    assert.equal(a.cari('anak').status, STATUS.TINJAU, mode)
    assert.equal(a.cari('anak').kode, 'INDUK_TINJAU', mode)
  }
})

test('TIMEOUT baris yang masih muda tetap mundur per baris walau batas umur ada', async () => {
  const a = new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-uji' })
  baris(a, 'muda')
  const { pg } = pengurai(a, { kebijakan: () => ({ maksPercobaanGalatServer: null, maksUmurJam: 1 }), kirimBatch: () => ({ ok: false, status: -1, gangguan: true, timeout: true }) })
  await pg.jalankan()
  assert.equal(a.cari('muda').status, STATUS.MENUNGGU)
  assert.equal(a.cari('muda').sebabTunda, 'TIMEOUT')
})

test('umur_detik dihitung per operasi saat dikirim (segmen berikutnya & kiriman ulang 409 tidak basi)', async () => {
  const a = new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-uji' })
  baris(a, 'c1'); baris(a, 'c2')
  let jam = 10001
  const umur = []
  const { pg } = pengurai(a, {
    maksOperasi: 1,
    sekarang: () => jam,
    kirimBatch: (b) => { umur.push(b.operations.map((op) => op.umur_detik)); jam += 20000; return terimaSemua(b) }
  })
  assert.equal(await pg.jalankan(), 2)
  assert.deepEqual(umur, [[10], [30]])
})

test('409 dijawab dua kali (ref bergaram pun bentrok) → galat server per baris, bukan kirim ketiga', async () => {
  const a = new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-uji' })
  baris(a, 'c1'); baris(a, 'c2')
  let jam = 10001
  const kiriman = []
  const { pg } = pengurai(a, {
    sekarang: () => jam,
    kirimBatch: (b) => { kiriman.push(b); jam += 5000; return { ok: false, status: 409, errors: { kode: ['BATCH_REF_BENTROK'] }, message: 'Bentrok' } }
  })
  assert.equal(await pg.jalankan(), 0)
  assert.equal(kiriman.length, 2)
  assert.notEqual(kiriman[0].client_ref, kiriman[1].client_ref)
  assert.deepEqual(kiriman.map((b) => b.operations[0].umur_detik), [10, 15], 'umur disegarkan pada kiriman bergaram')
  for (const r of ['c1', 'c2']) {
    const p = a.cari(r)
    assert.equal(p.status, STATUS.MENUNGGU, r)
    assert.equal(p.sebabTunda, 'SERVER', r)
    assert.equal(p.galatServer, 1, r)
    assert.match(p.galat, /HTTP 409/, r)
    assert.equal(p.kode, null, r)
  }
})

test('segmen dibelah menurut byte (≤70% maks_byte /config)', async () => {
  const a = antreanMemori()
  for (let i = 0; i < 5; i++) baris(a, `b${i}`, 'CHECKOUT', { body: { client_ref: `b${i}`, catatan: 'x'.repeat(1000) } })
  const ukuran = []
  const byte = []
  const { pg } = pengurai(a, { maksByte: 4000, kirimBatch: (b) => { ukuran.push(b.operations.length); byte.push(Buffer.byteLength(JSON.stringify(b.operations))); return terimaSemua(b) } })
  assert.equal(await pg.jalankan(), 5)
  assert.deepEqual(ukuran, [2, 2, 1])
  for (const n of byte) assert.ok(n <= 2800 + 10, `segmen ${n} byte`)
})

test('maks_operasi/saran/maks_byte /config pecahan dibulatkan ke bawah (10.5 → 10); < 1 = tanpa batas', async () => {
  assert.deepEqual(syncBatchDariConfig({ sync_batch: { versi: 2.9, maks_operasi: 10.5, maks_byte: 4000.7 } }), { versi: 2, maksOperasi: 10, maksByte: 4000 })
  assert.equal(syncBatchDariConfig({ sync_batch: { versi: 2, maks_operasi: 200, saran_operasi_per_segmen: 7.9 } }).maksOperasi, 7)
  assert.equal(syncBatchDariConfig({ sync_batch: { versi: 2, maks_operasi: 0.5 } }).maksOperasi, null)
  const a = antreanMemori()
  for (let i = 0; i < 5; i++) baris(a, `c${i}`)
  const ukuran = []
  const { pg } = pengurai(a, { maksOperasi: 2.5, kirimBatch: (b) => { ukuran.push(b.operations.length); return terimaSemua(b) } })
  await pg.jalankan()
  assert.deepEqual(ukuran, [2, 2, 1], 'aturSyncBatch ikut membulatkan')
})

test('429 BATCH_BERJALAN = jeda batch tingkat perangkat: putaran berikut di dalam jendela tidak mem-POST segmen lain', async () => {
  const a = antreanMemori()
  baris(a, 'c1'); baris(a, 'c2')
  let jam = 1000
  let ke = 0
  const jadwal = []
  const log = []
  const pg = new Pengurai({
    antrean: a,
    kirim: async (jalur, body, p) => { log.push(`baris:${p.clientRef}`); return { ok: true, status: 201, data: {} } },
    kirimBatch: async (b) => { log.push(`batch:${b.operations.map((op) => op.idempotency_key).join(',')}`); return ++ke === 1 ? { ok: false, status: 429, errors: { kode: ['BATCH_BERJALAN'] }, message: 'Masih diproses' } : terimaSemua(b) },
    sekarang: () => jam,
    jadwal: (fn, ms) => { jadwal.push(ms); return null },
    batalJadwal: () => {}
  })
  pg.aturSyncBatch({ versi: 2, maksOperasi: 1 })
  await pg.jalankan()
  assert.deepEqual(log, ['batch:c1'])
  jam = 2000
  assert.equal(await pg.jalankan(), 0)
  assert.deepEqual(log, ['batch:c1'], 'c2 (belum pernah dikirim) tidak di-POST selama jendela Retry-After')
  assert.equal(jadwal[jadwal.length - 1], 1000 + JEDA_BERJALAN_MS - 2000, 'timer digeser ke akhir jendela, bukan 1 dtk')
  jam = 1000 + JEDA_BERJALAN_MS
  assert.equal(await pg.jalankan(), 2)
  assert.deepEqual(log, ['batch:c1', 'batch:c1', 'batch:c2'])
})

// Paritas Flutter A-17 (memo /config 5 menit): 503 BATCH_TIDAK_TERSEDIA itu sementara (tabel idempotensi
// belum siap / gagal-tertutup) → batch dicoba lagi setelah 5 menit walau /config belum dimuat ulang.
// 404 (rute belum ada di server/gateway) tetap per baris sampai /config berikutnya.
test('503 BATCH_TIDAK_TERSEDIA mematikan batch 5 menit; 404 sampai /config berikutnya', async () => {
  const { BATCH_MATI_SEMENTARA_MS } = require('../src/main/offline/pengurai')
  assert.equal(BATCH_MATI_SEMENTARA_MS, 5 * 60 * 1000)
  let kini = 1000
  const a = antreanMemori()
  const { pg } = pengurai(a, { sekarang: () => kini })
  pg._olahJawabanBatch([], { ok: false, status: 503, gangguan: true, errors: { kode: ['BATCH_TIDAK_TERSEDIA'] } })
  assert.equal(pg.modeBatch(), false)
  kini += BATCH_MATI_SEMENTARA_MS - 1
  assert.equal(pg.modeBatch(), false, 'belum 5 menit')
  kini += 1
  assert.equal(pg.modeBatch(), true, 'lewat 5 menit → batch dicoba lagi')

  pg._olahJawabanBatch([], { ok: false, status: 404, gateway: 'route-unknown' })
  kini += BATCH_MATI_SEMENTARA_MS * 10
  assert.equal(pg.modeBatch(), false, '404 tidak kedaluwarsa sendiri')
  assert.equal(pg.aturSyncBatch({ versi: 2 }), true)
})
