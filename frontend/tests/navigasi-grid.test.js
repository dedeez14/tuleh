'use strict'

// Navigasi katalog kasir dengan keyboard (panah/Home/End) — roving focus.

const test = require('node:test')
const assert = require('node:assert/strict')

let g
test.before(async () => { g = await import('../src/renderer/js/utils/navigasi-grid.js') })

const kartu = (top) => ({ getBoundingClientRect: () => ({ top }) })

test('hitungKolom: banyaknya kartu sebaris dengan kartu pertama', () => {
  assert.equal(g.hitungKolom([kartu(0), kartu(0), kartu(0), kartu(120), kartu(120)]), 3)
  assert.equal(g.hitungKolom([kartu(0)]), 1)
  assert.equal(g.hitungKolom([]), 1)
})

test('panah kanan/kiri berhenti di ujung; atas/bawah tetap di kolom', () => {
  // 8 kartu, 3 kolom:  0 1 2 / 3 4 5 / 6 7
  assert.equal(g.indeksTujuan('ArrowRight', 2, 8, 3), 3, 'kanan di ujung baris → kartu berikutnya')
  assert.equal(g.indeksTujuan('ArrowRight', 7, 8, 3), 7, 'kartu terakhir tetap')
  assert.equal(g.indeksTujuan('ArrowLeft', 0, 8, 3), 0)
  assert.equal(g.indeksTujuan('ArrowDown', 1, 8, 3), 4)
  assert.equal(g.indeksTujuan('ArrowDown', 5, 8, 3), 7, 'baris terakhir pendek → dijepit ke kartu terakhir')
  assert.equal(g.indeksTujuan('ArrowDown', 7, 8, 3), 7)
  assert.equal(g.indeksTujuan('ArrowUp', 4, 8, 3), 1)
  assert.equal(g.indeksTujuan('ArrowUp', 1, 8, 3), 1, 'baris pertama tetap')
  assert.equal(g.indeksTujuan('Home', 5, 8, 3), 0)
  assert.equal(g.indeksTujuan('End', 0, 8, 3), 7)
  assert.equal(g.indeksTujuan('Enter', 0, 8, 3), -1, 'bukan tombol navigasi')
  assert.equal(g.indeksTujuan('ArrowDown', 0, 0, 3), -1, 'grid kosong')
})

test('karakterCetak: huruf/angka tanpa modifier saja', () => {
  assert.equal(g.karakterCetak({ key: 'a' }), true)
  assert.equal(g.karakterCetak({ key: '7' }), true)
  assert.equal(g.karakterCetak({ key: 'a', ctrlKey: true }), false)
  assert.equal(g.karakterCetak({ key: 'Enter' }), false)
  assert.equal(g.karakterCetak({ key: 'F4' }), false)
})
