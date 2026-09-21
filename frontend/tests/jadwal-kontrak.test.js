'use strict'

// Kontrak kanal modul Jadwal (server 2026-09-21, app 0.9.39): slot kelas/janji temu per hari
// dan pesertanya. Satu kontrak dipakai desktop (ipc.js) & Android Capacitor (mobile-bridge.js).

const test = require('node:test')
const assert = require('node:assert/strict')
const kontrak = require('../src/shared/kontrak-kanal.js')

const polos = (v) => JSON.parse(JSON.stringify(v))

test('jadwal:list → GET /jadwal dengan tanggal; semua=1 hanya bila diminta', () => {
  assert.deepEqual(kontrak.bentuk('jadwal:list', { tanggal: '2026-09-21' }), {
    metode: 'GET', jalur: '/jadwal', query: { tanggal: '2026-09-21', semua: undefined }
  })
  assert.equal(kontrak.bentuk('jadwal:list', { tanggal: '2026-09-21', semua: true }).query.semua, 1)
})

test('jadwal:simpan & jadwal:ubah mengirim bentuk server (snake_case, jam HH:MM)', () => {
  const isi = { nama: 'Yoga Pagi', tanggal: '2026-09-21', jamMulai: '07:00', jamSelesai: '08:00', kuota: 12, pengajar: 'Sari', catatan: 'Studio B' }
  const baru = kontrak.bentuk('jadwal:simpan', isi)
  assert.equal(baru.metode, 'POST')
  assert.equal(baru.jalur, '/jadwal')
  assert.deepEqual(polos(baru.body), {
    nama: 'Yoga Pagi', tanggal: '2026-09-21', jam_mulai: '07:00', jam_selesai: '08:00', kuota: 12, pengajar: 'Sari', catatan: 'Studio B'
  })
  const ubah = kontrak.bentuk('jadwal:ubah', { id: 'J1', ...isi, jamSelesai: '', kuota: '' })
  assert.equal(ubah.metode, 'PUT')
  assert.equal(ubah.jalur, '/jadwal/J1')
  // Kosong dikirim null, bukan dibuang: PUT mengganti penuh (hapus jam selesai / kuota).
  assert.equal(ubah.body.jam_selesai, null)
  assert.equal(ubah.body.kuota, null)
})

test('jadwal:simpan menolak isian tak lengkap sebelum menyentuh jaringan', () => {
  assert.throws(() => kontrak.bentuk('jadwal:simpan', { tanggal: '2026-09-21', jamMulai: '07:00' }), /wajib/)
  assert.throws(() => kontrak.bentuk('jadwal:simpan', { nama: 'Yoga', jamMulai: '07:00' }), /wajib/)
  assert.throws(() => kontrak.bentuk('jadwal:simpan', { nama: 'Yoga', tanggal: '2026-09-21' }), /wajib/)
})

test('peserta: tambah/ubah status/lepas memakai jalur bersarang', () => {
  const tambah = kontrak.bentuk('jadwal:pesertaTambah', { id: 'J1', idPelanggan: 'C9' })
  assert.equal(tambah.metode, 'POST')
  assert.equal(tambah.jalur, '/jadwal/J1/peserta')
  assert.deepEqual(polos(tambah.body), { pelanggan_id: 'C9' })
  const status = kontrak.bentuk('jadwal:pesertaStatus', { id: 'J1', pesertaId: 'P2', status: 'HADIR' })
  assert.equal(status.metode, 'PATCH')
  assert.equal(status.jalur, '/jadwal/J1/peserta/P2')
  assert.deepEqual(polos(status.body), { status: 'HADIR' })
  assert.deepEqual(kontrak.bentuk('jadwal:pesertaHapus', { id: 'J1', pesertaId: 'P2' }), { metode: 'DELETE', jalur: '/jadwal/J1/peserta/P2' })
  assert.throws(() => kontrak.bentuk('jadwal:pesertaTambah', { id: 'J1' }), /wajib/)
})

test('permukaan preload desktop memuat seluruh metode jadwal (paritas dengan jembatan Android)', () => {
  const fs = require('node:fs')
  const path = require('node:path')
  const preload = fs.readFileSync(path.join(__dirname, '../src/preload/preload.js'), 'utf8')
  for (const kanal of ['jadwal:list', 'jadwal:detail', 'jadwal:simpan', 'jadwal:ubah', 'jadwal:batal', 'jadwal:pesertaTambah', 'jadwal:pesertaStatus', 'jadwal:pesertaHapus']) {
    assert.match(preload, new RegExp(`invoke\\('${kanal}'\\)`), `preload tanpa ${kanal}`)
  }
})
