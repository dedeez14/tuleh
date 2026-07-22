'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')

let fmt

test.before(async () => {
  fmt = await import('../src/renderer/js/utils/format.js')
})

test('esc menetralkan karakter HTML berbahaya', () => {
  assert.equal(
    fmt.esc(`<img src=x onerror="alert('xss')">&`),
    '&lt;img src=x onerror=&quot;alert(&#39;xss&#39;)&quot;&gt;&amp;'
  )
  assert.equal(fmt.esc(null), '')
  assert.equal(fmt.esc(undefined), '')
  assert.equal(fmt.esc(12345), '12345')
})

test('fmtIDR memformat rupiah tanpa desimal', () => {
  const result = fmt.fmtIDR(18000)
  assert.match(result, /18\.000/)
  assert.match(result, /Rp/)
  assert.match(fmt.fmtIDR('bukan angka'), /0/)
})

test('parseAmount menerima berbagai format input uang', () => {
  assert.equal(fmt.parseAmount('50.000'), 50000)
  assert.equal(fmt.parseAmount('Rp 50.000'), 50000)
  assert.equal(fmt.parseAmount('50rb'), 50000)
  assert.equal(fmt.parseAmount('50k'), 50000)
  assert.equal(fmt.parseAmount('1,5jt'), 1500000)
  assert.equal(fmt.parseAmount(75000), 75000)
  assert.equal(fmt.parseAmount(''), 0)
  assert.equal(fmt.parseAmount('abc'), 0)
})

test('toISODate menghasilkan format YYYY-MM-DD', () => {
  assert.equal(fmt.toISODate(new Date(2026, 6, 2)), '2026-07-02')
  assert.equal(fmt.toISODate(new Date(2026, 0, 15)), '2026-01-15')
})
