'use strict'

// Mode offline desktop (padanan Android fase 1–2): salinan baca per toko+jalur,
// antrean kirim FIFO ketat dengan mundur eksponensial, TINJAU untuk penolakan
// server / timeout setelah kirim, nomor lokal per hari, struk lokal.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const { SalinanBaca, kunciSalinan } = require('../src/main/offline/salinan')
const { Antrean, STATUS } = require('../src/main/offline/antrean')
const { Pengurai, mundur, PESAN_TIMEOUT_SETELAH_KIRIM } = require('../src/main/offline/pengurai')
const { NomorLokal, buatStrukLokal } = require('../src/main/offline/struk-lokal')

function dirSementara() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'tuleh-offline-'))
}

test('SalinanBaca: kunci per toko+jalur+query terurut; simpan, ambil, batas LRU, muat ulang dari berkas', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'salinan.json')
  let jam = 1000
  const s = new SalinanBaca({ berkas, maksEntri: 2, sekarang: () => jam++ })
  assert.equal(kunciSalinan('T1', '/produk', { page: 1, q: '' }), 'T1|/produk|page=1')
  assert.equal(kunciSalinan('T1', '/produk', { q: 'a', page: 1 }), kunciSalinan('T1', '/produk', { page: 1, q: 'a' }))

  s.simpan('T1', '/produk', { page: 1 }, { data: [1], meta: null })
  s.simpan('T1', '/pelanggan', {}, { data: [2] })
  assert.deepEqual(s.ambil('T1', '/produk', { page: 1 }).data, [1]) // disentuh → jadi terbaru
  s.simpan('T2', '/produk', {}, { data: [3] })
  assert.equal(s.jumlah, 2)
  assert.equal(s.ambil('T1', '/pelanggan', {}), null, 'yang paling lama tak disentuh dibuang')
  assert.ok(s.ambil('T1', '/produk', { page: 1 }))

  s.simpanSekarang()
  const s2 = new SalinanBaca({ berkas })
  assert.deepEqual(s2.ambil('T2', '/produk', {}).data, [3])
})

test('Antrean: FIFO, transaksi lokal & delta stok ikut, selesai/batalkan membersihkan, muat ulang MENGIRIM→MENUNGGU', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'antrean.json')
  const a = new Antrean({ berkas, sekarang: () => 5 })
  a.antrekan({ clientRef: 'a', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: { x: 1 } },
    { transaksi: { tokoId: 'T1', nomorLokal: 'L-1', waktuKlien: '2026-09-07T09:00:00', struk: { nomor: 'L-1' } }, deltaStok: { P1: -2 } })
  a.antrekan({ clientRef: 'b', jenis: 'PENGELUARAN', tokoId: 'T1', path: '/pengeluaran', body: {} }, { deltaStok: { P1: -1, P2: 5 } })
  assert.deepEqual(a.semua().map((p) => p.clientRef), ['a', 'b'])
  assert.deepEqual(a.deltaStokTertunda('T1'), { P1: -3, P2: 5 })
  assert.deepEqual(a.ringkas('T1'), { menunggu: 2, tinjau: 0, total: 2 })
  assert.equal(a.transaksiTertunda('T1').length, 1)

  a.perbarui('a', { status: STATUS.MENGIRIM })
  const a2 = new Antrean({ berkas })
  assert.equal(a2.cari('a').status, STATUS.MENUNGGU, 'proses mati saat mengirim → diulang')

  a2.selesai('a', { nomor: '26-POS-000041' })
  assert.equal(a2.cari('a').status, STATUS.TERKIRIM)
  assert.equal(a2.transaksiLokal('a'), null)
  assert.deepEqual(a2.deltaStokTertunda('T1'), { P1: -1, P2: 5 })
  a2.batalkan('b')
  assert.deepEqual(a2.deltaStokTertunda('T1'), {})
  assert.deepEqual(a2.ringkas('T1'), { menunggu: 0, tinjau: 0, total: 0 })
})

function antreanMemori() { return new Antrean({ berkas: null, sekarang: () => 0 }) }

function pesan(a, ref, jenis = 'CHECKOUT') {
  return a.antrekan({ clientRef: ref, jenis, tokoId: 'T1', path: '/x', body: { ref } })
}

test('Pengurai: sukses → TERKIRIM dengan hasil; ditolak 422 → TINJAU dengan pesan server; lanjut ke berikutnya', async () => {
  const a = antreanMemori()
  pesan(a, 'a'); pesan(a, 'b'); pesan(a, 'c')
  const log = []
  const kirim = async (p, body) => {
    log.push(body.ref)
    if (body.ref === 'b') return { ok: false, status: 422, message: 'x', errors: { items: ['Stok tidak cukup.'] } }
    return { ok: true, status: 200, data: { nomor: `N-${body.ref}` } }
  }
  const pg = new Pengurai({ antrean: a, kirim, jadwal: () => null, batalJadwal: () => {} })
  assert.equal(await pg.jalankan(), 2)
  assert.deepEqual(log, ['a', 'b', 'c'])
  assert.equal(a.cari('a').status, STATUS.TERKIRIM)
  assert.equal(a.cari('a').hasil.nomor, 'N-a')
  assert.equal(a.cari('b').status, STATUS.TINJAU)
  assert.equal(a.cari('b').galat, 'Stok tidak cukup.')
  assert.equal(a.cari('c').status, STATUS.TERKIRIM)
})

test('Pengurai: gagal jaringan → mundur eksponensial & FIFO ketat (yang di belakang ikut menunggu)', async () => {
  const a = antreanMemori()
  pesan(a, 'a'); pesan(a, 'b')
  let jam = 100000
  let hidup = false
  const log = []
  const kirim = async (p, body) => {
    log.push(body.ref)
    return hidup ? { ok: true, status: 200, data: {} } : { ok: false, status: 0, message: 'putus' }
  }
  const koneksi = { offline: false, tandaiOffline() { this.offline = true }, tandaiOnline() { this.offline = false } }
  const pg = new Pengurai({ antrean: a, kirim, koneksi, sekarang: () => jam, jadwal: () => null, batalJadwal: () => {} })
  assert.equal(await pg.jalankan(), 0)
  assert.deepEqual(log, ['a'], 'b tidak dikirim selagi a gagal')
  assert.equal(a.cari('a').percobaan, 1)
  assert.equal(a.cari('a').cobaLagiSetelah, jam + mundur(1))
  assert.equal(koneksi.offline, true)

  assert.equal(await pg.jalankan(), 0, 'belum waktunya coba lagi')
  assert.deepEqual(log, ['a'])

  jam += mundur(1)
  hidup = true
  assert.equal(await pg.jalankan(), 2)
  assert.deepEqual(log, ['a', 'a', 'b'])
  assert.equal(koneksi.offline, false)
  assert.deepEqual([mundur(1), mundur(2), mundur(3), mundur(4), mundur(5), mundur(9)], [5000, 15000, 45000, 120000, 600000, 600000])
})

test('Pengurai: timeout setelah kirim → TINJAU (tidak diulang); 401 → berhenti; kirimUlang memulihkan', async () => {
  const a = antreanMemori()
  pesan(a, 'a'); pesan(a, 'b')
  let mode = 'timeout'
  const kirim = async () => mode === 'timeout'
    ? { ok: false, status: -1, message: 'timeout' }
    : mode === '401' ? { ok: false, status: 401, message: 'Sesi berakhir' } : { ok: true, status: 200, data: {} }
  const pg = new Pengurai({ antrean: a, kirim, jadwal: () => null, batalJadwal: () => {} })
  await pg.jalankan()
  assert.equal(a.cari('a').status, STATUS.TINJAU)
  assert.equal(a.cari('a').galat, PESAN_TIMEOUT_SETELAH_KIRIM)
  assert.equal(a.cari('b').status, STATUS.TINJAU)

  mode = '401'
  await pg.kirimUlang('a')
  assert.equal(a.cari('a').status, STATUS.MENUNGGU, '401 → tetap menunggu sampai masuk lagi')

  mode = 'ok'
  await pg.jalankan()
  assert.equal(a.cari('a').status, STATUS.TERKIRIM)
})

test('NomorLokal: naik per hari, format L-yyMMdd-NNNN, tersimpan', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'nomor.json')
  const n = new NomorLokal({ berkas })
  assert.equal(n.berikutnya(new Date(2026, 8, 7)), 'L-260907-0001')
  assert.equal(n.berikutnya(new Date(2026, 8, 7)), 'L-260907-0002')
  assert.equal(new NomorLokal({ berkas }).berikutnya(new Date(2026, 8, 7)), 'L-260907-0003')
  assert.equal(n.berikutnya(new Date(2026, 8, 8)), 'L-260908-0001')
})

test('buatStrukLokal: bentuk sama dengan struk server, hitung diskon/pajak/kembalian', () => {
  const s = buatStrukLokal({
    nomor: 'L-260907-0001',
    body: {
      items: [
        { id_produk: 'P1', harga: 18000, kuantitas: 2, diskon_persen: 10, pajak_persen: 0 },
        { id_produk: 'P2', harga: 15000, kuantitas: 1, diskon_persen: 0, pajak_persen: 10 }
      ],
      tipe_pembayaran: 'TUNAI', dibayar: 100000, catatan: 'tanpa es'
    },
    tampilan: [{ id_produk: 'P1', nama: 'Kopi', satuan: 'Cup' }],
    kasir: 'Dede',
    waktu: new Date(Date.UTC(2026, 8, 7, 2))
  })
  assert.equal(s.nomor, 'L-260907-0001')
  assert.equal(s.belum_sinkron, true)
  assert.equal(s.items[0].nama, 'Kopi')
  assert.equal(s.items[1].nama, 'Produk P2')
  assert.equal(s.subtotal, 51000)
  assert.equal(s.total_diskon, 3600)
  assert.equal(s.total_pajak, 1500)
  assert.equal(s.grand_total, 48900)
  assert.equal(s.kembalian, 51100)
  assert.equal(s.catatan, 'tanpa es')
  assert.equal(s.kasir, 'Dede')
})

const { Pemulih } = require('../src/main/offline/pemulih')

function tinjau(a, ref, total, tipe, waktuMs) {
  return a.antrekan({
    clientRef: ref, jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout',
    body: { items: [{ id_produk: 'P1', kuantitas: 1, harga: total }], tipe_pembayaran: tipe, dibayar: total, waktu_klien: new Date(waktuMs).toISOString() },
    status: STATUS.TINJAU, galat: PESAN_TIMEOUT_SETELAH_KIRIM
  }, { transaksi: { tokoId: 'T1', nomorLokal: `L-${ref}`, waktuKlien: new Date(waktuMs).toISOString(), struk: { grand_total: total } } })
}
const trxServer = (id, total, tipe, waktuMs, status = 'SELESAI') =>
  ({ id, nomor: `N-${id}`, grand_total: total, tipe_pembayaran: tipe, status, tanggal: new Date(waktuMs).toISOString() })

test('Pemulih: satu kandidat → TERKIRIM; tanpa kandidat → MENUNGGU; ganda → TINJAU dengan petunjuk; gagal tarik → dibiarkan', async () => {
  const jam = Date.parse('2026-09-08T07:00:00Z')
  const a = antreanMemori()
  tinjau(a, 'a', 25000, 'TUNAI', jam)
  tinjau(a, 'b', 40000, 'QRIS', jam)
  tinjau(a, 'c', 15000, 'TUNAI', jam)
  const daftar = [
    trxServer('s1', 25000, 'TUNAI', jam + 3 * 60000),
    trxServer('s2', 25000, 'TUNAI', jam - 3 * 3600000),          // di luar jendela
    trxServer('s3', 25000, 'TUNAI', jam, 'DIBATALKAN'),           // dibatalkan
    trxServer('s4', 15000, 'TUNAI', jam + 60000),
    trxServer('s5', 15000, 'TUNAI', jam - 120000)                 // ganda untuk c
  ]
  const dipanggil = []
  const pm = new Pemulih({ antrean: a, ambilDaftar: async (toko, dari, sampai) => { dipanggil.push([toko, dari, sampai]); return daftar } })
  assert.equal(await pm.jalankan(), 2)
  assert.equal(a.cari('a').status, STATUS.TERKIRIM)
  assert.equal(a.cari('a').hasil.nomor, 'N-s1')
  assert.equal(a.transaksiLokal('a'), null)
  assert.equal(a.cari('b').status, STATUS.MENUNGGU, 'tidak ada QRIS 40.000 → dikirim ulang')
  assert.equal(a.cari('c').status, STATUS.TINJAU)
  assert.match(a.cari('c').galat, /N-s4, N-s5/)
  assert.equal(dipanggil.length, 1, 'daftar per toko+tanggal ditarik sekali')
  assert.deepEqual(dipanggil[0], ['T1', '2026-09-07', '2026-09-09'])

  const d = antreanMemori()
  tinjau(d, 'x', 25000, 'TUNAI', jam)
  const gagal = new Pemulih({ antrean: d, ambilDaftar: async () => null })
  assert.equal(await gagal.jalankan(), 0)
  assert.equal(d.cari('x').status, STATUS.TINJAU)
  assert.equal(d.cari('x').galat, PESAN_TIMEOUT_SETELAH_KIRIM)
})

test('Pengurai + Pemulih: baris yang dipastikan belum tercatat dikirim ulang di putaran yang sama', async () => {
  const jam = Date.parse('2026-09-08T07:00:00Z')
  const a = antreanMemori()
  tinjau(a, 'a', 25000, 'TUNAI', jam)
  let kirim = 0
  const pm = new Pemulih({ antrean: a, ambilDaftar: async () => [trxServer('z', 99000, 'TUNAI', jam)] })
  const pg = new Pengurai({
    antrean: a,
    pemulih: pm,
    kirim: async () => { kirim++; return { ok: true, status: 201, data: { nomor: '26-POS-000077' } } },
    jadwal: () => null, batalJadwal: () => {}
  })
  assert.equal(await pg.jalankan(), 1)
  assert.equal(kirim, 1)
  assert.equal(a.cari('a').status, STATUS.TERKIRIM)
  assert.equal(a.cari('a').hasil.nomor, '26-POS-000077')
})
