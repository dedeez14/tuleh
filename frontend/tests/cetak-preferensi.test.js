'use strict'

// Regresi audit 8 Sep 2026: preferensi "cetak langsung tanpa dialog" pernah
// berlaku untuk SEMUA panggilan cetak — termasuk ekspor PDF laporan keuangan
// dan cetak QR meja, sehingga laporan diam-diam keluar di printer thermal dan
// tidak pernah menjadi berkas PDF. Sekarang hanya dokumen yang menandai diri
// sebagai struk yang boleh dicetak senyap.
//
// Menguji fungsi keputusan yang sama dengan handler app:print di ipc.js.

const test = require('node:test')
const assert = require('node:assert/strict')

/** Salinan aturan di src/main/ipc.js (app:print). */
function putuskan({ paksaDialog, struk, printerSekaliPakai, langsungSekaliPakai }, pref) {
  const uji = printerSekaliPakai !== undefined || langsungSekaliPakai !== undefined
  const printer = uji ? String(printerSekaliPakai || '') : pref.printer
  const maunyaLangsung = uji ? !!langsungSekaliPakai : pref.langsung
  const langsung = !paksaDialog && (struk === true || uji) && maunyaLangsung && !!printer
  return { langsung, printer: langsung ? printer : null }
}

const prefAktif = { printer: 'RPP02 Thermal', langsung: true, otomatis: true }

test('struk kasir dicetak langsung ke printer pilihan', () => {
  const r = putuskan({ struk: true }, prefAktif)
  assert.equal(r.langsung, true)
  assert.equal(r.printer, 'RPP02 Thermal')
})

test('PDF laporan & QR meja TIDAK ikut cetak langsung', () => {
  // Pemanggil tanpa penanda struk: keuangan.js (PDF) dan receipt.js (QR meja).
  assert.equal(putuskan({}, prefAktif).langsung, false)
  assert.equal(putuskan({ struk: false }, prefAktif).langsung, false)
})

test('"Cetak lewat dialog" mengalahkan preferensi', () => {
  assert.equal(putuskan({ struk: true, paksaDialog: true }, prefAktif).langsung, false)
})

test('preferensi mati atau printer kosong tetap lewat dialog', () => {
  assert.equal(putuskan({ struk: true }, { printer: 'RPP02', langsung: false }).langsung, false)
  assert.equal(putuskan({ struk: true }, { printer: '', langsung: true }).langsung, false)
})

test('uji cetak memakai setelan sekali pakai tanpa menyentuh preferensi', () => {
  const prefMati = { printer: '', langsung: false, otomatis: false }
  const r = putuskan({ printerSekaliPakai: 'EPSON TM-T82', langsungSekaliPakai: true }, prefMati)
  assert.equal(r.langsung, true)
  assert.equal(r.printer, 'EPSON TM-T82')
  // Preferensi tersimpan tidak berubah — itu tugas tombol Simpan.
  assert.deepEqual(prefMati, { printer: '', langsung: false, otomatis: false })
})

test('uji cetak tanpa printer terpilih jatuh ke dialog', () => {
  const r = putuskan({ printerSekaliPakai: '', langsungSekaliPakai: true }, prefAktif)
  assert.equal(r.langsung, false)
})
