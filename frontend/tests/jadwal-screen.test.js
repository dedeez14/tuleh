'use strict'

// Gerbang tulis layar Jadwal (gym/klinik) — gagal-tertutup.
//
// Menata slot & peserta butuh `jadwal.kelola` dari server; pemegang `jadwal.lihat` saja
// (mis. peran kasir bawaan) hanya boleh MEMBACA. Yang diuji: tanpa `jadwal.kelola` tidak ada
// satu pun kontrol tulis yang IKUT DIRENDER — bukan sekadar disembunyikan CSS atau dimatikan
// `disabled`, yang masih bisa dihidupkan lagi dari devtools.
//
// Layar utuh (screens/jadwal.js) butuh DOM sungguhan + jembatan iposAPI, jadi potongan render
// yang digerbang sudah dipisah apa adanya ke lib/jadwal-tampilan.js dan itulah yang dirender
// di sini — sumber HTML yang sama persis yang dipakai layarnya.

const test = require('node:test')
const assert = require('node:assert/strict')

let J
let bisa

test.before(async () => {
  // lib/jadwal-tampilan.js → components/ui.js mendaftarkan listener keydown di document saat dimuat.
  global.document = { addEventListener() {} }
  J = await import('../src/renderer/js/lib/jadwal-tampilan.js')
  ;({ bisa } = await import('../src/renderer/js/akses.js'))
})

const PESERTA = [
  { id: 'P1', nama: 'Rina', telepon: '0811', status: 'TERDAFTAR' },
  { id: 'P2', nama: 'Bagas', telepon: '', status: 'HADIR' }
]

// `jadwal.lihat` saja = argumen kelola false (screens/jadwal.js: `bisa('jadwal.kelola')`).
const AKSES_LIHAT = ['jadwal.lihat']
const AKSES_KELOLA = ['jadwal.lihat', 'jadwal.kelola']
// Gerbangnya harus resolver yang SAMA dengan layar (akses.js), bukan tiruan lokal — kalau tidak,
// mengubah layar menjadi `const kelola = true` tak akan membuat satu tes pun merah.
const kelolaDari = (akses) => bisa('jadwal.kelola', { akses })

test('hanya jadwal.lihat: tidak ada tombol "Tambah Jadwal" di kepala halaman', () => {
  const html = J.kepalaJadwalHTML(kelolaDari(AKSES_LIHAT))
  assert.doesNotMatch(html, /jdw-add/, 'tombol tambah tidak dirender')
  assert.doesNotMatch(html, /<button/, 'tak ada tombol apa pun di kepala halaman')
  assert.match(html, /page-head__title">Jadwal/, 'judul tetap tampil — layarnya boleh dibaca')
})

test('dengan jadwal.kelola: tombol "Tambah Jadwal" muncul', () => {
  const html = J.kepalaJadwalHTML(kelolaDari(AKSES_KELOLA))
  assert.match(html, /id="jdw-add"/)
  assert.match(html, /Tambah Jadwal/)
})

test('hanya jadwal.lihat: peserta baca-saja — tanpa <select> status & tanpa tombol lepas', () => {
  const html = J.pesertaTabelHTML(PESERTA, kelolaDari(AKSES_LIHAT))
  assert.doesNotMatch(html, /<select/, 'status tidak bisa diubah')
  assert.doesNotMatch(html, /data-status/)
  assert.doesNotMatch(html, /data-lepas/, 'tidak ada tombol lepas peserta')
  assert.doesNotMatch(html, /<button/, 'tak ada tombol tulis di baris peserta')
  // Tetap terbaca: nama & status muncul sebagai lencana.
  assert.match(html, /Rina/)
  assert.match(html, /Bagas/)
  assert.match(html, /<span class="badge">TERDAFTAR<\/span>/)
})

test('dengan jadwal.kelola: <select> status + tombol lepas per peserta', () => {
  const html = J.pesertaTabelHTML(PESERTA, kelolaDari(AKSES_KELOLA))
  assert.equal(html.match(/<select class="select" data-status>/g).length, 2, 'satu select per peserta')
  assert.equal(html.match(/data-lepas/g).length, 2, 'satu tombol lepas per peserta')
  assert.match(html, /<option value="HADIR" selected>/, 'status tersimpan terpilih')
  assert.deepEqual(J.STATUS_PESERTA.map((x) => x.id), ['TERDAFTAR', 'HADIR', 'BATAL'])
})

test('peserta kosong: tidak ada kontrol tulis pada peran mana pun', () => {
  for (const akses of [AKSES_LIHAT, AKSES_KELOLA]) {
    for (const isi of [[], null, undefined]) {
      const html = J.pesertaTabelHTML(isi, kelolaDari(akses))
      assert.match(html, /Belum ada peserta terdaftar/)
      assert.doesNotMatch(html, /<select|<button/)
    }
  }
})

test('hanya jadwal.lihat: kaki modal detail tanpa satu pun tombol tulis', () => {
  assert.deepEqual(J.aksiDetailJadwal(kelolaDari(AKSES_LIHAT)), [], 'tak ada batal/ubah/daftarkan peserta')
})

test('dengan jadwal.kelola: batal, ubah, dan daftarkan peserta — pada urutan tampil', () => {
  const aksi = J.aksiDetailJadwal(kelolaDari(AKSES_KELOLA))
  assert.deepEqual(aksi.map((a) => a.kunci), ['batal', 'ubah', 'daftar'])
  assert.deepEqual(aksi.map((a) => a.label), ['Batalkan jadwal', 'Ubah jadwal', 'Daftarkan peserta'])
  // Deskriptor disalin — pemanggil tak bisa mencemari daftar bersama untuk render berikutnya.
  aksi[0].label = 'diubah'
  assert.equal(J.aksiDetailJadwal(true)[0].label, 'Batalkan jadwal')
})

test('argumen kelola non-boolean tetap gagal-tertutup', () => {
  for (const nilai of [undefined, null, 0, '', NaN]) {
    assert.doesNotMatch(J.kepalaJadwalHTML(nilai), /jdw-add/, String(nilai))
    assert.doesNotMatch(J.pesertaTabelHTML(PESERTA, nilai), /<select|data-lepas/, String(nilai))
    assert.deepEqual(J.aksiDetailJadwal(nilai), [], String(nilai))
  }
})

// Penjaga refactor: layar HARUS memakai potongan yang digerbang ini, bukan menyusun
// ulang kontrol tulisnya sendiri (kalau tidak, test di atas berhenti menjaga apa pun).
test('screens/jadwal.js merender lewat lib/jadwal-tampilan.js', () => {
  const fs = require('node:fs')
  const path = require('node:path')
  const src = fs.readFileSync(path.join(__dirname, '../src/renderer/js/screens/jadwal.js'), 'utf8')
  assert.match(src, /from '\.\.\/lib\/jadwal-tampilan\.js'/)
  // Sumber `kelola` dipaku ke resolver hak akses: tanpa ini, gerbang bisa dilepas diam-diam.
  assert.match(src, /const kelola = bisa\('jadwal\.kelola'\)/)
  for (const fn of ['kepalaJadwalHTML(kelola)', 'pesertaTabelHTML(s.peserta, kelola)', 'aksiDetailJadwal(kelola)']) {
    assert.ok(src.includes(fn), `layar memanggil ${fn}`)
  }
  // Layar boleh MENDENGARKAN penandanya (delegasi event `[data-status]`, `#jdw-add`),
  // tapi tidak boleh MERENDER kontrol tulisnya sendiri di luar gerbang.
  for (const bentukRender of ['id="jdw-add"', '<select', '<option', 'data-lepas title']) {
    assert.ok(!src.includes(bentukRender), `kontrol tulis dirender langsung di layar: ${bentukRender}`)
  }
})
