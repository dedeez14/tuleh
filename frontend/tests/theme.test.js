'use strict'

// Unit test manajemen tema (Option B: light/dark/system).
// theme.js membaca localStorage/matchMedia/document — semua di-mock di sini
// SEBELUM import dinamis (modul memanggil applyTheme() saat dimuat).

const test = require('node:test')
const assert = require('node:assert/strict')

let theme
const store = {}
const attrs = {}
let mediaMatches = false

test.before(async () => {
  global.localStorage = {
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v) },
    removeItem: (k) => { delete store[k] }
  }
  global.document = {
    documentElement: {
      setAttribute: (k, v) => { attrs[k] = v },
      removeAttribute: (k) => { delete attrs[k] },
      getAttribute: (k) => (k in attrs ? attrs[k] : null)
    }
  }
  global.matchMedia = () => ({ matches: mediaMatches, addEventListener() {}, addListener() {} })
  theme = await import('../src/renderer/js/theme.js')
})

test.beforeEach(() => {
  for (const k of Object.keys(store)) delete store[k]
  for (const k of Object.keys(attrs)) delete attrs[k]
  mediaMatches = false
})

test('getTheme default "system" saat penyimpanan kosong', () => {
  assert.equal(theme.getTheme(), 'system')
})

test('setTheme("dark") → tersimpan + atribut data-theme=dark', () => {
  theme.setTheme('dark')
  assert.equal(theme.getTheme(), 'dark')
  assert.equal(attrs['data-theme'], 'dark')
})

test('setTheme("system") → atribut data-theme dihapus', () => {
  theme.setTheme('dark')
  theme.setTheme('system')
  assert.equal(theme.getTheme(), 'system')
  assert.equal('data-theme' in attrs, false)
})

test('setTheme nilai tak dikenal → dinormalkan ke "system"', () => {
  assert.equal(theme.setTheme('ungu'), 'system')
  assert.equal(theme.getTheme(), 'system')
})

test('getEffectiveTheme meresolusi "system" via matchMedia', () => {
  theme.setTheme('system')
  mediaMatches = true
  assert.equal(theme.getEffectiveTheme(), 'dark')
  mediaMatches = false
  assert.equal(theme.getEffectiveTheme(), 'light')
})

test('cycleTheme membalik dari efektif terang → gelap', () => {
  theme.setTheme('light')
  assert.equal(theme.cycleTheme(), 'dark')
  assert.equal(attrs['data-theme'], 'dark')
})

test('applyTheme menstempel mode tersimpan tanpa setTheme', () => {
  store['mpos.theme'] = 'light'
  theme.applyTheme()
  assert.equal(attrs['data-theme'], 'light')
})
