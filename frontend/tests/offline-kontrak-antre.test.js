'use strict'

// Fase 4: kanal tulis yang boleh diantrekan desktop (refund, batal, bayar bon, transisi pesanan) membawa
// client_ref/waktu_klien; refund transaksi lokal merujuk baris lewat indeks; penulis antrean menghormati
// client_ref pemanggil dan hanya menambah tanda offline/nomor lokal pada baris yang benar-benar diantrekan.

const test = require('node:test')
const assert = require('node:assert/strict')

const kontrak = require('../src/shared/kontrak-kanal.js')
const { Antrean, STATUS, buatClientRef, waktuKlien } = require('../src/main/offline/antrean')
const { buatTulisAtauAntre } = require('../src/main/offline/tulis')
const { Koneksi } = require('../src/main/offline')
const { NomorLokal, buatStrukLokal, strukCadangan } = require('../src/main/offline/struk-lokal')

const badan = (m) => JSON.parse(JSON.stringify(m.body))

function offlinePalsu(online = true) {
  const koneksi = new Koneksi()
  if (!online) koneksi.tandaiOffline()
  return { koneksi, antrean: new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-uji' }), STATUS, buatClientRef, waktuKlien }
}

test('kanal ber-antrean desktop: jenis sesuai kontrak', () => {
  const jenis = Object.fromEntries(Object.entries(kontrak.KANAL).filter(([, e]) => e.antrean).map(([k, e]) => [k, e.antrean.jenis]))
  assert.deepEqual(jenis, {
    'order:transition': 'ORDER_TRANSISI',
    'order:konfirmasiBayar': 'ORDER_TRANSISI',
    'order:lunasi': 'ORDER_TRANSISI',
    'bill:bayar': 'BILL_BAYAR',
    'inventory:stokMasuk': 'STOK_MASUK',
    'pengeluaran:create': 'PENGELUARAN',
    'trx:batal': 'BATAL',
    'trx:refund': 'REFUND'
  })
})

test('trx:batal, bill:bayar, order:* meneruskan client_ref & waktu_klien bila ada; tanpa itu badan lama utuh', () => {
  assert.deepEqual(badan(kontrak.bentuk('trx:batal', { id: 'T1', alasan: 'Salah input', clientRef: 'b-1', waktuKlien: '2026-09-24T10:30:00' })),
    { alasan: 'Salah input', client_ref: 'b-1', waktu_klien: '2026-09-24T10:30:00' })
  assert.deepEqual(badan(kontrak.bentuk('trx:batal', { id: 'T1' })), {})
  assert.equal(kontrak.bentuk('trx:batal', { id: 'lokal:abc' }).jalur, '/transaksi/lokal%3Aabc/batal')
  assert.deepEqual(badan(kontrak.bentuk('bill:bayar', { id: 'B1', tipePembayaran: 'QRIS', clientRef: 's-1' })), { tipe_pembayaran: 'QRIS', dibayar: null, client_ref: 's-1' })
  assert.deepEqual(badan(kontrak.bentuk('bill:bayar', { id: 'B1', tipePembayaran: 'TUNAI', dibayar: 50000 })), { tipe_pembayaran: 'TUNAI', dibayar: 50000 })
  assert.deepEqual(badan(kontrak.bentuk('order:lunasi', { id: 'O1', tipePembayaran: 'TUNAI', clientRef: 'o-1', waktuKlien: '2026-09-24T11:00:00' })),
    { to: 'SELESAI', tipe_pembayaran: 'TUNAI', client_ref: 'o-1', waktu_klien: '2026-09-24T11:00:00' })
  assert.deepEqual(badan(kontrak.bentuk('order:transition', { id: 'O1', to: 'DIPROSES' })), { to: 'DIPROSES' })
  assert.deepEqual(badan(kontrak.bentuk('order:konfirmasiBayar', { id: 'O1', tipePembayaran: 'TUNAI', clientRef: 'o-2' })), { to: 'ANTRIAN', tipe_pembayaran: 'TUNAI', client_ref: 'o-2' })
})

test('trx:refund menerima rujukan baris (transaksi lokal) ATAU id — tidak keduanya', () => {
  const m = kontrak.bentuk('trx:refund', { id: 'lokal:abc', baris: [{ baris: 1, kuantitas: 2 }, { baris: 0, kuantitas: 0.5 }], metode: 'TUNAI', alasan: 'Rusak' })
  assert.equal(m.jalur, '/transaksi/lokal%3Aabc/refund')
  assert.deepEqual(badan(m).items, [{ baris: 1, kuantitas: 2 }, { baris: 0, kuantitas: 0.5 }])
  assert.throws(() => kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ baris: -1, kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak' }), /tidak valid/)
  assert.throws(() => kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ baris: 1.5, kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak' }), /tidak valid/)
  assert.throws(() => kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ id: 'I1', baris: 0, kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak' }), /tidak valid/)
  assert.deepEqual(badan(kontrak.bentuk('trx:refund', { id: 'T1', baris: [{ id: 'I1', kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak' })).items, [{ id: 'I1', kuantitas: 1 }])
})

test('tulisAtauAntre: client_ref & waktu_klien pemanggil dipertahankan; pemilik & toko dicatat', async () => {
  const off = offlinePalsu()
  const dikirim = []
  const tulis = buatTulisAtauAntre({ offline: off, kirim: async (j, b) => { dikirim.push(b); return { ok: false, status: 0, gangguan: true } }, tokoAktif: () => 'T1', pemilikAktif: () => 'k@toko.test' })
  const r = await tulis({ jenis: 'REFUND', jalur: '/transaksi/T1/refund', body: { items: [], client_ref: 'rf-1', waktu_klien: '2026-09-24T10:00:00' } })
  assert.equal(r.tertunda, true)
  assert.equal(r.clientRef, 'rf-1')
  assert.equal(dikirim[0].client_ref, 'rf-1', 'percobaan online memakai ref lembar yang sama')
  const p = off.antrean.cari('rf-1')
  assert.equal(p.body.waktu_klien, '2026-09-24T10:00:00')
  assert.equal(p.pemilik, 'k@toko.test')
  assert.equal(p.tokoId, 'T1')
})

test('tulisAtauAntre: langsungAntre (rujukan transaksi lokal) tidak mencoba kirim walau online', async () => {
  const off = offlinePalsu(true)
  let dikirim = 0
  const tulis = buatTulisAtauAntre({ offline: off, kirim: async () => { dikirim++; return { ok: true } }, tokoAktif: () => 'T1' })
  const r = await tulis({ jenis: 'BATAL', jalur: '/transaksi/lokal%3Ac1/batal', body: {}, langsungAntre: true })
  assert.equal(r.tertunda, true)
  assert.equal(dikirim, 0)
  assert.equal(off.antrean.cari(r.clientRef).pemilik, null, 'tanpa pemilikAktif → null (diklaim saat akun dikenali)')
})

test('tulisAtauAntre: siapkanAntre HANYA untuk baris yang benar-benar diantrekan', async () => {
  const sukses = offlinePalsu(true)
  let dipanggil = 0
  const siapkan = (b) => { dipanggil++; return { body: { ...b, offline: true, nomor_lokal: 'L-X' }, transaksi: { tokoId: 'T1', nomorLokal: 'L-X', struk: { nomor: 'L-X' } } } }
  const t1 = buatTulisAtauAntre({ offline: sukses, kirim: async (j, b) => ({ ok: true, status: 201, data: { nomor: 'POS/1', badan: b } }), tokoAktif: () => 'T1' })
  const r1 = await t1({ jenis: 'CHECKOUT', jalur: '/transaksi/checkout', body: { items: [] }, siapkanAntre: siapkan })
  assert.equal(r1.ok, true)
  assert.equal(dipanggil, 0, 'terkirim langsung → tanpa nomor lokal')
  assert.equal(r1.data.badan.offline, undefined, 'kiriman online tidak membawa tanda offline')

  const gagal = offlinePalsu(true)
  const t2 = buatTulisAtauAntre({ offline: gagal, kirim: async () => ({ ok: false, status: 502, gangguan: true, gateway: 'upstream-unreachable' }), tokoAktif: () => 'T1' })
  const r2 = await t2({ jenis: 'CHECKOUT', jalur: '/transaksi/checkout', body: { items: [] }, siapkanAntre: siapkan })
  assert.equal(r2.tertunda, true)
  assert.equal(dipanggil, 1)
  const p = gagal.antrean.cari(r2.clientRef)
  assert.equal(p.body.offline, true)
  assert.equal(p.body.nomor_lokal, 'L-X')
  assert.equal(p.body.client_ref, r2.clientRef)
  assert.equal(gagal.antrean.transaksiLokal(r2.clientRef).nomorLokal, 'L-X')
})

test('NomorLokal: awalan 4 karakter perangkat (huruf besar); tanpa awalan = format lama', () => {
  const n = new NomorLokal({ berkas: null })
  assert.equal(n.berikutnya(new Date(2026, 8, 24), '3b9d6c1e-6a0f'), 'L-3B9D-260924-0001')
  assert.equal(n.berikutnya(new Date(2026, 8, 24), '3b9d6c1e-6a0f'), 'L-3B9D-260924-0002')
  assert.equal(n.berikutnya(new Date(2026, 8, 24)), 'L-260924-0003')
  assert.equal(n.berikutnya(new Date(2026, 8, 24), '--'), 'L-260924-0004', 'awalan tanpa huruf/angka diabaikan')
})

test('buatStrukLokal: baris per nominal ditandai per_nominal (tak bisa direfund sebagian sebelum tersinkron)', () => {
  const s = buatStrukLokal({ nomor: 'L-1', body: { items: [{ id_produk: 'P1', harga: 12000, kuantitas: 0.5, nominal: 6000 }, { id_produk: 'P2', harga: 5000, kuantitas: 1 }], tipe_pembayaran: 'TUNAI', dibayar: 11000 } })
  assert.equal(s.items[0].per_nominal, true)
  assert.equal('per_nominal' in s.items[1], false)
})

test('tulisAtauAntre: client_ref yang masih ada di antrean (belum terkirim) tidak diantrekan dua kali & tidak dicoba online', async () => {
  const off = offlinePalsu(true)
  let dikirim = 0
  const tulis = buatTulisAtauAntre({ offline: off, kirim: async () => { dikirim++; return { ok: false, status: 0, gangguan: true } }, tokoAktif: () => 'T1', pemilikAktif: () => 'k@toko.test' })
  const r1 = await tulis({ jenis: 'REFUND', jalur: '/transaksi/T1/refund', body: { items: [], client_ref: 'rf-1' } })
  assert.equal(r1.tertunda, true)
  assert.equal(dikirim, 1)
  // Tombol yang sama ditekan lagi (lembar refund yang sama) selagi baris pertama masih menunggu / ditinjau.
  for (const status of [STATUS.MENUNGGU, STATUS.TINJAU]) {
    off.antrean.perbarui('rf-1', { status })
    const r2 = await tulis({ jenis: 'REFUND', jalur: '/transaksi/T1/refund', body: { items: [], client_ref: 'rf-1' } })
    const harap = { ok: true, status: 202, data: null, meta: null, message: '', tertunda: true, clientRef: 'rf-1' }
    // Baris ditinjau: layar menampilkan "periksa Pengaturan → Sinkronisasi" (pos.js membaca perluTinjau).
    if (status === STATUS.TINJAU) harap.perluTinjau = true
    assert.deepEqual(r2, harap)
  }
  assert.equal(dikirim, 1, 'tidak ada percobaan online kedua')
  assert.equal(off.antrean.semua().filter((p) => p.clientRef === 'rf-1').length, 1, 'tetap satu baris')

  // Sudah terkirim → jalur biasa (server memutar ulang jawaban menurut client_ref).
  off.antrean.selesai('rf-1', { id: 'R1' })
  const t2 = buatTulisAtauAntre({ offline: off, kirim: async () => { dikirim++; return { ok: true, status: 200, data: { id: 'R1' } } }, tokoAktif: () => 'T1' })
  const r3 = await t2({ jenis: 'REFUND', jalur: '/transaksi/T1/refund', body: { items: [], client_ref: 'rf-1' } })
  assert.equal(r3.ok, true)
  assert.equal(r3.tertunda, undefined)
  assert.equal(dikirim, 2)
})

test('tulisAtauAntre: siapkanAntre melempar → tetap diantrekan dengan badan & transaksi dasar, galat dilaporkan', async () => {
  const off = offlinePalsu(false)
  const laporan = []
  const tulis = buatTulisAtauAntre({
    offline: off, kirim: async () => ({ ok: true }), tokoAktif: () => 'T1',
    laporGalat: (pesan, err) => laporan.push({ pesan, err })
  })
  const r = await tulis({
    jenis: 'CHECKOUT', jalur: '/transaksi/checkout', body: { items: [{ id_produk: 'P1' }] },
    transaksi: { tokoId: 'T1', nomorLokal: 'DASAR' },
    siapkanAntre: () => { throw new Error('nomor lokal rusak') }
  })
  assert.equal(r.tertunda, true)
  const p = off.antrean.cari(r.clientRef)
  assert.ok(p, 'operasi tidak hilang')
  assert.deepEqual(p.body.items, [{ id_produk: 'P1' }])
  assert.equal(p.body.client_ref, r.clientRef)
  assert.equal(typeof p.body.waktu_klien, 'string')
  assert.equal(off.antrean.transaksiLokal(r.clientRef).nomorLokal, 'DASAR')
  assert.equal(laporan.length, 1)
  assert.match(laporan[0].pesan, /nomor lokal rusak/)

  // Tanpa laporGalat → tidak melempar (bawaan: console.error).
  const asli = console.error
  let dicatat = 0
  console.error = () => { dicatat++ }
  try {
    const t2 = buatTulisAtauAntre({ offline: off, kirim: async () => ({ ok: true }), tokoAktif: () => 'T1' })
    const r2 = await t2({ jenis: 'CHECKOUT', jalur: '/transaksi/checkout', body: {}, siapkanAntre: () => { throw new Error('x') } })
    assert.equal(r2.tertunda, true)
    assert.ok(off.antrean.cari(r2.clientRef))
  } finally { console.error = asli }
  assert.equal(dicatat, 1)
})

test('trx:refund: indeks baris hanya bilangan bulat ≥ 0 atau teks digit (true/false/[2]/"1.0" ditolak)', () => {
  const refund = (baris) => kontrak.bentuk('trx:refund', { id: 'lokal:abc', baris: [{ baris, kuantitas: 1 }], metode: 'TUNAI', alasan: 'Rusak' })
  for (const salah of [true, false, [2], [], {}, '1.0', ' 2', '-1', '1e1', 1.5, -1, NaN, Infinity]) {
    assert.throws(() => refund(salah), /tidak valid/, `baris ${JSON.stringify(salah)} harus ditolak`)
  }
  assert.deepEqual(badan(refund(0)).items, [{ baris: 0, kuantitas: 1 }])
  assert.deepEqual(badan(refund(3)).items, [{ baris: 3, kuantitas: 1 }])
  assert.deepEqual(badan(refund('2')).items, [{ baris: 2, kuantitas: 1 }])
})

test('tulisAtauAntre: ref sama sudah TERKIRIM + offline / galat jaringan → hasil tersimpan dikembalikan, tanpa baris baru', async () => {
  // (i) offline: tidak ada percobaan online; hasil per baris = data server mentah.
  const off = offlinePalsu(false)
  off.antrean.antrekan({ clientRef: 'rf-1', jenis: 'REFUND', tokoId: 'T1', path: '/transaksi/T1/refund', body: {} })
  off.antrean.selesai('rf-1', { id: 'R1', nomor: 'RF/1', total_refund: 5000, _idempoten: true })
  let dikirim = 0
  const t1 = buatTulisAtauAntre({ offline: off, kirim: async () => { dikirim++; return { ok: true } }, tokoAktif: () => 'T1' })
  const r1 = await t1({ jenis: 'REFUND', jalur: '/transaksi/T1/refund', body: { items: [], client_ref: 'rf-1' }, siapkanAntre: () => { throw new Error('tak boleh dipanggil') } })
  assert.deepEqual(r1, { ok: true, status: 200, data: { id: 'R1', nomor: 'RF/1', total_refund: 5000 }, meta: null, message: '', clientRef: 'rf-1', dariAntrean: true })
  assert.equal(dikirim, 0)
  assert.equal(off.antrean.semua().length, 1, 'tidak ada baris baru')

  // (ii) online tetapi galat jaringan: dicoba online dulu, lalu hasil tersimpan (bentuk hasil batch).
  const on = offlinePalsu(true)
  on.antrean.antrekan({ clientRef: 'b-1', jenis: 'BATAL', tokoId: 'T1', path: '/transaksi/T1/batal', body: {} })
  on.antrean.selesai('b-1', { id: 'T1', nomor: 'POS/1', kode: 'OK', tipe: 'transaksi.batal', peringatan: [], idempoten: false, _idempoten: false, data: null })
  const t2 = buatTulisAtauAntre({ offline: on, kirim: async () => { dikirim++; return { ok: false, status: 0, gangguan: true } }, tokoAktif: () => 'T1' })
  const r2 = await t2({ jenis: 'BATAL', jalur: '/transaksi/T1/batal', body: { client_ref: 'b-1' } })
  assert.deepEqual(r2, { ok: true, status: 200, data: { id: 'T1', nomor: 'POS/1' }, meta: null, message: '', clientRef: 'b-1', dariAntrean: true })
  assert.equal(dikirim, 1, 'tetap dicoba online dulu')
  assert.equal(on.antrean.semua().length, 1)

  // Hasil batch ber-data → data itu yang dikembalikan.
  on.antrean.perbarui('b-1', { hasil: { id: 'T1', nomor: 'POS/1', kode: 'OK', tipe: 'transaksi.batal', peringatan: [], idempoten: true, data: { status: 'DIBATALKAN' } } })
  assert.deepEqual((await t2({ jenis: 'BATAL', jalur: '/transaksi/T1/batal', body: { client_ref: 'b-1' } })).data, { status: 'DIBATALKAN' })
})

test('Antrean.antrekan: clientRef yang sudah ada → baris itu dikembalikan, tidak ditambah (pertahanan berlapis)', () => {
  const a = new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-uji' })
  const p1 = a.antrekan({ clientRef: 'x', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: { a: 1 } }, { transaksi: { nomorLokal: 'L-1' }, deltaStok: { P1: -1 } })
  const seq = a.perangkat().seqTerakhir
  const p2 = a.antrekan({ clientRef: 'x', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: { a: 2 } }, { transaksi: { nomorLokal: 'L-2' }, deltaStok: { P1: -5 } })
  assert.equal(p2, p1)
  assert.equal(a.semua().length, 1)
  assert.equal(a.perangkat().seqTerakhir, seq, 'nomor urut perangkat tidak terpakai')
  assert.equal(a.transaksiLokal('x').nomorLokal, 'L-1')
  assert.deepEqual(a.deltaStokTertunda(), { P1: -1 })
})

test('strukCadangan: struk minimal dari badan checkout bila struk lokal gagal disusun (renderer tak boleh meledak)', () => {
  const body = { items: [{ id_produk: 'P1', harga: 10000, kuantitas: 2 }, { id_produk: 'P2', harga: 5000, kuantitas: 1, diskon_persen: 10 }], tipe_pembayaran: 'TUNAI', dibayar: 30000 }
  // tampilan rusak (null) membuat buatStrukLokal melempar → cadangan tetap menghitung dari badan.
  assert.throws(() => buatStrukLokal({ nomor: 'L-1', body, tampilan: [null] }))
  const s = strukCadangan({ body, tampilan: [null] })
  assert.equal(s.nomor, null)
  assert.equal(s.items.length, 2)
  assert.equal(s.grand_total, 24500)
  assert.equal(s.dibayar, 30000)
  assert.equal(s.kembalian, 5500)
  assert.equal(s.tipe_pembayaran, 'TUNAI')
  assert.equal(s.belum_sinkron, true)
  assert.equal(s.catatan_kaki, 'Belum tersinkron — struk lengkap tersedia setelah sinkron.')

  // Badan rusak pun menghasilkan struk minimal yang aman dibaca.
  for (const rusak of [null, {}, { items: 'x', dibayar: 'abc' }, { items: [null, 5] }]) {
    const m = strukCadangan({ body: rusak })
    assert.equal(m.nomor, null)
    assert.ok(Array.isArray(m.items))
    assert.equal(typeof m.grand_total, 'number')
    assert.equal(typeof m.dibayar, 'number')
    assert.equal(m.kembalian, 0)
    assert.match(m.catatan_kaki, /Belum tersinkron/)
  }
})
