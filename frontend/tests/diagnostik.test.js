'use strict'

// Diagnostik (kontrak #1): penyamaran rahasia, bentuk & batas body laporan, dedupe
// client_ref, antrean laporan offline, dan log berkas berotasi.

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const { samarkan, samarkanObjek, TANDA } = require('../src/main/lib/samarkan')
const { bangunLaporan, refLaporan, AntreanDiagnostik, MAKS_PESAN, MAKS_STACK, MAKS_KONTEKS_BYTE } = require('../src/main/lib/diagnostik')
const { buatPencatat } = require('../src/main/lib/pencatat')

const dirSementara = () => fs.mkdtempSync(path.join(os.tmpdir(), 'tuleh-diag-'))

test('samarkan: token Bearer/Sanctum/JWT, header Authorization, kunci Midtrans', () => {
  const s = samarkan([
    'GET /api/pos/v1/produk Authorization: Bearer 12|AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd',
    'token 45|ZyXwVuTsRqPoNmLkJiHgFeDcBa9876543210zyxw bocor',
    'jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.abcdefghijklmnop',
    'kunci SB-Mid-server-AbC123_xyz dan Mid-client-QwErTy'
  ].join('\n'))
  assert.doesNotMatch(s, /AbCdEfGhIjKl|ZyXwVuTsRq|eyJhbGci|Mid-server-AbC|Mid-client-QwE/)
  assert.match(s, new RegExp(TANDA.replace(/[[\]]/g, '\\$&')))
})

test('samarkan: kunci rahasia di JSON, objek JS, dan query string', () => {
  const s = samarkan('{"login":"kasir@toko.id","password":"rahasia123","pin":"123456","token":"abc","nama":"Budi"} '
    + "cfg={ server_key: 'sk-live-1', client_key: \"ck-1\" } "
    + 'url=/x?token=abc123&page=2&pin=9999')
  assert.doesNotMatch(s, /rahasia123|"123456"|"abc"|sk-live-1|ck-1|abc123|9999/)
  assert.match(s, /"nama":"Budi"/, 'data non-rahasia tetap utuh')
  assert.match(s, /page=2/)
  assert.match(s, /"login":"kasir@toko.id"/)
})

test('samarkanObjek: nilai berkunci rahasia dibuang rekursif', () => {
  const o = samarkanObjek({ layar: 'Kasir', gateway: { Authorization: 'Bearer x', token: 'y' }, catatan: 'Bearer zzzzzzzz', daftar: [{ pin: '1' }] })
  assert.equal(o.layar, 'Kasir')
  assert.equal(o.gateway.Authorization, TANDA)
  assert.equal(o.gateway.token, TANDA)
  assert.equal(o.daftar[0].pin, TANDA)
  assert.doesNotMatch(o.catatan, /zzzzzzzz/)
})

test('bangunLaporan: bentuk kontrak, batas panjang, konteks ≤10 KB, token disamarkan', () => {
  const l = bangunLaporan({
    platform: 'desktop', versi: '0.9.40', jenis: 'crash',
    pesan: 'x'.repeat(5000) + ' Bearer 1|abcdefghijklmnopqrstuvwxyz0123',
    stack: 'y'.repeat(30000),
    konteks: { layar: 'Kasir', besar: 'z'.repeat(20000), token: 'bocor' },
    terjadiPada: new Date('2026-09-15T02:03:04Z')
  })
  assert.deepEqual(Object.keys(l).sort(), ['client_ref', 'jenis', 'konteks', 'pesan', 'platform', 'stack', 'terjadi_pada', 'versi'])
  assert.equal(l.platform, 'desktop')
  assert.equal(l.jenis, 'crash')
  assert.ok(l.pesan.length <= MAKS_PESAN)
  assert.ok(l.stack.length <= MAKS_STACK)
  assert.ok(Buffer.byteLength(JSON.stringify(l.konteks)) <= MAKS_KONTEKS_BYTE)
  assert.equal(l.konteks.layar, 'Kasir')
  assert.notEqual(l.konteks.token, 'bocor')
  assert.equal(l.terjadi_pada, '2026-09-15T02:03:04.000Z')
  assert.equal(bangunLaporan({ platform: 'desktop', jenis: 'aneh', pesan: 'a' }).jenis, 'error', 'jenis tak dikenal → error')
})

test('client_ref: galat sama di hari sama = sama (dedupe); hari lain / log manual = beda', () => {
  const dasar = { jenis: 'error', pesan: 'TypeError: x', stack: 'at y', versi: '0.9.40' }
  const hari1 = new Date('2026-09-15T01:00:00Z')
  assert.equal(refLaporan(dasar, hari1), refLaporan(dasar, new Date('2026-09-15T20:00:00Z')))
  assert.notEqual(refLaporan(dasar, hari1), refLaporan(dasar, new Date('2026-09-16T01:00:00Z')))
  assert.notEqual(refLaporan({ ...dasar, jenis: 'log' }, hari1), refLaporan({ ...dasar, jenis: 'log' }, hari1))
})

test('AntreanDiagnostik: dedupe client_ref, gangguan menahan, 4xx dibuang, tersimpan di berkas', async () => {
  const berkas = path.join(dirSementara(), 'diagnostik.json')
  const a = new AntreanDiagnostik({ berkas })
  const l1 = bangunLaporan({ platform: 'desktop', versi: '1', jenis: 'error', pesan: 'satu' })
  const l2 = bangunLaporan({ platform: 'desktop', versi: '1', jenis: 'error', pesan: 'dua' })
  assert.equal(a.tambah(l1), true)
  assert.equal(a.tambah(l1), false, 'duplikat diabaikan')
  a.tambah(l2)
  assert.equal(new AntreanDiagnostik({ berkas }).jumlah, 2, 'bertahan saat aplikasi ditutup')

  const dikirim = []
  let jawab = { ok: false, status: 502, gangguan: true }
  const kirim = async (body) => { dikirim.push(body.pesan); return jawab }
  assert.equal(await a.kirimSemua(kirim), 0)
  assert.equal(a.jumlah, 2, 'offline → tetap di antrean')

  jawab = { ok: false, status: 422, message: 'tak sah' }
  await a.kirimSemua(async (b) => (b.pesan === 'satu' ? jawab : { ok: true, status: 202, data: { id: 9 } }))
  assert.equal(a.jumlah, 0, '4xx dibuang (tidak dicoba selamanya), 202 selesai')
})

test('pencatat: menulis log disamarkan, berotasi sesuai batas ukuran & jumlah berkas, ekor untuk laporan', () => {
  const dir = dirSementara()
  const p = buatPencatat({ dir, maksByte: 300, maksBerkas: 3, sekarang: () => new Date('2026-09-15T00:00:00Z') })
  for (let i = 0; i < 40; i++) p.tulis('main', 'info', `baris ${i} Authorization: Bearer 7|abcdefghijklmnopqrstuvwxyz0123456789`)
  const berkas = fs.readdirSync(dir).sort()
  assert.deepEqual(berkas, ['main.1.log', 'main.2.log', 'main.log'], 'maks 3 berkas')
  for (const b of berkas) {
    assert.ok(fs.statSync(path.join(dir, b)).size <= 300 + 200)
    assert.doesNotMatch(fs.readFileSync(path.join(dir, b), 'utf8'), /abcdefghijklmnop/)
  }
  p.tulis('gateway', 'info', 'level=INFO msg=req path=/api/pos/v1/ping')
  const ekor = p.ekor(['main', 'renderer', 'gateway'], 1000)
  assert.ok(ekor.length <= 1000)
  assert.match(ekor, /=== main\.log ===/)
  assert.match(ekor, /baris 39/, 'baris terbaru ada di ekor')
  assert.match(ekor, /=== gateway\.log ===/)
  assert.doesNotMatch(ekor, /renderer\.log/, 'berkas yang tak ada dilewati')
})

test('pencatat: tidak pernah melempar walau folder tidak bisa ditulis', () => {
  const fsRusak = { ...fs, mkdirSync: () => { throw new Error('EACCES') } }
  const p = buatPencatat({ dir: '/tidak/boleh', fsImpl: fsRusak })
  assert.doesNotThrow(() => p.tulis('main', 'error', new Error('x')))
})
