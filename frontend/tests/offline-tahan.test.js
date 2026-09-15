'use strict'

// Ketahanan mode offline desktop (kesiapan produksi 2026-09-15):
//  - penulis antrean: gangguan (termasuk 5xx/galat gateway) diantrekan; 402 & 4xx tidak;
//  - pengurai: 5xx/gangguan dicoba ulang dengan mundur (bukan TINJAU); 402/426 menahan;
//  - antrean: tulis atomik + .bak, galat tulis dilaporkan, berkas rusak dipindah (tidak ditimpa).

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const { Antrean, STATUS, buatClientRef, waktuKlien } = require('../src/main/offline/antrean')
const { Pengurai, mundur, kebijakanDariConfig, AMBANG_PERINGATAN_PERCOBAAN } = require('../src/main/offline/pengurai')
const { buatTulisAtauAntre } = require('../src/main/offline/tulis')
const { Koneksi } = require('../src/main/offline')
const { tulisAtomik, bacaDenganPemulihan } = require('../src/main/lib/berkas-atomik')

function dirSementara() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'tuleh-tahan-'))
}

function offlinePalsu({ online = true, antrean = new Antrean({ berkas: null, sekarang: () => 1 }) } = {}) {
  const koneksi = new Koneksi()
  if (!online) koneksi.tandaiOffline()
  return { koneksi, antrean, STATUS, buatClientRef, waktuKlien }
}

// ---------- Penulis antrean ----------

test('tulisAtauAntre: sukses → dikembalikan dengan clientRef, tidak diantrekan', async () => {
  const off = offlinePalsu()
  const kirim = async (jalur, body) => ({ ok: true, status: 201, data: { nomor: 'N1', ref: body.client_ref } })
  const tulis = buatTulisAtauAntre({ offline: off, kirim, tokoAktif: () => 'T1' })
  const r = await tulis({ jenis: 'PENGELUARAN', jalur: '/pengeluaran', body: { nominal: 5 } })
  assert.equal(r.ok, true)
  assert.equal(r.data.ref, r.clientRef)
  assert.equal(off.antrean.ringkas().total, 0)
})

test('tulisAtauAntre: gateway 502 / 503 server / jaringan putus → diantrekan & tertunda', async () => {
  for (const jawaban of [
    { ok: false, status: 502, gangguan: true, gateway: 'upstream-unreachable', message: 'x' },
    { ok: false, status: 503, gangguan: true, message: 'pemeliharaan' },
    { ok: false, status: 0, gangguan: true, message: 'putus' }
  ]) {
    const off = offlinePalsu()
    let status = 0
    const tulis = buatTulisAtauAntre({ offline: off, kirim: async () => jawaban, tokoAktif: () => 'T1', setelahAntre: () => { status++ } })
    const r = await tulis({ jenis: 'CHECKOUT', jalur: '/transaksi/checkout', body: { items: [] }, deltaStok: { P1: -1 } })
    assert.equal(r.tertunda, true, `HTTP ${jawaban.status}`)
    assert.equal(r.status, 202)
    assert.equal(off.antrean.ringkas('T1').menunggu, 1)
    assert.equal(off.antrean.cari(r.clientRef).body.client_ref, r.clientRef)
    assert.deepEqual(off.antrean.deltaStokTertunda('T1'), { P1: -1 })
    assert.equal(status, 1)
  }
})

test('tulisAtauAntre: 402 langganan & 422 ditolak → dikembalikan apa adanya, TIDAK diantrekan', async () => {
  for (const jawaban of [
    { ok: false, status: 402, message: 'Langganan berakhir', errors: { langganan: ['BERAKHIR'] } },
    { ok: false, status: 422, message: 'Stok kurang' },
    { ok: false, status: 401, message: 'Sesi berakhir' }
  ]) {
    const off = offlinePalsu()
    const tulis = buatTulisAtauAntre({ offline: off, kirim: async () => jawaban, tokoAktif: () => null })
    const r = await tulis({ jenis: 'CHECKOUT', jalur: '/transaksi/checkout', body: {} })
    assert.equal(r.status, jawaban.status)
    assert.equal(r.tertunda, undefined)
    assert.equal(off.antrean.ringkas().total, 0, `HTTP ${jawaban.status} tidak boleh masuk antrean`)
  }
})

test('tulisAtauAntre: diketahui offline → langsung diantrekan tanpa mencoba kirim', async () => {
  const off = offlinePalsu({ online: false })
  let dikirim = 0
  const tulis = buatTulisAtauAntre({ offline: off, kirim: async () => { dikirim++; return { ok: true } }, tokoAktif: () => 'T1' })
  const r = await tulis({ jenis: 'STOK_MASUK', jalur: '/inventory/stok-masuk', body: { jumlah: 2 } })
  assert.equal(r.tertunda, true)
  assert.equal(dikirim, 0)
})

test('tulisAtauAntre: antrean gagal disimpan ke disk → tetap tertunda tetapi membawa peringatan', async () => {
  const dir = dirSementara()
  const fsRusak = { ...fs, writeSync: () => { throw Object.assign(new Error('ENOSPC: no space left on device'), { code: 'ENOSPC' }) } }
  const galat = []
  const antrean = new Antrean({ berkas: path.join(dir, 'antrean.json'), fsImpl: fsRusak, onGalat: (g) => galat.push(g) })
  const off = offlinePalsu({ online: false, antrean })
  const tulis = buatTulisAtauAntre({ offline: off, kirim: async () => ({ ok: true }), tokoAktif: () => null })
  const r = await tulis({ jenis: 'CHECKOUT', jalur: '/transaksi/checkout', body: {} })
  assert.equal(r.tertunda, true)
  assert.match(r.peringatan, /gagal disimpan/)
  assert.equal(galat.length, 1)
  assert.equal(galat[0].jenis, 'simpan')
  assert.match(galat[0].detail, /ENOSPC/)
  assert.equal(antrean.masalahPenyimpanan().jenis, 'simpan')
})

// ---------- Pengurai ----------

function antreanMemori() { return new Antrean({ berkas: null, sekarang: () => 0 }) }

test('Pengurai: jaringan putus / gateway tak terjangkau / 429 → jeda GLOBAL, urutan utuh (bukan TINJAU)', async () => {
  for (const res of [
    { ok: false, status: 0, gangguan: true, message: 'putus' },
    { ok: false, status: 502, gangguan: true, gateway: 'upstream-unreachable' },
    { ok: false, status: 429, gangguan: true }
  ]) {
    const a = antreanMemori()
    a.antrekan({ clientRef: 'a', jenis: 'CHECKOUT', path: '/x', body: {} })
    a.antrekan({ clientRef: 'b', jenis: 'CHECKOUT', path: '/x', body: {} })
    const koneksi = new Koneksi()
    const log = []
    const pg = new Pengurai({ antrean: a, koneksi, kirim: async (_p, _b, pesan) => { log.push(pesan.clientRef); return res }, sekarang: () => 1000, jadwal: () => null, batalJadwal: () => {} })
    await pg.jalankan()
    assert.equal(a.cari('a').status, STATUS.MENUNGGU, `HTTP ${res.status}`)
    assert.equal(a.cari('a').percobaan, 1)
    assert.deepEqual(log, ['a'], 'server tak terjangkau → baris lain tidak dipukul percuma')
    assert.equal(pg.status().jeda.sebab, 'JARINGAN')
    assert.equal(koneksi.online, false)
    assert.equal(a.ringkas().tinjau, 0)
    await pg.jalankan()
    assert.deepEqual(log, ['a'], 'selama jeda jaringan tidak ada kiriman')
    koneksi.tandaiOnline() // koneksi terbukti pulih (permintaan lain sampai ke server)
    await pg.jalankan()
    assert.deepEqual(log, ['a', 'a'], 'setelah pulih dicoba lagi dari baris pertama (urutan utuh)')
  }
})

// ---------- Head-of-line: satu muatan beracun tidak menahan penjualan lain ----------

function antreanTiga(jam) {
  const a = new Antrean({ berkas: null, sekarang: () => jam.nilai })
  a.antrekan({ clientRef: 'racun', jenis: 'CHECKOUT', path: '/transaksi/checkout', body: { n: 1 } })
  a.antrekan({ clientRef: 'sehat1', jenis: 'PENGELUARAN', path: '/pengeluaran', body: { n: 2 } })
  a.antrekan({ clientRef: 'sehat2', jenis: 'STOK_MASUK', path: '/inventory/stok-masuk', body: { n: 3 } })
  return a
}
const kirimRacun = (log) => async (_p, _b, pesan) => {
  log.push(pesan.clientRef)
  return pesan.clientRef === 'racun'
    ? { ok: false, status: 500, gangguan: true, message: 'SQLSTATE[22003]: nilai di luar rentang' }
    : { ok: true, status: 201, data: { nomor: `N-${pesan.clientRef}` } }
}
async function putarSampai(pg, a, jam, kali) {
  for (let i = 0; i < kali && a.cari('racun').status === STATUS.MENUNGGU; i++) {
    jam.nilai = Math.max(jam.nilai + 1, a.cari('racun').cobaLagiSetelah || 0) // tunggu mundurnya
    await pg.jalankan()
  }
}

test('HOL: satu baris 5xx beracun + dua baris sehat → yang sehat TERKIRIM di putaran yang sama; racun mundur sendiri', async () => {
  const jam = { nilai: 1_000_000 }
  const a = antreanTiga(jam)
  const log = []
  const pg = new Pengurai({ antrean: a, kirim: kirimRacun(log), sekarang: () => jam.nilai, jadwal: () => null, batalJadwal: () => {} })
  assert.equal(await pg.jalankan(), 2)
  assert.deepEqual(log, ['racun', 'sehat1', 'sehat2'], 'FIFO di antara baris yang siap')
  assert.equal(a.cari('sehat1').status, STATUS.TERKIRIM)
  assert.equal(a.cari('sehat2').status, STATUS.TERKIRIM)
  const racun = a.cari('racun')
  assert.equal(racun.status, STATUS.MENUNGGU)
  assert.equal(racun.galatServer, 1)
  assert.equal(racun.cobaLagiSetelah, jam.nilai + mundur(1))
  assert.match(racun.galat, /nilai di luar rentang/)

  // Penjualan baru dibuat setelahnya tetap terkirim walau racun belum waktunya dicoba.
  a.antrekan({ clientRef: 'sehat3', jenis: 'CHECKOUT', path: '/transaksi/checkout', body: {} })
  jam.nilai += 1
  assert.equal(await pg.jalankan(), 1)
  assert.deepEqual(log.slice(3), ['sehat3'], 'racun masih dalam mundurnya → dilewati, bukan menahan')
})

test('HOL: batas dari /config ada → racun pindah ke TINJAU dengan pesan server terakhir', async () => {
  const jam = { nilai: 1_000_000 }
  const a = antreanTiga(jam)
  const log = []
  const kebijakan = kebijakanDariConfig({ antrean_maks_percobaan_galat_server: 3, antrean_maks_umur_jam: 48 })
  const pg = new Pengurai({ antrean: a, kirim: kirimRacun(log), kebijakan: () => kebijakan, sekarang: () => jam.nilai, jadwal: () => null, batalJadwal: () => {} })
  await pg.jalankan()
  await putarSampai(pg, a, jam, 10)
  const racun = a.cari('racun')
  assert.equal(racun.status, STATUS.TINJAU)
  assert.equal(racun.galatServer, 3)
  assert.match(racun.galat, /SQLSTATE\[22003\]: nilai di luar rentang/)
  assert.equal(log.filter((r) => r === 'racun').length, 3, 'tepat sebanyak batas server')
  assert.equal(a.ringkas().tinjau, 1)
})

test('HOL: batas umur (antrean_maks_umur_jam) → racun lama langsung ditinjau pada galat server berikutnya', async () => {
  const jam = { nilai: 1_000_000 }
  const a = antreanTiga(jam)
  const kebijakan = kebijakanDariConfig({ antrean_maks_umur_jam: 24 })
  const pg = new Pengurai({ antrean: a, kirim: kirimRacun([]), kebijakan: () => kebijakan, sekarang: () => jam.nilai, jadwal: () => null, batalJadwal: () => {} })
  await pg.jalankan()
  assert.equal(a.cari('racun').status, STATUS.MENUNGGU, 'belum 24 jam')
  jam.nilai += 25 * 3600000
  await pg.jalankan()
  assert.equal(a.cari('racun').status, STATUS.TINJAU)
  assert.match(a.cari('racun').galat, /lebih dari 24 jam/)
})

test('HOL: server TIDAK mengirim batas → racun tetap menunggu (tidak ditinjau otomatis) + peringatan setelah 10 percobaan', async () => {
  const jam = { nilai: 1_000_000 }
  const a = antreanTiga(jam)
  const log = []
  const kebijakan = kebijakanDariConfig({ nama: 'config lama tanpa field antrean' })
  assert.deepEqual(kebijakan, { maksPercobaanGalatServer: null, maksUmurJam: null })
  const pg = new Pengurai({ antrean: a, kirim: kirimRacun(log), kebijakan: () => kebijakan, sekarang: () => jam.nilai, jadwal: () => null, batalJadwal: () => {} })
  await pg.jalankan()
  await putarSampai(pg, a, jam, AMBANG_PERINGATAN_PERCOBAAN + 5)
  const racun = a.cari('racun')
  assert.equal(racun.status, STATUS.MENUNGGU)
  assert.ok(racun.galatServer >= AMBANG_PERINGATAN_PERCOBAAN)
  assert.equal(a.ringkas().tinjau, 0)
  assert.equal(a.macet(null, AMBANG_PERINGATAN_PERCOBAAN), 1, 'panel Sinkronisasi menampilkan peringatan menetap')
  assert.equal(new Antrean({ berkas: null }).macet(null, AMBANG_PERINGATAN_PERCOBAAN), 0)
  assert.equal(AMBANG_PERINGATAN_PERCOBAAN, 10)
})

test('kebijakanDariConfig: angka positif saja; string angka diterima; 0/negatif/teks → tanpa batas', () => {
  assert.deepEqual(kebijakanDariConfig({ antrean_maks_percobaan_galat_server: '5', antrean_maks_umur_jam: 12.5 }), { maksPercobaanGalatServer: 5, maksUmurJam: 12.5 })
  assert.deepEqual(kebijakanDariConfig({ antrean_maks_percobaan_galat_server: 0, antrean_maks_umur_jam: -1 }), { maksPercobaanGalatServer: null, maksUmurJam: null })
  assert.deepEqual(kebijakanDariConfig({ antrean_maks_percobaan_galat_server: 'x', antrean_maks_umur_jam: true }), { maksPercobaanGalatServer: null, maksUmurJam: null })
  assert.deepEqual(kebijakanDariConfig(null), { maksPercobaanGalatServer: null, maksUmurJam: null })
})

test('HOL: timeout per baris juga tidak menahan baris lain, dan tidak dihitung sebagai galat server', async () => {
  const a = antreanMemori()
  a.antrekan({ clientRef: 'lambat', jenis: 'CHECKOUT', path: '/x', body: {} })
  a.antrekan({ clientRef: 'cepat', jenis: 'CHECKOUT', path: '/x', body: {} })
  const pg = new Pengurai({
    antrean: a,
    kirim: async (_p, _b, pesan) => (pesan.clientRef === 'lambat' ? { ok: false, status: -1, gangguan: true, timeout: true } : { ok: true, status: 201, data: {} }),
    kebijakan: () => kebijakanDariConfig({ antrean_maks_percobaan_galat_server: 1 }),
    jadwal: () => null, batalJadwal: () => {}
  })
  await pg.jalankan()
  assert.equal(a.cari('cepat').status, STATUS.TERKIRIM)
  assert.equal(a.cari('lambat').status, STATUS.MENUNGGU, 'timeout tidak memindahkan ke tinjau')
  assert.equal(a.cari('lambat').galatServer || 0, 0)
})

test('Pengurai: 402 di tengah antrean → jeda global, baris lain & baris 402 tetap MENUNGGU', async () => {
  const a = antreanMemori()
  a.antrekan({ clientRef: 'a', jenis: 'CHECKOUT', path: '/x', body: {} })
  a.antrekan({ clientRef: 'b', jenis: 'CHECKOUT', path: '/x', body: {} })
  const log = []
  const pg = new Pengurai({ antrean: a, kirim: async (_p, _b, pesan) => { log.push(pesan.clientRef); return { ok: false, status: 402, message: 'Langganan berakhir' } }, jadwal: () => null, batalJadwal: () => {} })
  await pg.jalankan()
  await pg.jalankan()
  assert.deepEqual(log, ['a'])
  assert.equal(a.ringkas().menunggu, 2)
  assert.equal(a.ringkas().tinjau, 0)
  await pg.sinkronSekarang() // mis. setelah perpanjang: sinkron manual melewati jeda
  assert.deepEqual(log, ['a', 'a'])
})

test('Pengurai: 401 → berhenti; tanpa token (siapKirim false) tidak mengirim apa pun', async () => {
  const a = antreanMemori()
  a.antrekan({ clientRef: 'a', jenis: 'CHECKOUT', path: '/x', body: {} })
  let token = false
  let dikirim = 0
  const pg = new Pengurai({ antrean: a, siapKirim: () => token, kirim: async () => { dikirim++; return { ok: true, status: 201, data: {} } }, jadwal: () => null, batalJadwal: () => {} })
  assert.equal(await pg.jalankan(), 0)
  assert.equal(dikirim, 0)
  token = true
  assert.equal(await pg.jalankan(), 1)
})

test('Pengurai: 402 menahan antrean tanpa TINJAU (penjualan tidak dibuang); 426 menunggu update', async () => {
  const a = antreanMemori()
  a.antrekan({ clientRef: 'a', jenis: 'CHECKOUT', path: '/x', body: {} })
  let mode = '402'
  const kirim = async () => mode === '402'
    ? { ok: false, status: 402, message: 'Langganan berakhir', errors: { langganan: ['BERAKHIR'] } }
    : mode === '426' ? { ok: false, status: 426, message: 'Perbarui' } : { ok: true, status: 200, data: { nomor: 'N' } }
  const pg = new Pengurai({ antrean: a, kirim, sekarang: () => 50, jadwal: () => null, batalJadwal: () => {} })
  await pg.jalankan()
  assert.equal(a.cari('a').status, STATUS.MENUNGGU)
  assert.equal(a.cari('a').galat, 'Langganan berakhir', 'pesan server, bukan kode')
  assert.ok(a.cari('a').cobaLagiSetelah > 50)
  mode = '426'
  await pg.kirimUlang('a')
  assert.equal(a.cari('a').status, STATUS.MENUNGGU)
  mode = 'ok'
  await pg.kirimUlang('a')
  assert.equal(a.cari('a').status, STATUS.TERKIRIM)
})

test('Pengurai: penolakan 4xx (409/422/403) tetap TINJAU', async () => {
  for (const status of [403, 409, 422]) {
    const a = antreanMemori()
    a.antrekan({ clientRef: 'a', jenis: 'CHECKOUT', path: '/x', body: {} })
    const pg = new Pengurai({ antrean: a, kirim: async () => ({ ok: false, status, message: `ditolak ${status}` }), jadwal: () => null, batalJadwal: () => {} })
    await pg.jalankan()
    assert.equal(a.cari('a').status, STATUS.TINJAU, `HTTP ${status}`)
  }
})

// ---------- Ketahanan berkas antrean ----------

test('tulisAtomik: generasi sebelumnya disimpan sebagai .bak, tanpa .tmp tersisa', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'antrean.json')
  tulisAtomik(berkas, JSON.stringify({ pesan: [1] }))
  tulisAtomik(berkas, JSON.stringify({ pesan: [1, 2] }))
  assert.deepEqual(JSON.parse(fs.readFileSync(berkas, 'utf8')).pesan, [1, 2])
  assert.deepEqual(JSON.parse(fs.readFileSync(`${berkas}.bak`, 'utf8')).pesan, [1])
  assert.equal(fs.existsSync(`${berkas}.tmp`), false)
})

test('Antrean: berkas utama terpotong (tulis parsial) → dipulihkan dari .bak, berkas rusak dipindah & dilaporkan', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'antrean.json')
  const a = new Antrean({ berkas })
  a.antrekan({ clientRef: 'lama', jenis: 'CHECKOUT', path: '/x', body: { v: 1 } })
  a.antrekan({ clientRef: 'baru', jenis: 'CHECKOUT', path: '/x', body: { v: 2 } }) // .bak = hanya 'lama'
  const utuh = fs.readFileSync(berkas, 'utf8')
  fs.writeFileSync(berkas, utuh.slice(0, Math.floor(utuh.length / 2))) // listrik padam di tengah tulis

  const galat = []
  const b = new Antrean({ berkas, onGalat: (g) => galat.push(g), sekarang: () => Date.parse('2026-09-15T01:02:03Z') })
  assert.deepEqual(b.semua().map((p) => p.clientRef), ['lama'])
  assert.equal(galat.length, 1)
  assert.equal(galat[0].jenis, 'muat')
  assert.match(b.masalahPenyimpanan().pesan, /dipulihkan dari salinan cadangan/)
  const rusak = fs.readdirSync(dir).filter((n) => n.includes('.rusak-'))
  assert.deepEqual(rusak, ['antrean.rusak-2026-09-15T01-02-03-000Z.json'])
  assert.equal(fs.readFileSync(path.join(dir, rusak[0]), 'utf8'), utuh.slice(0, Math.floor(utuh.length / 2)), 'berkas rusak disimpan utuh untuk dukungan')

  // Penulisan berikutnya tidak menimpa cadangan yang sah dengan berkas rusak.
  b.antrekan({ clientRef: 'lagi', jenis: 'PENGELUARAN', path: '/p', body: {} })
  assert.deepEqual(new Antrean({ berkas }).semua().map((p) => p.clientRef), ['lama', 'lagi'])
})

test('Antrean: utama & .bak rusak → keduanya dipindah ke samping, antrean kosong + peringatan (tidak ditimpa diam-diam)', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'antrean.json')
  fs.writeFileSync(berkas, '{"pesan": [ {"clientRef": "x"')
  fs.writeFileSync(`${berkas}.bak`, 'bukan json')
  const galat = []
  const a = new Antrean({ berkas, onGalat: (g) => galat.push(g), sekarang: () => Date.parse('2026-09-15T00:00:00Z') })
  assert.equal(a.semua().length, 0)
  assert.match(a.masalahPenyimpanan().pesan, /tidak bisa dipulihkan/)
  assert.equal(galat[0].berkasRusak.length, 2)
  const nama = fs.readdirSync(dir).sort()
  assert.ok(nama.includes('antrean.rusak-2026-09-15T00-00-00-000Z.json'), nama.join(','))
  assert.ok(nama.includes('antrean.bak.rusak-2026-09-15T00-00-00-000Z.json'), nama.join(','))
  assert.equal(fs.existsSync(berkas), false, 'berkas rusak tidak ditimpa kosong')
})

test('Antrean: bentuk JSON sah tapi bukan antrean (mis. array) diperlakukan rusak', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'antrean.json')
  fs.writeFileSync(berkas, '[1,2,3]')
  const a = new Antrean({ berkas })
  assert.ok(a.masalahPenyimpanan())
  assert.ok(fs.readdirSync(dir).some((n) => n.includes('.rusak-')))
})

test('Antrean: proses mati setelah utama→.bak sebelum .tmp→utama → generasi .tmp terbaru dipakai', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'antrean.json')
  fs.writeFileSync(`${berkas}.bak`, JSON.stringify({ pesan: [{ urut: 1, clientRef: 'lama', status: 'MENUNGGU' }] }))
  fs.writeFileSync(`${berkas}.tmp`, JSON.stringify({ pesan: [{ urut: 1, clientRef: 'lama', status: 'MENUNGGU' }, { urut: 2, clientRef: 'baru', status: 'MENUNGGU' }] }))
  const h = bacaDenganPemulihan(berkas, (d) => d && Array.isArray(d.pesan))
  assert.equal(h.sumber, 'sementara')
  assert.equal(new Antrean({ berkas }).semua().length, 2)
})

test('Antrean: gagal tulis dilaporkan sekali; tulis berikutnya yang berhasil membersihkan galat', () => {
  const dir = dirSementara()
  const berkas = path.join(dir, 'antrean.json')
  let rusak = true
  const fsKadang = { ...fs, fsyncSync: (fd) => { if (rusak) throw new Error('EIO: i/o error'); return fs.fsyncSync(fd) } }
  const galat = []
  const a = new Antrean({ berkas, fsImpl: fsKadang, onGalat: (g) => galat.push(g) })
  a.antrekan({ clientRef: 'a', jenis: 'CHECKOUT', path: '/x', body: {} })
  assert.equal(a.simpan(), false)
  assert.equal(galat.length, 1, 'tidak membanjiri laporan')
  assert.ok(a.galatSimpan)
  rusak = false
  assert.equal(a.simpan(), true)
  assert.equal(a.galatSimpan, null)
  assert.equal(a.masalahPenyimpanan(), null)
  assert.deepEqual(new Antrean({ berkas }).semua().map((p) => p.clientRef), ['a'])
})

test('status offline: macet & tinjauOtomatis untuk panel Sinkronisasi; batas diambil dari /config', () => {
  const offline = require('../src/main/offline')
  offline.init({ dir: dirSementara(), kirim: async () => ({ ok: true }) })
  offline.antrean.antrekan({ clientRef: 'racun', jenis: 'CHECKOUT', tokoId: 'T1', path: '/x', body: {} })
  offline.antrean.perbarui('racun', { galatServer: AMBANG_PERINGATAN_PERCOBAAN, sebabTunda: 'SERVER' })
  offline.aturKebijakanAntrean({ nama: 'tanpa field antrean' })
  assert.deepEqual([offline.status('T1').macet, offline.status('T1').tinjauOtomatis], [1, false])
  offline.aturKebijakanAntrean({ antrean_maks_percobaan_galat_server: 15, antrean_maks_umur_jam: 48 })
  assert.equal(offline.status('T1').tinjauOtomatis, true)
  assert.deepEqual(offline.kebijakanAntrean, { maksPercobaanGalatServer: 15, maksUmurJam: 48 })
  assert.equal(offline.status('T2').macet, 0, 'dihitung per toko')
})

test('Mode Demo: /config membawa batas tinjau antrean', () => {
  const demo = require('../src/main/demo.js')
  demo.start()
  try {
    const c = demo.handlers['config:get']().data
    const k = kebijakanDariConfig(c)
    assert.ok(k.maksPercobaanGalatServer > 0)
    assert.ok(k.maksUmurJam > 0)
  } finally { demo.stop() }
})
