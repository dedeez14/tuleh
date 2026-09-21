'use strict'

// Logika layar Jadwal (desktop & Android Capacitor memakai renderer yang sama):
// navigasi hari, label kuota, dan validasi formulir slot sebelum menyentuh server.

const test = require('node:test')
const assert = require('node:assert/strict')

let J
test.before(async () => { J = await import('../src/renderer/js/lib/jadwal-model.js') })

test('geserTanggal melintasi batas bulan & tahun tanpa zona waktu', () => {
  assert.equal(J.geserTanggal('2026-09-21', 1), '2026-09-22')
  assert.equal(J.geserTanggal('2026-09-30', 1), '2026-10-01')
  assert.equal(J.geserTanggal('2026-01-01', -1), '2025-12-31')
  assert.equal(J.geserTanggal('2026-09-21', 0), '2026-09-21')
})

test('labelTanggal: nama hari Indonesia; hari ini/besok/kemarin ditandai', () => {
  assert.equal(J.labelTanggal('2026-09-21', '2026-09-21'), 'Hari ini · Senin, 21 Sep 2026')
  assert.equal(J.labelTanggal('2026-09-22', '2026-09-21'), 'Besok · Selasa, 22 Sep 2026')
  assert.equal(J.labelTanggal('2026-09-20', '2026-09-21'), 'Kemarin · Minggu, 20 Sep 2026')
  assert.equal(J.labelTanggal('2026-09-25', '2026-09-21'), 'Jumat, 25 Sep 2026')
})

test('labelKuota & slotPenuh: kuota kosong = tanpa batas', () => {
  assert.equal(J.labelKuota({ peserta_count: 3, kuota: 12, sisa_kuota: 9 }), '3 / 12 peserta')
  assert.equal(J.labelKuota({ peserta_count: 12, kuota: 12, sisa_kuota: 0 }), '12 / 12 peserta · penuh')
  assert.equal(J.labelKuota({ peserta_count: 3, kuota: null, sisa_kuota: null }), '3 peserta · tanpa batas')
  assert.equal(J.slotPenuh({ kuota: 12, sisa_kuota: 0 }), true)
  assert.equal(J.slotPenuh({ kuota: 12, sisa_kuota: 1 }), false)
  assert.equal(J.slotPenuh({ kuota: null, sisa_kuota: null }), false)
})

test('urutSlot: jam mulai lalu nama; slot batal turun ke bawah', () => {
  const rows = [
    { nama: 'Zumba', jam_mulai: '17:00', status: 'AKTIF' },
    { nama: 'Yoga', jam_mulai: '07:00', status: 'BATAL' },
    { nama: 'Angkat Beban', jam_mulai: '07:00', status: 'AKTIF' },
    { nama: 'Aerobik', jam_mulai: '07:00', status: 'AKTIF' }
  ]
  assert.deepEqual(J.urutSlot(rows).map((r) => r.nama), ['Aerobik', 'Angkat Beban', 'Zumba', 'Yoga'])
})

test('susunSlot: payload kanal jadwal:simpan; validasi berpesan Indonesia', () => {
  assert.deepEqual(
    J.susunSlot({ nama: '  Yoga Pagi ', tanggal: '2026-09-21', jamMulai: '07:00', jamSelesai: '08:00', kuota: '12', pengajar: ' Sari ', catatan: '' }),
    { nama: 'Yoga Pagi', tanggal: '2026-09-21', jamMulai: '07:00', jamSelesai: '08:00', kuota: 12, pengajar: 'Sari', catatan: '' }
  )
  assert.equal(J.susunSlot({ nama: 'Yoga', tanggal: '2026-09-21', jamMulai: '07:00', kuota: '' }).kuota, null)
  assert.throws(() => J.susunSlot({ tanggal: '2026-09-21', jamMulai: '07:00' }), /Nama jadwal/)
  assert.throws(() => J.susunSlot({ nama: 'Yoga', jamMulai: '07:00' }), /Tanggal/)
  assert.throws(() => J.susunSlot({ nama: 'Yoga', tanggal: '2026-09-21' }), /Jam mulai/)
  assert.throws(() => J.susunSlot({ nama: 'Yoga', tanggal: '2026-09-21', jamMulai: '09:00', jamSelesai: '08:00' }), /setelah jam mulai/)
  assert.throws(() => J.susunSlot({ nama: 'Yoga', tanggal: '2026-09-21', jamMulai: '07:00', kuota: '0' }), /minimal 1/)
})
