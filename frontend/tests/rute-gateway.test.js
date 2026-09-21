'use strict'

// Penjaga CI: SETIAP permintaan HTTP yang dibentuk aplikasi harus ada di allowlist gateway
// Go (backend/routes.go). Tanpa ini, rute yang lupa didaftarkan baru ketahuan di kasir:
// desktop mendapat 404 "Endpoint tidak dikenal" dari gateway (kasus PUT/DELETE /tables/{id}
// 2026-09-15) sementara Android — yang tak lewat gateway — tetap jalan.
//
// Sumber yang diperiksa:
//   1. semua kanal kontrak bersama (src/shared/kontrak-kanal.js), dibentuk dengan payload contoh;
//   2. panggilan langsung api.get/post/put/hapus/request/upload di src/main/*.js (+ lib/offline).

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const AKAR = path.join(__dirname, '..')
const kontrak = require('../src/shared/kontrak-kanal.js')

const API_PREFIX = '/api/pos/v1'

// Kanal/jalur yang sengaja TIDAK lewat gateway — wajib beralasan.
const DIKECUALIKAN = new Map([
  // (kosong) — tambahkan ['METODE /jalur', 'alasan'] bila memang ada jalur langsung ke server.
])

function ruteGateway() {
  const go = fs.readFileSync(path.join(AKAR, '../backend/routes.go'), 'utf8')
  const rute = []
  const re = /\{\s*method:\s*"([A-Z]+)",\s*pattern:\s*"([^"]+)"/g
  let m
  while ((m = re.exec(go)) !== null) rute.push({ metode: m[1], pola: m[2] })
  return rute
}

function cocok(rute, metode, jalur) {
  const seg = jalur.split('/')
  return rute.some((r) => {
    if (r.metode !== metode) return false
    const pola = (API_PREFIX + r.pola).split('/')
    if (pola.length !== seg.length) return false
    return pola.every((p, i) => (/^\{[^}]+\}$/.test(p) ? seg[i].length > 0 : p === seg[i]))
  })
}

// Payload contoh yang memenuhi validasi semua kanal kontrak.
const CONTOH = {
  id: 'X1', idProduk: 'P1', idUtama: 'B1', idGabung: 'B2', mejaId: 'M1', sesiId: 'S1',
  items: [{ idProduk: 'P1', harga: 1000, kuantitas: 1 }],
  tipePembayaran: 'TUNAI', dibayar: 1000, nama: 'Contoh', nomor: '1', type: 'MEJA', pax: 2,
  barcode: '899', hargaJual: 1000, tokoIds: ['T1'], jumlah: 1, keterangan: 'k', nominal: 1000,
  gudangId: 'G1', kasAwal: 0, kasAkhirFisik: 0, to: 'SELESAI', bulan: '2026-09',
  baris: [{ id: 'I1', kuantitas: 1 }], metode: 'TUNAI', alasan: 'Contoh alasan refund',
  tanggal: '2026-09-21', jamMulai: '07:00', jamSelesai: '08:00', pesertaId: 'PS1', idPelanggan: 'C1', status: 'HADIR',
  bytes: new Uint8Array([1]), filename: 'a.png', mime: 'image/png'
}

function permintaanKontrak() {
  const out = []
  for (const kanal of Object.keys(kontrak.KANAL)) {
    const minta = kontrak.bentuk(kanal, CONTOH, { tokoAktif: 'T1', versiApp: '0.0.0', platform: 'desktop' })
    const metode = minta.metode === 'UPLOAD' ? 'POST' : minta.metode
    out.push({ asal: `kontrak ${kanal}`, metode, jalur: API_PREFIX + minta.jalur })
  }
  return out
}

function daftarJs(dir) {
  const out = []
  for (const nama of fs.readdirSync(dir)) {
    const p = path.join(dir, nama)
    if (fs.statSync(p).isDirectory()) out.push(...daftarJs(p))
    else if (p.endsWith('.js')) out.push(p)
  }
  return out
}

function permintaanLangsung() {
  const out = []
  const metodeDari = { get: 'GET', post: 'POST', put: 'PUT', hapus: 'DELETE', upload: 'POST' }
  for (const file of daftarJs(path.join(AKAR, 'src/main'))) {
    if (file.endsWith('demo.js') || file.endsWith('demo-data.js')) continue // simulasi lokal, tanpa HTTP
    const kode = fs.readFileSync(file, 'utf8')
    const rel = path.relative(AKAR, file)
    // api.get('/x') / klien.post(`/x/${id}`) / api.upload('/x')
    const re1 = /\b(?:api|klien)\.(get|post|put|hapus|upload)\(\s*(['`])(\/[^'`]*)\2/g
    // request('POST', '/x') / klien.request('GET', `/x/${id}`)
    const re2 = /\brequest\(\s*'([A-Z]+)'\s*,\s*(['`])(\/[^'`]*)\2/g
    let m
    while ((m = re1.exec(kode)) !== null) out.push({ asal: rel, metode: metodeDari[m[1]], jalur: API_PREFIX + m[3].replace(/\$\{[^}]+\}/g, 'X1') })
    while ((m = re2.exec(kode)) !== null) out.push({ asal: rel, metode: m[1], jalur: API_PREFIX + m[3].replace(/\$\{[^}]+\}/g, 'X1') })
    // buildUrl('/app/versi', …) untuk permintaan manual (waktuServer)
    const re3 = /buildUrl\(\s*'(\/[^']*)'/g
    while ((m = re3.exec(kode)) !== null) out.push({ asal: rel, metode: 'GET', jalur: API_PREFIX + m[1] })
  }
  return out
}

test('tabel rute gateway terbaca (sanity)', () => {
  const rute = ruteGateway()
  assert.ok(rute.length > 50, `rute terbaca ${rute.length}`)
  assert.ok(cocok(rute, 'PUT', '/api/pos/v1/tables/M1'), 'PUT /tables/{id} wajib ada')
  assert.ok(cocok(rute, 'DELETE', '/api/pos/v1/tables/M1'), 'DELETE /tables/{id} wajib ada')
  assert.ok(cocok(rute, 'POST', '/api/pos/v1/diagnostik'), 'POST /diagnostik wajib ada')
  assert.ok(!cocok(rute, 'PATCH', '/api/pos/v1/tables/M1'))
})

test('setiap kanal kontrak bersama punya rute di gateway Go', () => {
  const rute = ruteGateway()
  const hilang = permintaanKontrak()
    .filter((p) => !DIKECUALIKAN.has(`${p.metode} ${p.jalur}`) && !cocok(rute, p.metode, p.jalur))
    .map((p) => `${p.asal}: ${p.metode} ${p.jalur}`)
  assert.deepEqual(hilang, [], 'tambahkan ke backend/routes.go')
})

test('setiap panggilan HTTP langsung di proses utama punya rute di gateway Go', () => {
  const rute = ruteGateway()
  const semua = permintaanLangsung()
  assert.ok(semua.length >= 8, `panggilan langsung terdeteksi: ${semua.length}`)
  const hilang = semua
    .filter((p) => !DIKECUALIKAN.has(`${p.metode} ${p.jalur}`) && !cocok(rute, p.metode, p.jalur))
    .map((p) => `${p.asal}: ${p.metode} ${p.jalur}`)
  assert.deepEqual(hilang, [], 'tambahkan ke backend/routes.go')
})
