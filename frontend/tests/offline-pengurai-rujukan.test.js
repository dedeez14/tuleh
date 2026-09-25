'use strict'

// Rujukan transaksi lokal & urutan kausal di pengurai (Fase 4, rancangan §C.7 + kritik B-2/B-7/B-8/B-14):
// refund/pembatalan atas checkout yang belum terkirim, penahan stok masuk → penjualan, kaskade TINJAU.

const test = require('node:test')
const assert = require('node:assert/strict')

const { Antrean, STATUS } = require('../src/main/offline/antrean')
const { Pengurai, JEDA_LAMA_MS, mundur, PENAHAN_KAUSAL, PESAN_TIMEOUT_SETELAH_KIRIM } = require('../src/main/offline/pengurai')
const { Pemulih } = require('../src/main/offline/pemulih')

const memori = () => new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-uji' })

function induk(a, ref = 'induk', toko = 'T1') {
  return a.antrekan({ clientRef: ref, jenis: 'CHECKOUT', tokoId: toko, path: '/transaksi/checkout', body: { client_ref: ref, items: [{ id_produk: 'P1' }, { id_produk: 'P2' }] } })
}
function anakRefund(a, ref = 'anak', indukRef = 'induk') {
  return a.antrekan({ clientRef: ref, jenis: 'REFUND', tokoId: 'T1', path: `/transaksi/lokal%3A${indukRef}/refund`, body: { client_ref: ref, items: [{ baris: 1, kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak' } })
}

function hasilBatch(badan, tolak = {}) {
  return {
    ok: true, status: 200,
    data: {
      versi: 2,
      results: badan.operations.map((op) => tolak[op.idempotency_key]
        ? { idempotency_key: op.idempotency_key, type: op.type, accepted: false, ...tolak[op.idempotency_key] }
        : { idempotency_key: op.idempotency_key, type: op.type, accepted: true, server_id: `srv-${op.idempotency_key}`, nomor: `N-${op.idempotency_key}`, kode: 'OK', peringatan: [], data: null })
    }
  }
}

function pengurai(a, o = {}) {
  const log = []
  const pg = new Pengurai({
    antrean: a,
    kirim: async (jalur, body, p) => { log.push({ jalur, body, ref: p.clientRef }); return o.kirim ? o.kirim(jalur, body, p) : { ok: true, status: 201, data: { nomor: `B-${p.clientRef}` } } },
    kirimBatch: async (badan) => { log.push({ batch: badan.operations.map((op) => op.idempotency_key), badan }); return (o.kirimBatch || hasilBatch)(badan) },
    sekarang: o.sekarang || (() => 1000),
    kebijakan: o.kebijakan || (() => null),
    pemulih: o.pemulih ? o.pemulih(a) : null,
    jadwal: o.jadwal || (() => null),
    batalJadwal: () => {}
  })
  if (o.batch) pg.aturSyncBatch({ versi: 2, maksOperasi: o.maksOperasi || null })
  return { pg, log }
}

test('per baris: anak ditahan tanpa penalti selama induk menunggu; induk terkirim → jalur & baris ditulis ulang ke id server', async () => {
  const a = memori()
  induk(a); anakRefund(a)
  let jam = 1000
  a.perbarui('induk', { sebabTunda: 'SERVER', cobaLagiSetelah: jam + 60000 })
  const { pg, log } = pengurai(a, {
    sekarang: () => jam,
    kirim: (jalur, body, p) => p.clientRef === 'induk'
      ? { ok: true, status: 201, data: { id: 'SRV1', nomor: 'POS-1', items: [{ id: 'I-a' }, { id: 'I-b' }] } }
      : { ok: true, status: 201, data: { nomor: 'RFD-1' } }
  })
  await pg.jalankan()
  assert.deepEqual(log, [], 'induk belum waktunya, anak tertahan')
  assert.equal(a.cari('anak').percobaan, 0)
  assert.equal(a.cari('anak').status, STATUS.MENUNGGU)

  jam += 60000
  assert.equal(await pg.jalankan(), 2)
  assert.deepEqual(log.map((x) => x.jalur), ['/transaksi/checkout', '/transaksi/SRV1/refund'])
  assert.deepEqual(log[1].body.items, [{ id: 'I-b', kuantitas: 1 }])
  assert.equal(a.cari('anak').hasil.nomor, 'RFD-1')
})

test('per baris: induk terkirim tanpa rincian baris (dipulihkan) → anak TINJAU INDUK_TIDAK_DIKENAL, tidak dikirim', async () => {
  const a = memori()
  induk(a); anakRefund(a)
  a.selesai('induk', { id: 'SRV2', nomor: 'POS-2', dipulihkan: true })
  const { pg, log } = pengurai(a)
  await pg.jalankan()
  assert.deepEqual(log, [])
  assert.equal(a.cari('anak').status, STATUS.TINJAU)
  assert.equal(a.cari('anak').kode, 'INDUK_TIDAK_DIKENAL')
})

test('batch: induk & anak di segmen yang sama → anak merujuk transaksi_ref induk', async () => {
  const a = memori()
  induk(a); anakRefund(a)
  const { pg, log } = pengurai(a, { batch: true })
  assert.equal(await pg.jalankan(), 2)
  assert.equal(log.length, 1)
  assert.deepEqual(log[0].batch, ['induk', 'anak'])
  const opAnak = log[0].badan.operations[1]
  assert.equal(opAnak.payload.transaksi_ref, 'induk')
  assert.deepEqual(opAnak.payload.items, [{ baris: 1, kuantitas: 1 }])
})

test('batch: induk sedang mundur galat server → anak tidak ikut segmen (tidak memancing PRASYARAT)', async () => {
  const a = memori()
  induk(a); anakRefund(a)
  a.perbarui('induk', { sebabTunda: 'SERVER', cobaLagiSetelah: 999999 })
  const jadwal = []
  const { pg, log } = pengurai(a, { batch: true, jadwal: (fn, ms) => { jadwal.push(ms); return null } })
  await pg.jalankan()
  assert.deepEqual(log, [])
  assert.deepEqual(jadwal, [999999 - 1000], 'baris tertahan tidak menjadwalkan timer 1 dtk sendiri')
})

test('kaskade: induk ditolak (VALIDASI) → anak TINJAU INDUK_TINJAU; kirim ulang induk memulihkan anak & keduanya terkirim', async () => {
  const a = memori()
  induk(a); anakRefund(a)
  let tolakInduk = true
  const { pg, log } = pengurai(a, {
    batch: true,
    kirimBatch: (b) => hasilBatch(b, tolakInduk ? {
      induk: { kode: 'VALIDASI', retriable: false, message: 'Produk belum punya satuan.' },
      anak: { kode: 'PRASYARAT', retriable: true, message: 'Transaksi asal belum tercatat.' }
    } : {})
  })
  await pg.jalankan()
  assert.equal(a.cari('induk').status, STATUS.TINJAU)
  assert.equal(a.cari('anak').status, STATUS.TINJAU)
  assert.equal(a.cari('anak').kode, 'INDUK_TINJAU')

  tolakInduk = false
  await pg.kirimUlang('induk')
  assert.deepEqual(log[1].batch, ['induk', 'anak'])
  assert.equal(a.cari('induk').status, STATUS.TERKIRIM)
  assert.equal(a.cari('anak').status, STATUS.TERKIRIM)
})

test('kaskade: anak yang masih menunggu ikut TINJAU saat induk ditinjau per baris (422)', async () => {
  const a = memori()
  induk(a); anakRefund(a)
  const { pg } = pengurai(a, { kirim: () => ({ ok: false, status: 422, message: 'Data tidak valid.' }) })
  await pg.jalankan()
  assert.equal(a.cari('induk').status, STATUS.TINJAU)
  assert.equal(a.cari('anak').kode, 'INDUK_TINJAU')
})

test('anak PRASYARAT dibebaskan dari jeda panjang begitu induk diterima', async () => {
  const a = memori()
  induk(a); anakRefund(a)
  let jam = 1000
  let putaran = 0
  const { pg, log } = pengurai(a, {
    batch: true,
    sekarang: () => jam,
    kirimBatch: (b) => {
      putaran++
      return putaran === 1
        ? hasilBatch(b, { induk: { kode: 'GALAT_SERVER', retriable: true, message: 'Galat.' }, anak: { kode: 'PRASYARAT', retriable: true, message: 'Belum.' } })
        : hasilBatch(b)
    }
  })
  await pg.jalankan()
  assert.equal(a.cari('anak').cobaLagiSetelah, 1000 + JEDA_LAMA_MS[0])
  jam += mundur(1)
  await pg.jalankan()
  assert.deepEqual(log[1].batch, ['induk'], 'anak masih dalam jeda saat induk dikirim')
  assert.equal(a.cari('anak').cobaLagiSetelah, null, 'dibebaskan setelah induk diterima')
  assert.equal(a.cari('anak').kode, null, 'kode PRASYARAT basi dibersihkan')
  assert.equal(a.cari('anak').galat, null)
  await pg.jalankan()
  assert.deepEqual(log[2].batch, ['anak'])
  assert.equal(a.cari('anak').status, STATUS.TERKIRIM)
})

test('penahan kausal: stok masuk toko T yang mundur menahan penjualan toko T sesudahnya, toko lain jalan', async () => {
  const a = memori()
  a.antrekan({ clientRef: 'stok', jenis: 'STOK_MASUK', tokoId: 'T1', path: '/inventory/stok-masuk', body: {} })
  induk(a, 'jual-t1', 'T1')
  induk(a, 'jual-t2', 'T2')
  a.perbarui('stok', { sebabTunda: 'SERVER', cobaLagiSetelah: 999999 })
  const { pg, log } = pengurai(a, { batch: true })
  await pg.jalankan()
  assert.deepEqual(log.map((x) => x.batch), [['jual-t2']])
  a.perbarui('stok', { status: STATUS.TINJAU })
  await pg.jalankan()
  assert.deepEqual(log[1].batch, ['jual-t1'], 'penahan gugur saat stok masuk ditinjau')
})

test('penahan kausal berlaku juga di mode per baris', async () => {
  const a = memori()
  a.antrekan({ clientRef: 'stok', jenis: 'STOK_MASUK', tokoId: 'T1', path: '/inventory/stok-masuk', body: {} })
  induk(a, 'jual', 'T1')
  a.perbarui('stok', { sebabTunda: 'TIMEOUT', cobaLagiSetelah: 999999 })
  const { pg, log } = pengurai(a)
  await pg.jalankan()
  assert.deepEqual(log, [])
})

// ── Perbaikan review Task 18 ──

const TIMEOUT = Object.freeze({ ok: false, status: -1, gangguan: true, timeout: true })
const BATAS_1_JAM = () => ({ maksPercobaanGalatServer: null, maksUmurJam: 1 })

/** Induk checkout tua (dibuat 1) + anak refund lokal muda (dibuat 3.000.000) — jam pengurai 3.600.001. */
function indukTuaAnakMuda() {
  let buat = 1
  const a = new Antrean({ berkas: null, sekarang: () => buat, buatId: () => 'dev-uji' })
  a.antrekan({ clientRef: 'tua', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: { client_ref: 'tua', tipe_pembayaran: 'TUNAI', items: [{ id_produk: 'P1', harga: 10000, kuantitas: 1 }] } })
  buat = 3000000
  a.antrekan({ clientRef: 'anak', jenis: 'REFUND', tokoId: 'T1', path: '/transaksi/lokal%3Atua/refund', body: { client_ref: 'anak', items: [{ baris: 0, kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak' } })
  return a
}

for (const mode of ['perBaris', 'batch']) {
  for (const cocok of [true, false]) {
    test(`pemulih asli (${mode}, ${cocok ? 'cocok di server' : 'belum tercatat'}): anak INDUK_TINJAU dari induk yang timeout tua ikut pulih`, async () => {
      const a = indukTuaAnakMuda()
      const daftarServer = cocok ? [{ id: 'SRV9', nomor: 'POS-9', grand_total: 10000, tanggal: new Date(1).toISOString(), tipe_pembayaran: 'TUNAI', status: 'SELESAI' }] : []
      let kirimanTua = 0
      let batchKe = 0
      const { pg, log } = pengurai(a, {
        batch: mode === 'batch',
        sekarang: () => 3600001,
        kebijakan: BATAS_1_JAM,
        pemulih: (x) => new Pemulih({ antrean: x, ambilDaftar: async () => daftarServer }),
        kirim: (jalur, body, p) => p.clientRef === 'tua'
          ? (++kirimanTua === 1 ? { ...TIMEOUT } : { ok: true, status: 201, data: { id: 'SRV1', nomor: 'POS-1', items: [{ id: 'I-a' }] } })
          : { ok: true, status: 201, data: { nomor: 'RFD-1' } },
        kirimBatch: (b) => (++batchKe === 1 ? { ...TIMEOUT } : hasilBatch(b))
      })
      await pg.jalankan()
      const tua = a.cari('tua')
      const anak = a.cari('anak')
      assert.equal(tua.status, STATUS.TERKIRIM)
      if (cocok) assert.equal(tua.hasil.dipulihkan, true)
      if (mode === 'perBaris' && cocok) {
        // Induk dipulihkan tanpa rincian baris: endpoint tunggal tak bisa dirujuk → pesan jelas, bukan INDUK_TINJAU selamanya.
        assert.equal(anak.status, STATUS.TINJAU)
        assert.equal(anak.kode, 'INDUK_TIDAK_DIKENAL')
      } else {
        assert.equal(anak.status, STATUS.TERKIRIM)
      }
      if (mode === 'perBaris' && !cocok) {
        assert.deepEqual(log.map((x) => x.jalur), ['/transaksi/checkout', '/transaksi/checkout', '/transaksi/SRV1/refund'])
      }
      if (mode === 'batch') {
        const kirimAnak = log.filter((x) => x.batch && x.batch.includes('anak'))
        assert.deepEqual(log.map((x) => x.batch), cocok ? [['tua', 'anak'], ['anak']] : [['tua', 'anak'], ['tua', 'anak']])
        assert.equal(kirimAnak[kirimAnak.length - 1].badan.operations.find((op) => op.idempotency_key === 'anak').payload.transaksi_ref, 'tua')
      }
    })
  }
}

test('TIMEOUT batch saat induk & anak sama-sama tua: anak INDUK_TINJAU (bukan teks timeout) → kirim ulang induk memulihkannya', async () => {
  const a = memori() // induk & anak dibuat 1
  induk(a, 'induk'); anakRefund(a)
  let batchKe = 0
  const { pg, log } = pengurai(a, { batch: true, sekarang: () => 3600001, kebijakan: BATAS_1_JAM, kirimBatch: (b) => (++batchKe === 1 ? { ...TIMEOUT } : hasilBatch(b)) })
  await pg.jalankan()
  assert.equal(a.cari('induk').status, STATUS.TINJAU)
  assert.equal(a.cari('induk').galat, `${PESAN_TIMEOUT_SETELAH_KIRIM} (tertunda lebih dari 1 jam; perlu ditinjau)`)
  assert.equal(a.cari('anak').status, STATUS.TINJAU)
  assert.equal(a.cari('anak').kode, 'INDUK_TINJAU')
  await pg.kirimUlang('induk')
  assert.deepEqual(log[1].batch, ['induk', 'anak'])
  assert.equal(a.cari('anak').status, STATUS.TERKIRIM)
})

test('batch: induk & anak terbelah segmen (batas 1 op) — anak dinilai ulang setelah jawaban induk', async () => {
  const kasus = [
    { nama: 'diterima', tolak: {}, harapLog: [['induk'], ['anak']], cek: (a) => assert.equal(a.cari('anak').status, STATUS.TERKIRIM) },
    { nama: 'ditolak', tolak: { induk: { kode: 'VALIDASI', retriable: false, message: 'Tidak valid.' } }, harapLog: [['induk']], cek: (a) => assert.equal(a.cari('anak').kode, 'INDUK_TINJAU') },
    { nama: 'mundur', tolak: { induk: { kode: 'GALAT_SERVER', retriable: true, message: 'Galat.' } }, harapLog: [['induk']], cek: (a) => { assert.equal(a.cari('anak').status, STATUS.MENUNGGU); assert.equal(a.cari('anak').percobaan, 0) } }
  ]
  for (const { nama, tolak, harapLog, cek } of kasus) {
    const a = memori()
    induk(a); anakRefund(a)
    const { pg, log } = pengurai(a, { batch: true, maksOperasi: 1, kirimBatch: (b) => hasilBatch(b, tolak) })
    await pg.jalankan()
    assert.deepEqual(log.map((x) => x.batch), harapLog, nama)
    if (nama === 'diterima') assert.equal(log[1].badan.operations[0].payload.transaksi_ref, 'induk')
    cek(a)
  }
})

test('penahan kausal: SESI_BUKA/OPNAME/BILL_BUKA toko T menahan CHECKOUT & BILL_BAYAR toko T; refund tidak ditahan', async () => {
  assert.deepEqual([...PENAHAN_KAUSAL].sort(), ['BILL_BUKA', 'OPNAME', 'SESI_BUKA', 'STOK_MASUK'])
  for (const jenis of ['SESI_BUKA', 'OPNAME', 'BILL_BUKA']) {
    for (const batch of [true, false]) {
      const a = memori()
      a.antrekan({ clientRef: 'penentu', jenis, tokoId: 'T1', path: '/penentu', body: {} })
      a.antrekan({ clientRef: 'bayar', jenis: 'BILL_BAYAR', tokoId: 'T1', path: '/bills/B1/settle', body: { client_ref: 'bayar' } })
      induk(a, 'jual', 'T1')
      a.antrekan({ clientRef: 'refund', jenis: 'REFUND', tokoId: 'T1', path: '/transaksi/TX1/refund', body: { client_ref: 'refund' } })
      a.perbarui('penentu', { sebabTunda: 'SERVER', cobaLagiSetelah: 999999 })
      const { pg, log } = pengurai(a, { batch })
      await pg.jalankan()
      const terkirim = log.flatMap((x) => x.batch || [x.ref])
      assert.deepEqual(terkirim, ['refund'], `${jenis} (${batch ? 'batch' : 'per baris'})`)
      assert.equal(a.cari('bayar').percobaan, 0, jenis)
    }
  }
})
