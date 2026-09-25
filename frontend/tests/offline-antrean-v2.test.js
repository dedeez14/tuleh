'use strict'

// Antrean v2 (Fase 4 /sync/v2/batch): identitas perangkat + nomor urut perangkat yang tak pernah mundur,
// pemilik baris, migrasi berkas lama, tulis kolektif satu kali, rujukan transaksi lokal & pembatalan berantai.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const { Antrean, STATUS, labelJenis, waktuKlienZona, kunciPemilik, refIndukLokal, MAKS_TERKIRIM } = require('../src/main/offline/antrean')

function dirSementara() { return fs.mkdtempSync(path.join(os.tmpdir(), 'tuleh-antrean-v2-')) }
function memori() { return new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-memori' }) }

test('perangkat: id dibuat sekali & tersimpan; deviceSeq naik dan tidak mundur setelah baris dibuang', () => {
  const berkas = path.join(dirSementara(), 'antrean.json')
  let n = 0
  const a = new Antrean({ berkas, sekarang: () => 1, buatId: () => `dev-${++n}` })
  const p1 = a.antrekan({ clientRef: 'a', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {}, pemilik: 'k@toko.test' })
  const p2 = a.antrekan({ clientRef: 'b', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {}, pemilik: 'k@toko.test' })
  assert.equal(p1.deviceSeq, 1)
  assert.equal(p2.deviceSeq, 2)
  assert.equal(p1.pemilik, 'k@toko.test')
  assert.equal(p1.kirimUlangKe, 0)
  assert.equal(p1.kode, null)
  a.batalkan('a')
  a.batalkan('b')

  const b = new Antrean({ berkas, sekarang: () => 1, buatId: () => `dev-${++n}` })
  assert.equal(b.perangkat().id, 'dev-1', 'id perangkat tidak dibuat ulang')
  assert.equal(b.perangkat().seqTerakhir, 2)
  assert.equal(b.antrekan({ clientRef: 'c', jenis: 'CHECKOUT', path: '/x', body: {} }).deviceSeq, 3, 'tidak dihitung ulang dari baris tersisa')
  const isi = JSON.parse(fs.readFileSync(berkas, 'utf8'))
  assert.equal(isi.versi, 2)
  assert.equal(isi.perangkat.id, 'dev-1')
  assert.equal(isi.perangkat.seqTerakhir, 3)
})

test('berkas lama tanpa perangkat: id baru, deviceSeq = urut, seqTerakhir = urut terbesar; MENGIRIM → MENUNGGU', () => {
  const berkas = path.join(dirSementara(), 'antrean.json')
  fs.writeFileSync(berkas, JSON.stringify({
    pesan: [
      { urut: 3, clientRef: 'x', jenis: 'CHECKOUT', path: '/transaksi/checkout', body: {}, status: 'MENUNGGU', percobaan: 0 },
      { urut: 7, clientRef: 'y', jenis: 'PENGELUARAN', path: '/pengeluaran', body: {}, status: 'MENGIRIM', percobaan: 1 }
    ],
    transaksi: {},
    delta: []
  }))
  const a = new Antrean({ berkas, sekarang: () => 1, buatId: () => 'dev-baru' })
  assert.equal(a.perangkat().id, 'dev-baru')
  assert.equal(a.perangkat().seqTerakhir, 7)
  assert.equal(a.perangkat().syncBatchVersi, 0)
  assert.deepEqual(a.semua().map((p) => p.deviceSeq), [3, 7])
  assert.equal(a.cari('y').status, STATUS.MENUNGGU)
  assert.equal(a.antrekan({ clientRef: 'z', jenis: 'CHECKOUT', path: '/x', body: {} }).deviceSeq, 8)
})

test('berkas 0.9.40 (format versi 1) utuh: semua baris, struk, delta & field lama bertahan; tulis berikutnya = versi 2 tanpa kehilangan baris', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'antrean.json')
  // Bentuk persis tulisan 0.9.40: JSON.stringify({ pesan, transaksi, delta }) — tanpa `versi`/`perangkat`,
  // baris tanpa deviceSeq/pemilik/kode/kirimUlangKe, ditambah field yang diisi pengurai lama.
  const struk = { nomor: 'L-260924-0001', total: 25000, items: [{ nama: 'Kopi', qty: 1 }] }
  const lama = {
    pesan: [
      { urut: 4, clientRef: 'co-1', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: { items: [{ id_produk: 'P1', qty: 1 }], waktu_klien: '2026-09-24T10:00:00' }, dibuat: 1000, status: 'MENUNGGU', percobaan: 0, cobaLagiSetelah: null, galat: null, hasil: null },
      { urut: 5, clientRef: 'pg-1', jenis: 'PENGELUARAN', tokoId: 'T1', path: '/pengeluaran', body: { jumlah: 5000 }, dibuat: 1100, status: 'TINJAU', percobaan: 6, galatServer: 6, cobaLagiSetelah: null, sebabTunda: null, galat: 'Server menolak data ini.', hasil: null },
      { urut: 6, clientRef: 'sm-1', jenis: 'STOK_MASUK', tokoId: 'T2', path: '/inventory/stok-masuk', body: { jumlah: 2 }, dibuat: 1200, status: 'TERKIRIM', percobaan: 1, cobaLagiSetelah: null, galat: null, hasil: { nomor: 'SM/0007', id: 'enc-7' } },
      { urut: 9, clientRef: 'sb-1', jenis: 'SESI_BUKA', tokoId: 'T1', path: '/sesi/buka', body: { modal_awal: 100000 }, dibuat: 1300, status: 'MENGIRIM', percobaan: 2, cobaLagiSetelah: 5000, sebabTunda: 'UPDATE', galat: 'Perbarui aplikasi.', hasil: null }
    ],
    transaksi: { 'co-1': { tokoId: 'T1', nomorLokal: 'L-260924-0001', waktuKlien: '2026-09-24T10:00:00', struk, clientRef: 'co-1' } },
    delta: [{ clientRef: 'co-1', idProduk: 'P1', delta: -1 }, { clientRef: 'pg-1', idProduk: 'P2', delta: 3 }]
  }
  const teksLama = JSON.stringify(lama)
  fs.writeFileSync(berkas, teksLama)

  const a = new Antrean({ berkas, sekarang: () => 2000, buatId: () => 'dev-lama' })
  assert.equal(a.masalahPenyimpanan(), null, 'berkas lama sah, bukan rusak')
  assert.deepEqual(a.semua().map((p) => p.clientRef), ['co-1', 'pg-1', 'sm-1', 'sb-1'])
  assert.deepEqual(a.semua().map((p) => p.deviceSeq), [4, 5, 6, 9])
  assert.deepEqual(a.perangkat(), { id: 'dev-lama', seqTerakhir: 9, syncBatchVersi: 0 })
  // Field lama tidak diubah selain deviceSeq (+ MENGIRIM → MENUNGGU).
  for (const asli of lama.pesan) {
    const kini = a.cari(asli.clientRef)
    assert.deepEqual({ ...kini, deviceSeq: undefined, status: undefined }, { ...asli, deviceSeq: undefined, status: undefined }, asli.clientRef)
  }
  assert.equal(a.cari('sb-1').status, STATUS.MENUNGGU)
  assert.equal(a.cari('pg-1').status, STATUS.TINJAU)
  assert.deepEqual(a.transaksiLokal('co-1').struk, struk)
  assert.deepEqual(a.deltaStokTertunda(), { P1: -1, P2: 3 })
  assert.deepEqual(a.ringkas('T1'), { menunggu: 2, tinjau: 1, total: 3 })
  assert.equal(a.cari('sm-1').hasil.nomor, 'SM/0007')

  // Tulis pertama sesudah pembaruan (klaim akun) → berkas versi 2 lengkap; generasi lama tetap di .bak.
  assert.equal(a.klaimTanpaPemilik('kasir@toko.test@tatreport.com'), 4)
  const isi = JSON.parse(fs.readFileSync(berkas, 'utf8'))
  assert.equal(isi.versi, 2)
  assert.deepEqual(isi.perangkat, { id: 'dev-lama', seqTerakhir: 9, syncBatchVersi: 0 })
  assert.deepEqual(isi.pesan.map((p) => [p.clientRef, p.deviceSeq, p.pemilik]), [
    ['co-1', 4, 'kasir@toko.test@tatreport.com'],
    ['pg-1', 5, 'kasir@toko.test@tatreport.com'],
    ['sm-1', 6, 'kasir@toko.test@tatreport.com'],
    ['sb-1', 9, 'kasir@toko.test@tatreport.com']
  ])
  assert.deepEqual(isi.transaksi, lama.transaksi)
  assert.deepEqual(isi.delta, lama.delta)
  assert.equal(fs.readFileSync(`${berkas}.bak`, 'utf8'), teksLama, 'berkas 0.9.40 asli tersimpan sebagai cadangan')

  // Buka ulang: id perangkat & nomor urut stabil, baris baru melanjutkan urut & deviceSeq.
  const b = new Antrean({ berkas, sekarang: () => 3000, buatId: () => 'dev-lain' })
  assert.equal(b.perangkat().id, 'dev-lama')
  assert.equal(b.semua().length, 4)
  const baru = b.antrekan({ clientRef: 'co-2', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {} })
  assert.equal(baru.urut, 10)
  assert.equal(baru.deviceSeq, 10)
  b.selesai('co-1', { nomor: 'POS/1', id: 'SRV1' })
  assert.equal(b.cari('co-1').hasil.nomorLokal, 'L-260924-0001', 'struk lokal berkas lama ikut hasil')
})

test('aturPerangkat: versi sinkron batch tersimpan untuk start dingin', () => {
  const berkas = path.join(dirSementara(), 'antrean.json')
  const a = new Antrean({ berkas, sekarang: () => 1, buatId: () => 'dev-x' })
  assert.equal(a.aturPerangkat({ syncBatchVersi: 2 }).syncBatchVersi, 2)
  assert.equal(new Antrean({ berkas, sekarang: () => 1 }).perangkat().syncBatchVersi, 2)
})

test('perbaruiBanyak: banyak baris dalam SATU tulis ke disk', () => {
  const a = memori()
  for (const r of ['a', 'b', 'c']) a.antrekan({ clientRef: r, jenis: 'CHECKOUT', path: '/x', body: {} })
  let tulis = 0
  const asli = a.simpan.bind(a)
  a.simpan = () => { tulis++; return asli() }
  const n = a.perbaruiBanyak([
    { clientRef: 'a', patch: { status: STATUS.MENGIRIM } },
    { clientRef: 'b', patch: { status: STATUS.MENGIRIM } },
    { clientRef: 'hilang', patch: { status: STATUS.MENGIRIM } },
    { clientRef: 'c', patch: { status: STATUS.MENGIRIM } }
  ])
  assert.equal(n, 3)
  assert.equal(tulis, 1)
  assert.deepEqual(a.semua().map((p) => p.status), ['MENGIRIM', 'MENGIRIM', 'MENGIRIM'])
})

test('pemilik: klaimTanpaPemilik mengklaim baris lama sekali; ringkas & transaksiTertunda memisahkan akun lain', () => {
  const a = memori()
  a.antrekan({ clientRef: 'lama', jenis: 'CHECKOUT', tokoId: 'T1', path: '/x', body: {} }, { transaksi: { tokoId: 'T1', nomorLokal: 'L-1', waktuKlien: '2026-09-24T10:00:00', struk: {} } })
  a.antrekan({ clientRef: 'lain', jenis: 'CHECKOUT', tokoId: 'T1', path: '/x', body: {}, pemilik: 'lain@toko.test' }, { transaksi: { tokoId: 'T1', nomorLokal: 'L-2', waktuKlien: '2026-09-24T10:01:00', struk: {} } })
  assert.equal(a.klaimTanpaPemilik('kasir@toko.test'), 1)
  assert.equal(a.klaimTanpaPemilik('kedua@toko.test'), 0, 'hanya baris tanpa pemilik')
  assert.equal(a.cari('lama').pemilik, 'kasir@toko.test')
  assert.deepEqual(a.ringkas('T1', 'kasir@toko.test'), { menunggu: 1, tinjau: 0, total: 1, milikLain: 1 })
  assert.deepEqual(a.ringkas('T1'), { menunggu: 2, tinjau: 0, total: 2 }, 'tanpa pemilik = semua baris (penjaga ganti server/keluar)')
  assert.deepEqual(a.transaksiTertunda('T1', 'kasir@toko.test').map((t) => t.nomorLokal), ['L-1'])
  assert.equal(a.transaksiTertunda('T1').length, 2)
})

test('kunciPemilik: email huruf kecil + host server; null bila salah satu tak ada', () => {
  assert.equal(kunciPemilik(' Kasir@Demo.Tuleh.id ', 'https://tatreport.com'), 'kasir@demo.tuleh.id@tatreport.com')
  assert.equal(kunciPemilik('k@t.id', 'https://erp.contoh.test:8443/'), 'k@t.id@erp.contoh.test:8443')
  assert.equal(kunciPemilik('', 'https://tatreport.com'), null)
  assert.equal(kunciPemilik('k@t.id', 'bukan url'), null)
  assert.equal(kunciPemilik(null, null), null)
})

test('waktuKlienZona: waktu lokal + offset zona perangkat, menunjuk instan yang sama', () => {
  const d = new Date(2026, 8, 24, 10, 15, 2, 635)
  const s = waktuKlienZona(d)
  assert.match(s, /^2026-09-24T10:15:02[+-]\d{2}:\d{2}$/)
  assert.equal(new Date(s).getTime(), new Date(2026, 8, 24, 10, 15, 2).getTime())
  assert.equal(waktuKlienZona(new Date('entah')), null)
})

test('refIndukLokal: hanya /transaksi/lokal:<ref>/… (ter-encode maupun tidak)', () => {
  assert.equal(refIndukLokal('/transaksi/lokal%3Aabc-1/refund'), 'abc-1')
  assert.equal(refIndukLokal('/transaksi/lokal:abc-1/batal'), 'abc-1')
  assert.equal(refIndukLokal('/transaksi/T1/batal'), null)
  assert.equal(refIndukLokal('/bills/lokal:x/settle'), null)
  assert.equal(refIndukLokal('/transaksi/checkout'), null)
  assert.equal(refIndukLokal(undefined), null)
})

test('batalkan berantai: turunan transaksi lokal ikut dibuang bersama struk & delta', () => {
  const a = memori()
  a.antrekan({ clientRef: 'induk', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {} }, { transaksi: { tokoId: 'T1', nomorLokal: 'L-9', struk: {} }, deltaStok: { P1: -2 } })
  a.antrekan({ clientRef: 'rf', jenis: 'REFUND', tokoId: 'T1', path: '/transaksi/lokal%3Ainduk/refund', body: {} })
  a.antrekan({ clientRef: 'lain', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {} })
  assert.equal(a.batalkan('induk'), 2)
  assert.deepEqual(a.semua().map((p) => p.clientRef), ['lain'])
  assert.equal(a.transaksiLokal('induk'), null)
  assert.deepEqual(a.deltaStokTertunda(), {})
})

test('selesai: nomor lokal ikut hasil; induk yang masih dirujuk anak aktif tidak dipangkas', () => {
  const a = memori()
  a.antrekan({ clientRef: 'induk', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {} }, { transaksi: { tokoId: 'T1', nomorLokal: 'L-3B9D-260924-0001', struk: {} } })
  a.antrekan({ clientRef: 'anak', jenis: 'REFUND', tokoId: 'T1', path: '/transaksi/lokal%3Ainduk/refund', body: {} })
  a.selesai('induk', { id: 'SRV1', nomor: 'POS/1', peringatan: ['SELISIH_STOK'] })
  assert.equal(a.cari('induk').hasil.nomorLokal, 'L-3B9D-260924-0001')
  assert.equal(a.cari('induk').terkirimPada, 1)
  assert.equal(a.transaksiLokal('induk'), null, 'struk lokal dibuang: Riwayat memakai baris server')
  for (let i = 0; i < MAKS_TERKIRIM + 5; i++) {
    a.antrekan({ clientRef: `x${i}`, jenis: 'PENGELUARAN', path: '/pengeluaran', body: {} })
    a.selesai(`x${i}`, { nomor: `N${i}` })
  }
  assert.ok(a.cari('induk'), 'induk tetap ada selama anak aktif merujuknya')
  assert.equal(a.cari('x0'), null, 'riwayat lain tetap dipangkas')
  assert.equal(a.selisihTerkini(0), 1)
  assert.equal(a.selisihTerkini(2), 0, 'di luar jendela waktu')
})

test('label jenis Fase 4', () => {
  assert.equal(labelJenis('REFUND'), 'Refund')
  assert.equal(labelJenis('BATAL'), 'Pembatalan')
  assert.equal(labelJenis('BILL_BAYAR'), 'Bayar bon')
  assert.equal(labelJenis('ORDER_TRANSISI'), 'Pesanan')
  assert.equal(labelJenis('ASING'), 'ASING')
})

// Temuan review Task 15 (kontroler): pemilik null = semua baris, waktu null = null, induk TERKIRIM tak memutus turunan.
test('pemilik null diperlakukan sama dengan tanpa pemilik (semua baris), bukan kunci bernama null', () => {
  const a = memori()
  a.antrekan({ clientRef: 'm1', jenis: 'CHECKOUT', tokoId: 'T', path: '/transaksi/checkout', body: {}, pemilik: 'a@x.test' })
  a.antrekan({ clientRef: 'm2', jenis: 'CHECKOUT', tokoId: 'T', path: '/transaksi/checkout', body: {} })
  const r = a.ringkas('T', null)
  assert.equal(r.menunggu, 2)
  assert.equal(r.milikLain, undefined)
  assert.equal(a.transaksiTertunda('T', null).length, a.transaksiTertunda('T').length)
})

test('waktuKlienZona(null) mengembalikan null, bukan tanggal 1970', () => {
  assert.equal(waktuKlienZona(null), null)
})

test('batalkan induk yang sudah TERKIRIM tidak menghapus turunan lokal yang masih sah', () => {
  const a = memori()
  a.antrekan({ clientRef: 'induk', jenis: 'CHECKOUT', tokoId: 'T', path: '/transaksi/checkout', body: {} })
  a.antrekan({ clientRef: 'anak', jenis: 'REFUND', tokoId: 'T', path: '/transaksi/lokal:induk/refund', body: {} })
  a.selesai('induk', {})
  a.batalkan('induk')
  assert.ok(a.pesan.some((p) => p.clientRef === 'anak'), 'turunan dari induk terkirim tetap ada')
})
