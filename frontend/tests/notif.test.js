'use strict'

// Unit test notifikasi (derivasi dari state + keamanan escaping markup panel).

const test = require('node:test')
const assert = require('node:assert/strict')

let N
test.before(async () => {
  // notif.js → ui.js mendaftarkan listener keydown di document saat dimuat.
  global.document = { addEventListener() {} }
  N = await import('../src/renderer/js/notif.js')
})

test('state kosong → aman, notif "sesi belum dibuka", tanpa notif langganan', () => {
  const notifs = N.hitungNotifikasi({})
  assert.ok(Array.isArray(notifs))
  assert.ok(notifs.some((n) => n.id === 'sesi-tutup'))
  assert.ok(!notifs.some((n) => n.id === 'langganan'))
})

test('stok menipis/habis dari stokAlerts, dibatasi maksimum (<= 4)', () => {
  const stokAlerts = Array.from({ length: 10 }, (_, i) => ({
    id: `P${i}`, produk: `Produk ${i}`, stok: 1, min: 5, status: 'menipis'
  }))
  const notifs = N.hitungNotifikasi({ stokAlerts })
  const stok = notifs.filter((n) => n.id.startsWith('stok-'))
  assert.ok(stok.length > 0)
  assert.ok(stok.length <= 4)
})

test('stok habis → notif berwarna danger', () => {
  const notifs = N.hitungNotifikasi({ stokAlerts: [{ id: 'X', produk: 'Bakso', stok: 0, min: 5, status: 'habis' }] })
  const s = notifs.find((n) => n.id.startsWith('stok-'))
  assert.ok(s)
  assert.equal(s.warna, 'danger')
})

test('sesi aktif → notif "sesi aktif", bukan "sesi tutup"', () => {
  const notifs = N.hitungNotifikasi({ session: { nomor: 'SK-1' } })
  assert.ok(notifs.some((n) => n.id === 'sesi-aktif'))
  assert.ok(!notifs.some((n) => n.id === 'sesi-tutup'))
})

test('langganan sehat → TIDAK ada notif langganan (hindari klaim palsu)', () => {
  const notifs = N.hitungNotifikasi({ langganan: { status: 'AKTIF', sisa_hari: 20 } })
  assert.ok(!notifs.some((n) => n.id === 'langganan'))
})

test('langganan kedaluwarsa → notif langganan berwarna danger', () => {
  const notifs = N.hitungNotifikasi({ langganan: { status: 'KEDALUWARSA', sisa_hari: 0 } })
  const l = notifs.find((n) => n.id === 'langganan')
  assert.ok(l)
  assert.equal(l.warna, 'danger')
})

test('langganan segera berakhir → notif berwarna warn', () => {
  const notifs = N.hitungNotifikasi({ langganan: { status: 'AKTIF', sisa_hari: 3 } })
  const l = notifs.find((n) => n.id === 'langganan')
  assert.ok(l)
  assert.equal(l.warna, 'warn')
})

test('panel: empty state + tombol Hubungi CS selalu ada', () => {
  const html = N.renderPanelNotifikasi([])
  assert.match(html, /Tidak ada notifikasi baru/)
  assert.match(html, /data-cs-contact/)
  assert.match(html, /Hubungi CS/)
})

test('panel: judul/detail berbahaya di-escape (cegah XSS)', () => {
  const jahat = [{
    id: 'x', ikon: 'box', warna: 'info',
    judul: '<img src=x onerror=alert(1)>',
    detail: '<script>bad()</script>', waktu: 'now'
  }]
  const html = N.renderPanelNotifikasi(jahat)
  assert.ok(!html.includes('<img src=x'))
  assert.ok(!html.includes('<script>bad'))
  assert.match(html, /&lt;img/)
})
