'use strict'

// Aturan proses utama untuk kanal tulis ber-antrean (Fase 4): daftar kanal dari kontrak, refund/batal atas
// transaksi lokal (pemilik, induk ditinjau, satu tindakan tertunda, induk sudah terkirim → id server),
// penjaga tutup sesi, baris tampilan panel tanpa token, dan simpul offline (mode batch dari /config).

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const kontrak = require('../src/shared/kontrak-kanal.js')
const { Antrean, STATUS } = require('../src/main/offline/antrean')
const { daftarKanalAntre, putuskanTulisAntre, pesanTahanTutupSesi, barisUntukTampilan, buatTutupSesi, buatAkunAktif } = require('../src/main/offline/kanal-antre')
const { SalinanBaca } = require('../src/main/offline/salinan')

const memori = () => new Antrean({ berkas: null, sekarang: () => 1, buatId: () => 'dev-uji' })
const K = 'kasir@toko.test'

function indukLokal(a, ref = 'c1', ekstra = {}) {
  return a.antrekan({ clientRef: ref, jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {}, pemilik: K, ...ekstra })
}

test('daftarKanalAntre: diturunkan dari field antrean kontrak (checkout ditangani khusus)', () => {
  assert.deepEqual(daftarKanalAntre(kontrak.KANAL).sort(), [
    'bill:bayar', 'inventory:stokMasuk', 'order:konfirmasiBayar', 'order:lunasi', 'order:transition', 'pengeluaran:create', 'trx:batal', 'trx:refund'
  ])
})

test('putuskanTulisAntre: jalur biasa lewat apa adanya (boleh dicoba online)', () => {
  const a = memori()
  assert.deepEqual(putuskanTulisAntre({ jenis: 'BILL_BAYAR', jalur: '/bills/B1/settle', body: { x: 1 }, antrean: a, pemilik: K }), { jalur: '/bills/B1/settle', body: { x: 1 }, langsungAntre: false })
})

test('putuskanTulisAntre: refund/batal transaksi lokal milik sendiri → langsung diantrekan', () => {
  const a = memori()
  indukLokal(a)
  const r = putuskanTulisAntre({ jenis: 'REFUND', jalur: '/transaksi/lokal%3Ac1/refund', body: { items: [{ baris: 0, kuantitas: 1 }] }, antrean: a, pemilik: K })
  assert.equal(r.langsungAntre, true)
  assert.equal(r.jalur, '/transaksi/lokal%3Ac1/refund')
})

test('putuskanTulisAntre: penolakan transaksi lokal — akun lain, induk ditinjau, tindakan tertunda, tak ada, jenis/grup salah', () => {
  const a = memori()
  indukLokal(a, 'lain', { pemilik: 'lain@toko.test' })
  assert.match(putuskanTulisAntre({ jenis: 'BATAL', jalur: '/transaksi/lokal%3Alain/batal', body: {}, antrean: a, pemilik: K }).tolak, /akun lain/)

  indukLokal(a, 'tinjau')
  a.perbarui('tinjau', { status: STATUS.TINJAU })
  assert.match(putuskanTulisAntre({ jenis: 'BATAL', jalur: '/transaksi/lokal%3Atinjau/batal', body: {}, antrean: a, pemilik: K }).tolak, /ditinjau/)

  indukLokal(a, 'c1')
  a.antrekan({ clientRef: 'rf', jenis: 'REFUND', tokoId: 'T1', path: '/transaksi/lokal%3Ac1/refund', body: {}, pemilik: K })
  assert.match(putuskanTulisAntre({ jenis: 'BATAL', jalur: '/transaksi/lokal%3Ac1/batal', body: {}, antrean: a, pemilik: K }).tolak, /refund yang menunggu/)
  assert.match(putuskanTulisAntre({ jenis: 'REFUND', jalur: '/transaksi/lokal%3Ac1/refund', body: {}, antrean: a, pemilik: K }).tolak, /refund yang menunggu/)

  // Lembar refund yang SAMA diulang (client_ref sama) bukan tindakan kedua → lewat (penulis antrean menjawab tertunda).
  assert.equal(putuskanTulisAntre({ jenis: 'REFUND', jalur: '/transaksi/lokal%3Ac1/refund', body: { client_ref: 'rf' }, antrean: a, pemilik: K }).langsungAntre, true)
  assert.match(putuskanTulisAntre({ jenis: 'REFUND', jalur: '/transaksi/lokal%3Ac1/refund', body: { client_ref: 'rf-lain' }, antrean: a, pemilik: K }).tolak, /refund yang menunggu/)

  assert.match(putuskanTulisAntre({ jenis: 'BATAL', jalur: '/transaksi/lokal%3Ahilang/batal', body: {}, antrean: a, pemilik: K }).tolak, /tidak ditemukan/)
  assert.match(putuskanTulisAntre({ jenis: 'BILL_BAYAR', jalur: '/bills/lokal%3Ab1/settle', body: {}, antrean: a, pemilik: K }).tolak, /belum tersinkron/)
})

test('putuskanTulisAntre: induk lokal sudah terkirim → rujukan diganti id server dan boleh dicoba online', () => {
  const a = memori()
  indukLokal(a)
  a.selesai('c1', { id: 'SRV1', nomor: 'POS/1', data: { items: [{ baris: 0, id: 'I-a' }] } })
  const r = putuskanTulisAntre({ jenis: 'REFUND', jalur: '/transaksi/lokal%3Ac1/refund', body: { items: [{ baris: 0, kuantitas: 1 }], metode: 'TUNAI' }, antrean: a, pemilik: K })
  assert.deepEqual(r, { jalur: '/transaksi/SRV1/refund', body: { items: [{ id: 'I-a', kuantitas: 1 }], metode: 'TUNAI' }, langsungAntre: false })
})

test('pesanTahanTutupSesi: hanya baris akun ini untuk toko itu (termasuk TINJAU); lainnya tidak menahan', () => {
  const a = memori()
  assert.equal(pesanTahanTutupSesi(a, { tokoId: 'T1', pemilik: K }), null)
  a.antrekan({ clientRef: 'lain', jenis: 'CHECKOUT', tokoId: 'T1', path: '/x', body: {}, pemilik: 'lain@toko.test' })
  a.antrekan({ clientRef: 't2', jenis: 'CHECKOUT', tokoId: 'T2', path: '/x', body: {}, pemilik: K })
  assert.equal(pesanTahanTutupSesi(a, { tokoId: 'T1', pemilik: K }), null)
  a.antrekan({ clientRef: 'milik', jenis: 'BILL_BAYAR', tokoId: 'T1', path: '/bills/B1/settle', body: {}, pemilik: K })
  a.perbarui('milik', { status: STATUS.TINJAU })
  assert.match(pesanTahanTutupSesi(a, { tokoId: 'T1', pemilik: K }), /^1 data belum terkirim/)
  a.selesai('milik', { nomor: 'x' })
  assert.equal(pesanTahanTutupSesi(a, { tokoId: 'T1', pemilik: K }), null)
})

test('barisUntukTampilan: token persetujuan tidak pernah sampai renderer; label jenis/kode/peringatan; milik akun lain', () => {
  const a = memori()
  const p = a.antrekan({ clientRef: 'b', jenis: 'BATAL', tokoId: 'T1', path: '/transaksi/T1/batal', body: { alasan: 'x', otorisasi_token: 'rahasia' }, pemilik: 'lain@toko.test' })
  a.perbarui('b', { status: STATUS.TINJAU, kode: 'OTORISASI_WAJIB' })
  const t = barisUntukTampilan(p, K)
  assert.equal('otorisasi_token' in t.body, false)
  assert.equal(p.body.otorisasi_token, 'rahasia', 'baris antrean tidak diubah')
  assert.equal(t.label, 'Pembatalan')
  assert.equal(t.labelKode, 'Butuh persetujuan atasan — ulangi saat online')
  assert.equal(t.milikLain, true)
  a.antrekan({ clientRef: 'c', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {}, pemilik: K })
  a.selesai('c', { nomor: 'POS/1', peringatan: ['SELISIH_STOK'] })
  const u = barisUntukTampilan(a.cari('c'), K)
  assert.deepEqual(u.labelPeringatan, ['Selisih stok'])
  assert.equal(u.labelKode, null)
  assert.equal(u.milikLain, false)
})

// Direktori sementara dihapus setelah tes selesai.
function dirSementara(t, awalan) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), awalan))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  return dir
}

test('simpul offline: /config sync_batch mengaktifkan mode batch & tersimpan untuk start dingin; status memuat modeBatch & milikLain', (t) => {
  const offline = require('../src/main/offline')
  const dir = dirSementara(t, 'tuleh-simpul-')
  const kirim = async () => ({ ok: true })
  offline.init({ dir, kirim, kirimBatch: async () => ({ ok: true }), pemilikAktif: () => K })
  assert.equal(offline.status().modeBatch, false)
  assert.deepEqual(offline.aturSyncBatch({ sync_batch: { versi: 2, maks_operasi: 200, maks_byte: 2097152 } }), { versi: 2, maksOperasi: 200, maksByte: 2097152 })
  assert.equal(offline.status().modeBatch, true)
  offline.antrean.antrekan({ clientRef: 'x', jenis: 'CHECKOUT', tokoId: 'T1', path: '/x', body: {}, pemilik: 'lain@toko.test' })
  assert.equal(offline.status('T1', K).milikLain, 1)
  assert.equal(offline.status('T1', K).menunggu, 0)
  assert.equal(offline.status('T1', K).selisihTerkini, 0)

  offline.init({ dir, kirim, kirimBatch: async () => ({ ok: true }) })
  assert.equal(offline.status().modeBatch, true, 'start dingin tanpa /config')
  offline.aturSyncBatch({ nama: 'server lama' })
  assert.equal(offline.status().modeBatch, false)
})

test('simpul offline: setiap /config memanggil aturSyncBatch → mode batch yang dimatikan 404/503 pulih (paritas memo 5 menit Flutter)', (t) => {
  const offline = require('../src/main/offline')
  const dir = dirSementara(t, 'tuleh-simpul-mati-')
  offline.init({ dir, kirim: async () => ({ ok: true }), kirimBatch: async () => ({ ok: true }), pemilikAktif: () => K })
  offline.aturSyncBatch({ sync_batch: { versi: 2 } })
  assert.equal(offline.status().modeBatch, true)
  // Server menjawab 404 (rute batch belum ada di koneksi ini) → per baris sampai /config berikutnya.
  offline.pengurai._olahJawabanBatch([], { ok: false, status: 404 })
  assert.equal(offline.status().modeBatch, false)
  offline.aturSyncBatch({ sync_batch: { versi: 2 } })
  assert.equal(offline.status().modeBatch, true, '/config berikutnya mengaktifkan lagi')
})

test('sesi:tutup: sesi sendiri ditahan 409 ANTREAN selama antrean akun ini untuk toko aktif belum kosong; sesiLain melewati', async () => {
  const a = memori()
  const dikirim = []
  const tutup = buatTutupSesi({ antrean: a, tokoAktif: () => 'T1', pemilik: () => K, kirim: async (p) => { dikirim.push(p); return { ok: true, status: 200, data: { id: p.id } } } })
  assert.equal((await tutup({ id: 'S1' })).ok, true, 'antrean kosong → diteruskan')
  a.antrekan({ clientRef: 'c', jenis: 'CHECKOUT', tokoId: 'T1', path: '/transaksi/checkout', body: {}, pemilik: K })
  const r = await tutup({ id: 'S1' })
  assert.deepEqual([r.ok, r.status, r.code, r.errors], [false, 409, 'ANTREAN', null])
  assert.match(r.message, /^1 data belum terkirim/)
  assert.equal(dikirim.length, 1, 'tidak diteruskan ke server')
  assert.equal((await tutup({ id: 'S2', sesiLain: true })).ok, true, 'sesi kasir lain tidak ditahan')
  assert.equal(dikirim.length, 2)
  // Baris akun lain / toko lain tidak menahan.
  const b = memori()
  b.antrekan({ clientRef: 'l', jenis: 'CHECKOUT', tokoId: 'T1', path: '/x', body: {}, pemilik: 'lain@toko.test' })
  b.antrekan({ clientRef: 't2', jenis: 'CHECKOUT', tokoId: 'T2', path: '/x', body: {}, pemilik: K })
  const tutupB = buatTutupSesi({ antrean: b, tokoAktif: () => 'T1', pemilik: () => K, kirim: async () => ({ ok: true }) })
  assert.equal((await tutupB({ id: 'S1' })).ok, true)
  // Payload kosong tidak meledak.
  assert.equal((await buatTutupSesi({ antrean: a, tokoAktif: () => 'T1', pemilik: () => K, kirim: async () => ({ ok: true }) })()).status, 409)
})

test('akun aktif: salinan /auth/me saat start & login mengklaim baris tanpa pemilik; keluar melupakan akun', () => {
  const a = memori()
  a.antrekan({ clientRef: 'lama', jenis: 'CHECKOUT', tokoId: 'T1', path: '/x', body: {} })
  let siar = 0
  const akun = buatAkunAktif({ antrean: () => a, baseUrl: () => 'https://toko.contoh.test', setelahKlaim: () => { siar++ } })
  assert.equal(akun.pemilikAktif(), null)
  assert.equal(akun.pemilikStatus(), undefined, 'akun belum diketahui → semua baris untuk hitungan')

  // Start: identitas dari salinan /auth/me (disimpan saat masuk).
  const salinan = new SalinanBaca({ berkas: null })
  salinan.simpan(null, '/auth/me', {}, { data: { user: { email: ' Kasir@Toko.Test ' } }, meta: null })
  akun.dariSalinan(salinan)
  assert.equal(akun.pemilikAktif(), 'kasir@toko.test@toko.contoh.test')
  assert.equal(a.cari('lama').pemilik, 'kasir@toko.test@toko.contoh.test')
  assert.equal(siar, 1)

  // Login akun lain: baris yang sudah berpemilik tidak diklaim ulang; baris baru tanpa pemilik diklaim.
  a.antrekan({ clientRef: 'baru', jenis: 'CHECKOUT', tokoId: 'T1', path: '/x', body: {} })
  akun.atur('owner@toko.test')
  assert.equal(a.cari('lama').pemilik, 'kasir@toko.test@toko.contoh.test')
  assert.equal(a.cari('baru').pemilik, 'owner@toko.test@toko.contoh.test')
  assert.equal(siar, 2)
  akun.atur('owner@toko.test')
  assert.equal(siar, 2, 'tanpa klaim → tanpa siaran')
  akun.atur('')
  assert.equal(akun.pemilikAktif(), 'owner@toko.test@toko.contoh.test', 'email kosong diabaikan')

  akun.lupakan()
  assert.equal(akun.pemilikAktif(), null, 'keluar → akun dilupakan')
  // Salinan rusak / kosong tidak melempar.
  akun.dariSalinan({ ambil: () => { throw new Error('rusak') } })
  akun.dariSalinan(null)
  assert.equal(akun.pemilikAktif(), null)
})
