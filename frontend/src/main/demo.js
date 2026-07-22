'use strict'

// Mode Demo — mensimulasikan MOVERA POS API sepenuhnya di memori main process.
// Handler menerima payload MENTAH dari renderer (camelCase, sama seperti
// channel IPC) dan mengembalikan envelope ternormalisasi {ok, status, data, meta}.
// State di-reset setiap kali demo dimulai ulang / aplikasi ditutup.

const crypto = require('node:crypto')
const {
  COMPANY, USER, BRANCH, KATEGORI, GUDANG, SATUAN, PELANGGAN_AWAL, TOKOS, MANIFESTS, TABLES,
  buatProduk, buatProdukBakso, buatProdukLaundry, KATEGORI_BAKSO, KATEGORI_LAUNDRY
} = require('./demo-data')

// Label tahap untuk halaman pelacakan pelanggan
const STAGE_LABELS = {
  MENUNGGU_BAYAR: 'Menunggu Pembayaran di Kasir',
  ANTRIAN: 'Antrian',
  DIPROSES: 'Diproses',
  READY: 'Siap',
  PENCUCIAN: 'Pencucian',
  PENGERINGAN: 'Pengeringan',
  LIPAT: 'Lipat & Kemas',
  SIAP_AMBIL: 'Siap Diambil',
  SELESAI: 'Selesai'
}

let active = false
let catalogs = {}      // tokoId → { produk: [], kategori: [] } — wajah kasir per toko
let pelanggan = []
let sesiList = []      // rekap penuh (+toko_id), terbaru dulu
let transaksi = []     // struk penuh (+toko_id) + tanggal ISO, terbaru dulu
let orders = []        // pesanan hidup (POS universal), semua toko
let bills = []         // bon meja hidup (open bill dine-in), semua toko
let stations = []      // stasiun kerja (kasir/dapur/mesin), semua toko
let counter = { trx: 0, sesi: 0, cust: 0, order: 0, station: 0, bill: 0 }
let antrianCounter = {}          // per toko: nomor antrian berjalan
let activeTokoId = 'TOKO-1'      // toko terpilih (di-set renderer via toko:select)

const ANTRIAN_PREFIX = { 'TOKO-2': 'A', 'TOKO-3': 'L' }

const produkToko = (tokoId) => (catalogs[tokoId] || {}).produk || []
const kategoriToko = (tokoId) => (catalogs[tokoId] || {}).kategori || []
const produkAktif = () => produkToko(activeTokoId)

function lifecycleStates(tokoId) {
  const m = MANIFESTS[tokoId]
  return m && m.lifecycle && Array.isArray(m.lifecycle.states) ? m.lifecycle.states : []
}

function pakaiAntrian(tokoId) {
  return lifecycleStates(tokoId).length > 1
}

function nomorAntrianBerikut(tokoId) {
  antrianCounter[tokoId] = (antrianCounter[tokoId] || 0) + 1
  const prefix = ANTRIAN_PREFIX[tokoId] || 'Q'
  return `${prefix}-${String(antrianCounter[tokoId]).padStart(3, '0')}`
}

const STATUS_STASIUN = ['AKTIF', 'ISTIRAHAT', 'NONAKTIF']

function buatStasiun({ tokoId, type, nama, status = 'AKTIF', kapasitas = null }) {
  counter.station += 1
  return { id: `STN-${counter.station}`, toko_id: tokoId, type, nama, status, kapasitas }
}

function buatOrder({ tokoId, items, total, pelangganNama = null, menitLalu = 0, stage = null, tanpaAntrian = false }) {
  counter.order += 1
  const dibuat = new Date(Date.now() - menitLalu * 60000)
  const states = lifecycleStates(tokoId)
  return {
    id: `ORD-${counter.order}`,
    nomor: `ORD/${String(counter.order).padStart(4, '0')}`,
    token_lacak: crypto.randomBytes(16).toString('hex'),
    // Order dari QR meja belum bayar → nomor antrian terbit saat konfirmasi kasir
    no_antrian: tanpaAntrian ? null : nomorAntrianBerikut(tokoId),
    toko_id: tokoId,
    stage: stage || states[0] || 'ANTRIAN',
    items,
    total,
    pelanggan: pelangganNama,
    bayar: 'LUNAS', // 'BELUM' utk nota bayar-saat-ambil / order QR meja
    created_at: dibuat.toISOString(),
    updated_at: dibuat.toISOString()
  }
}

// ---------- Bon Meja (open bill dine-in) ----------
// Satu bon berjalan per meja: dibuka saat pelanggan datang, diisi beberapa
// ronde pesanan (masing-masing jadi tiket dapur), lalu dilunasi di akhir.
// Meja dianggap TERISI selama ada bon berstatus BUKA/BILL yang memuatnya.

const bonMejaAktif = (b) => b.status === 'BUKA' || b.status === 'BILL'

function bonUntukMeja(mejaId) {
  return bills.find((b) => bonMejaAktif(b) && b.meja_ids.includes(mejaId)) || null
}

function buatBon({ tokoId, mejaIds, pax = 1, pelangganNama = null }) {
  counter.bill += 1
  const now = new Date().toISOString()
  return {
    id: `BILL-${counter.bill}`,
    nomor: `BON/${String(counter.bill).padStart(4, '0')}`,
    toko_id: tokoId,
    meja_ids: [...mejaIds],
    pax: Math.max(1, Math.min(Number(pax) || 1, 99)),
    status: 'BUKA',        // BUKA → BILL (pra-bon dicetak) → LUNAS/GABUNG/BATAL
    bill_dicetak: false,
    pelanggan: pelangganNama,
    catatan: null,
    rounds: [],            // [{ ronde, waktu, order_id, items, sumber }]
    dibuka_at: now,
    updated_at: now
  }
}

// Label meja untuk kartu dapur & struk — gabungan bila lintas-meja
function bonLabel(bill) {
  const nomors = bill.meja_ids
    .map((id) => (TABLES.find((t) => t.id === id) || {}).nomor)
    .filter(Boolean)
  if (nomors.length > 1) return `Meja ${nomors.join('+')}`
  return `Meja ${nomors[0] || '?'}`
}

// Agregasi item semua ronde jadi baris unik per produk (untuk pra-bon & struk)
function bonItems(bill) {
  const peta = new Map()
  for (const r of bill.rounds) {
    for (const it of r.items) {
      const ada = peta.get(it.idProduk)
      if (ada) ada.kuantitas = round2(ada.kuantitas + it.kuantitas)
      else peta.set(it.idProduk, { ...it })
    }
  }
  return [...peta.values()]
}

function bonTotal(bill) {
  return round2(bill.rounds.reduce(
    (s, r) => s + r.items.reduce((ss, it) => ss + it.harga * it.kuantitas, 0), 0))
}

// Ringkasan bon untuk renderer (peta & detail)
function bonRingkas(bill) {
  const items = bonItems(bill)
  return {
    id: bill.id,
    nomor: bill.nomor,
    toko_id: bill.toko_id,
    meja_ids: [...bill.meja_ids],
    label: bonLabel(bill),
    pax: bill.pax,
    status: bill.status,
    bill_dicetak: bill.bill_dicetak,
    pelanggan: bill.pelanggan,
    catatan: bill.catatan,
    dibuka_at: bill.dibuka_at,
    updated_at: bill.updated_at,
    ronde: bill.rounds.length,
    jumlah_item: round2(items.reduce((s, it) => s + it.kuantitas, 0)),
    total: bonTotal(bill),
    items,
    rounds: bill.rounds.map((r) => ({ ...r }))
  }
}

// Tiket dapur untuk satu ronde bon — identitas = MEJA, dibayar via bon (BON)
function tiketDapurBon(bill, items, ronde) {
  const total = round2(items.reduce((s, it) => s + it.harga * it.kuantitas, 0))
  const order = buatOrder({
    tokoId: bill.toko_id,
    items: items.map((it) => ({ idProduk: it.idProduk, nama: it.nama, kuantitas: it.kuantitas, harga: it.harga, catatan: it.catatan || null })),
    total,
    // Identitas tiket = nomor MEJA (order.meja). pelanggan hanya diisi bila
    // bon memang bernama; jangan pakai label meja agar tak jadi "pelanggan palsu"
    // di kartu dapur setelah meja digabung (label berubah).
    pelangganNama: bill.pelanggan || null,
    tanpaAntrian: true    // dine-in: dikenali dari nomor MEJA, bukan antrian
  })
  order.bayar = 'BON'
  order.meja = bonLabel(bill)
  order.bill_id = bill.id
  order.ronde = ronde
  return order
}

// PRNG deterministik agar data seed selalu sama
function mulberry32(seed) {
  let a = seed
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const round2 = (v) => Math.round((v + Number.EPSILON) * 100) / 100
const ok = (data, meta = null) => ({ ok: true, status: 200, data, meta, message: '' })
const err = (status, message) => ({ ok: false, status, message, errors: null })
const isoDate = (d) => d.toISOString().slice(0, 10)

function hitungItem(p, kuantitas, diskonPersen) {
  const bruto = round2(p.harga_jual * kuantitas)
  const diskon = round2((bruto * diskonPersen) / 100)
  const dpp = round2(bruto - diskon)
  const pajak = round2((dpp * (Number(p.pajak_persen) || 0)) / 100)
  return {
    nama: p.nama,
    kuantitas,
    satuan: p.satuan,
    harga: p.harga_jual,
    diskon_persen: diskonPersen,
    pajak_persen: Number(p.pajak_persen) || 0,
    subtotal: round2(dpp + pajak),
    _bruto: bruto,
    _diskon: diskon,
    _pajak: pajak
  }
}

function buatStruk({ tokoId, items, tipePembayaran, dibayar, namaPelanggan, tanggal, status = 'SELESAI' }) {
  const subtotal = round2(items.reduce((s, i) => s + i._bruto, 0))
  const totalDiskon = round2(items.reduce((s, i) => s + i._diskon, 0))
  const totalPajak = round2(items.reduce((s, i) => s + i._pajak, 0))
  const grand = round2(subtotal - totalDiskon + totalPajak)
  counter.trx += 1
  return {
    id: `TRX-${counter.trx}`,
    nomor: `POS-${String(counter.trx).padStart(6, '0')}`,
    toko_id: tokoId,
    tanggal: tanggal.toISOString(),
    status,
    pelanggan: namaPelanggan || null,
    kasir: USER.name,
    tipe_pembayaran: tipePembayaran,
    subtotal,
    total_diskon: totalDiskon,
    total_pajak: totalPajak,
    grand_total: grand,
    dibayar: dibayar !== undefined ? dibayar : grand,
    kembalian: round2(Math.max((dibayar !== undefined ? dibayar : grand) - grand, 0)),
    items: items.map(({ _bruto, _diskon, _pajak, ...item }) => item)
  }
}

function sesiAktif(tokoId = activeTokoId) {
  return sesiList.find((s) => s.toko_id === tokoId && s.status === 'BUKA') || null
}

function tambahKeSesi(sesi, struk) {
  const key = { TUNAI: 'total_tunai', TRANSFER: 'total_transfer', QRIS: 'total_qris' }[struk.tipe_pembayaran]
  if (key) sesi[key] = round2(sesi[key] + struk.grand_total)
  sesi.total_penjualan = round2(sesi.total_penjualan + struk.grand_total)
  sesi.jumlah_transaksi += 1
  sesi.kas_akhir_sistem = round2(sesi.kas_awal + sesi.total_tunai)
}

function kurangiDariSesi(sesi, struk) {
  const key = { TUNAI: 'total_tunai', TRANSFER: 'total_transfer', QRIS: 'total_qris' }[struk.tipe_pembayaran]
  if (key) sesi[key] = round2(sesi[key] - struk.grand_total)
  sesi.total_penjualan = round2(sesi.total_penjualan - struk.grand_total)
  sesi.jumlah_transaksi -= 1
  sesi.kas_akhir_sistem = round2(sesi.kas_awal + sesi.total_tunai)
}

function buatSesi({ tokoId, buka, kasAwal, gudangId }) {
  counter.sesi += 1
  return {
    id: `SES-${counter.sesi}`,
    nomor: `SK-${String(counter.sesi).padStart(5, '0')}`,
    toko_id: tokoId,
    status: 'BUKA',
    kasir: USER.name,
    gudang_id: gudangId,
    waktu_buka: buka.toISOString(),
    waktu_tutup: null,
    kas_awal: kasAwal,
    total_tunai: 0,
    total_transfer: 0,
    total_qris: 0,
    total_penjualan: 0,
    jumlah_transaksi: 0,
    kas_akhir_sistem: kasAwal,
    kas_akhir_fisik: null,
    selisih: null
  }
}

// ---------- Seed: 7 hari riwayat + sesi berjalan hari ini ----------

function seed() {
  catalogs = {
    'TOKO-1': { produk: buatProduk(), kategori: KATEGORI.map((k) => ({ ...k })) },
    'TOKO-2': { produk: buatProdukBakso(), kategori: KATEGORI_BAKSO.map((k) => ({ ...k })) },
    'TOKO-3': { produk: buatProdukLaundry(), kategori: KATEGORI_LAUNDRY.map((k) => ({ ...k })) }
  }
  pelanggan = PELANGGAN_AWAL.map((c) => ({ ...c }))
  sesiList = []
  transaksi = []
  counter = { trx: 0, sesi: 0, cust: pelanggan.length, order: 0, station: 0, bill: 0 }
  const rand = mulberry32(20260703)
  const pick = (arr) => arr[Math.floor(rand() * arr.length)]
  const metode = ['TUNAI', 'TUNAI', 'TUNAI', 'QRIS', 'QRIS', 'TRANSFER']

  // Qty realistis per jenis item: layanan kiloan 3-6 kg, retail 1-3, F&B 1-2
  const qtyUntuk = (p) => {
    if (p.satuan === 'Kg') return 3 + Math.floor(rand() * 4)
    if (p.kategori === 'Sembako' || p.kategori === 'Snack') return 1 + Math.floor(rand() * 3)
    return 1 + Math.floor(rand() * 2)
  }

  // Riwayat 7 hari + sesi hari ini BUKA — untuk SETIAP toko, dari katalognya
  for (const toko of TOKOS) {
    const daftarProduk = catalogs[toko.id].produk
    for (let hari = 7; hari >= 0; hari--) {
      const tglDasar = new Date()
      tglDasar.setDate(tglDasar.getDate() - hari)
      tglDasar.setHours(8, 0, 0, 0)

      const sesi = buatSesi({ tokoId: toko.id, buka: tglDasar, kasAwal: 500000, gudangId: 'GDG-1' })
      sesiList.unshift(sesi)

      const jumlahTrx = 4 + Math.floor(rand() * 5) // 4-8 transaksi per hari
      for (let n = 0; n < jumlahTrx; n++) {
        const jam = new Date(tglDasar)
        jam.setMinutes(60 + Math.floor(rand() * 690)) // 09:00 - 20:30
        const jumlahItem = 1 + Math.floor(rand() * 3)
        const items = []
        for (let i = 0; i < jumlahItem; i++) {
          const p = pick(daftarProduk)
          items.push(hitungItem(p, qtyUntuk(p), 0))
        }
        const tipe = pick(metode)
        const grand = round2(items.reduce((s, i) => s + i.subtotal, 0))
        const dibayar = tipe === 'TUNAI' ? Math.ceil(grand / 5000) * 5000 : grand
        const struk = buatStruk({
          tokoId: toko.id,
          items,
          tipePembayaran: tipe,
          dibayar,
          namaPelanggan: rand() < 0.3 ? pick(pelanggan).nama : null,
          tanggal: jam
        })
        transaksi.unshift(struk)
        tambahKeSesi(sesi, struk)
      }

      if (hari > 0) {
        // Tutup sesi hari-hari lalu; sesi hari ini (hari=0) dibiarkan BUKA
        const tutup = new Date(tglDasar)
        tutup.setHours(21, 0, 0, 0)
        const noise = [0, 0, 0, -5000, 2000][Math.floor(rand() * 5)]
        sesi.status = 'TUTUP'
        sesi.waktu_tutup = tutup.toISOString()
        sesi.kas_akhir_fisik = round2(sesi.kas_akhir_sistem + noise)
        sesi.selisih = round2(noise)
      }
    }
  }

  // Satu transaksi dibatalkan kemarin per toko agar riwayat punya contoh void
  for (const toko of TOKOS) {
    const kemarin = transaksi.find((t) =>
      t.toko_id === toko.id && isoDate(new Date(t.tanggal)) !== isoDate(new Date()))
    if (kemarin) kemarin.status = 'DIBATALKAN'
  }

  // ----- Seed pesanan hidup (papan KDS/Proses langsung terlihat bekerja) -----
  orders = []
  bills = []
  antrianCounter = {}

  // Warung bakso: beberapa meja dengan BON BERJALAN (open bill dine-in).
  // Tiap ronde jadi tiket dapur berlabel MEJA; bon dilunasi saat pelanggan pulang.
  const baksoProd = catalogs['TOKO-2'].produk
  const cariBakso = (kode) => baksoProd.find((p) => p.kode === kode)
  const seedBon = ({ mejaId, pax, menitLalu, dicetak = false, rondes }) => {
    const meja = TABLES.find((t) => t.id === mejaId)
    const bill = buatBon({ tokoId: 'TOKO-2', mejaIds: [mejaId], pax })
    bill.dibuka_at = new Date(Date.now() - menitLalu * 60000).toISOString()
    bills.push(bill)
    rondes.forEach((r, i) => {
      const bersih = r.items.map(({ kode, qty }) => {
        const p = cariBakso(kode)
        return { idProduk: p.id, nama: p.nama, kuantitas: qty, harga: p.harga_jual, satuan: p.satuan, catatan: null }
      })
      const order = tiketDapurBon(bill, bersih, i + 1)
      // Sebar umur tiket agar papan dapur terlihat wajar
      const dibuat = new Date(Date.now() - Math.max(1, menitLalu - i * 4) * 60000).toISOString()
      order.created_at = dibuat
      order.updated_at = dibuat
      order.stage = r.stage
      orders.push(order)
      bill.rounds.push({ ronde: i + 1, waktu: dibuat, order_id: order.id, items: bersih, sumber: 'KASIR' })
    })
    if (dicetak) { bill.bill_dicetak = true; bill.status = 'BILL' }
    bill.updated_at = new Date().toISOString()
  }
  seedBon({ mejaId: 'MEJA-1', pax: 3, menitLalu: 12, rondes: [{ stage: 'DIPROSES', items: [{ kode: 'MIE-002', qty: 2 }, { kode: 'MIN-001', qty: 2 }] }] })
  seedBon({ mejaId: 'MEJA-3', pax: 2, menitLalu: 4, rondes: [{ stage: 'ANTRIAN', items: [{ kode: 'BKS-002', qty: 1 }, { kode: 'MIN-002', qty: 1 }] }] })
  seedBon({ mejaId: 'MEJA-5', pax: 5, menitLalu: 26, dicetak: true, rondes: [
    { stage: 'READY', items: [{ kode: 'BKS-001', qty: 2 }, { kode: 'MIN-001', qty: 3 }] },
    { stage: 'ANTRIAN', items: [{ kode: 'BKS-004', qty: 1 }, { kode: 'TMB-001', qty: 2 }] }
  ] })

  // Laundry: nota tersebar di berbagai tahap
  // ----- Seed stasiun kerja per toko -----
  stations = [
    buatStasiun({ tokoId: 'TOKO-1', type: 'cashier', nama: 'Kasir 1' }),
    buatStasiun({ tokoId: 'TOKO-2', type: 'cashier', nama: 'Kasir 1' }),
    buatStasiun({ tokoId: 'TOKO-2', type: 'kitchen', nama: 'Dapur 1', kapasitas: 5 }),
    buatStasiun({ tokoId: 'TOKO-2', type: 'kitchen', nama: 'Dapur 2', status: 'ISTIRAHAT', kapasitas: 5 }),
    buatStasiun({ tokoId: 'TOKO-2', type: 'waiter', nama: 'Waiter A' }),
    buatStasiun({ tokoId: 'TOKO-3', type: 'cashier', nama: 'Penerimaan 1' }),
    buatStasiun({ tokoId: 'TOKO-3', type: 'washer', nama: 'Mesin Cuci 1', kapasitas: 8 }),
    buatStasiun({ tokoId: 'TOKO-3', type: 'washer', nama: 'Mesin Cuci 2', status: 'NONAKTIF', kapasitas: 8 }),
    buatStasiun({ tokoId: 'TOKO-3', type: 'dryer', nama: 'Pengering 1', kapasitas: 8 }),
    buatStasiun({ tokoId: 'TOKO-3', type: 'folder', nama: 'Meja Lipat 1' })
  ]

  const seedLaundry = [
    { items: [{ nama: 'Cuci Kering Lipat 4 kg', kuantitas: 1 }], total: 28000, menitLalu: 25, stage: 'ANTRIAN', pelangganNama: 'Budi Santoso' },
    { items: [{ nama: 'Cuci Kering Lipat 6 kg', kuantitas: 1 }, { nama: 'Bed Cover', kuantitas: 1 }], total: 67000, menitLalu: 95, stage: 'PENCUCIAN', pelangganNama: 'Siti Aminah' },
    { items: [{ nama: 'Cuci Setrika 3 kg (Express)', kuantitas: 1 }], total: 36000, menitLalu: 150, stage: 'PENGERINGAN', pelangganNama: 'Rudi Hartono' },
    { items: [{ nama: 'Cuci Kering Lipat 5 kg', kuantitas: 1 }], total: 35000, menitLalu: 240, stage: 'LIPAT', pelangganNama: 'Dewi Lestari' },
    { items: [{ nama: 'Selimut Besar', kuantitas: 2 }], total: 50000, menitLalu: 420, stage: 'SIAP_AMBIL', pelangganNama: 'Budi Santoso' }
  ]
  for (const o of seedLaundry) orders.push(buatOrder({ tokoId: 'TOKO-3', ...o }))
}

// ---------- Kontrol ----------

function isActive() {
  return active
}

function start() {
  seed()
  active = true
  return ok({
    user: USER,
    company: COMPANY,
    branch: BRANCH,
    permissions: ['pos.semua'],
    modules: { multi_satuan: false },
    payment_methods: ['TUNAI', 'TRANSFER', 'QRIS'],
    demo: true
  })
}

function stop() {
  active = false
}

// Status langganan demo (bentuk mengikuti §6.5 spec Mitra). Env
// IPOS_SMOKE_LANGGANAN=segera|grace|kedaluwarsa memaksa keadaan untuk uji tampilan.
const MODUL_AKTIF_DEMO = ['kasir', 'dapur', 'antrian', 'proses', 'meja', 'riwayat', 'sesi', 'stasiun', 'laporan', 'produk', 'pelanggan']
function demoLangganan() {
  const base = {
    plan_kode: 'TULEH_PRO', plan_nama: 'Tuléh Pro', periode_mulai: '2026-07-01',
    modul_aktif: MODUL_AKTIF_DEMO, perpanjang_url: 'https://tatreport.com/langganan'
  }
  switch (process.env.IPOS_SMOKE_LANGGANAN) {
    case 'kedaluwarsa': return { ...base, status: 'KEDALUWARSA', periode_akhir: '2026-07-18', sisa_hari: 0 }
    case 'grace': return { ...base, status: 'GRACE', periode_akhir: '2026-07-20', sisa_hari: 0 }
    case 'segera': return { ...base, status: 'AKTIF', periode_akhir: '2026-07-27', sisa_hari: 5 }
    default: return { ...base, status: 'AKTIF', periode_akhir: '2026-08-12', sisa_hari: 21 }
  }
}

// ---------- Handler per channel IPC ----------

const handlers = {
  'net:ping': () => ok({ app: 'Tuléh Demo', version: 'demo', time: new Date().toISOString() }),

  'langganan:status': () => ok(demoLangganan()),

  'cs:kontak': () => ok({
    sumber: 'CS_MITRA',
    nama: 'Mitra Taufiq (Demo)',
    wa_link: 'https://wa.me/6281234567890'
  }),

  'auth:hasToken': () => ok({ hasToken: true }),

  'auth:me': () => ok({ user: USER, company: COMPANY, branch: BRANCH, sesi_aktif: sesiAktif() }),

  'auth:logout': () => {
    stop()
    return ok(null)
  },

  'toko:list': () => ok(TOKOS),

  'toko:manifest': ({ id } = {}) => {
    const manifest = MANIFESTS[id]
    return manifest ? ok(manifest) : err(404, 'Manifest toko tidak ditemukan.')
  },

  'toko:select': ({ id } = {}) => {
    if (!MANIFESTS[id]) return err(404, 'Toko tidak ditemukan.')
    activeTokoId = id
    return ok({ selected: id })
  },

  // ---------- Stasiun kerja ----------

  'station:list': () => ok(stations.filter((s) => s.toko_id === activeTokoId)),

  'station:create': ({ type, nama, kapasitas } = {}) => {
    const manifest = MANIFESTS[activeTokoId]
    const jenisSah = (manifest?.station_types || []).map((t) => t.type)
    if (!jenisSah.includes(type)) return err(422, 'Jenis stasiun tidak dikenal untuk toko ini.')
    if (!nama || !String(nama).trim()) return err(422, 'Nama stasiun wajib diisi.')
    const kap = kapasitas === undefined || kapasitas === null || kapasitas === '' ? null : Number(kapasitas)
    if (kap !== null && (!Number.isFinite(kap) || kap < 1)) return err(422, 'Kapasitas tidak valid.')
    const baru = buatStasiun({ tokoId: activeTokoId, type, nama: String(nama).trim(), kapasitas: kap })
    stations.push(baru)
    return ok(baru)
  },

  'station:update': ({ id, nama, status, kapasitas } = {}) => {
    const st = stations.find((s) => s.id === id && s.toko_id === activeTokoId)
    if (!st) return err(404, 'Stasiun tidak ditemukan.')
    if (status !== undefined) {
      if (!STATUS_STASIUN.includes(status)) return err(422, 'Status stasiun tidak valid.')
      st.status = status
    }
    if (nama !== undefined && String(nama).trim()) st.nama = String(nama).trim()
    if (kapasitas !== undefined) {
      const kap = kapasitas === null || kapasitas === '' ? null : Number(kapasitas)
      if (kap !== null && (!Number.isFinite(kap) || kap < 1)) return err(422, 'Kapasitas tidak valid.')
      st.kapasitas = kap
    }
    return ok(st)
  },

  'station:delete': ({ id } = {}) => {
    const idx = stations.findIndex((s) => s.id === id && s.toko_id === activeTokoId)
    if (idx === -1) return err(404, 'Stasiun tidak ditemukan.')
    const [dihapus] = stations.splice(idx, 1)
    return ok(dihapus)
  },

  'table:list': () => ok(TABLES.filter((t) => t.toko_id === activeTokoId)),

  // ---------- Bon Meja (open bill dine-in) ----------

  // Peta meja: setiap meja toko aktif + ringkasan bon berjalannya (null = kosong)
  'bill:peta': () => {
    const daftar = TABLES.filter((t) => t.toko_id === activeTokoId).map((t) => {
      const bill = bonUntukMeja(t.id)
      return { id: t.id, nomor: t.nomor, kode: t.kode, bill: bill ? bonRingkas(bill) : null }
    })
    return ok({ tables: daftar })
  },

  // Buka bon baru untuk meja kosong
  'bill:buka': ({ mejaId, pax } = {}) => {
    const meja = TABLES.find((t) => t.id === mejaId && t.toko_id === activeTokoId)
    if (!meja) return err(404, 'Meja tidak ditemukan.')
    if (bonUntukMeja(mejaId)) return err(409, 'Meja ini sudah terisi.')
    const bill = buatBon({ tokoId: activeTokoId, mejaIds: [mejaId], pax })
    bills.push(bill)
    return ok(bonRingkas(bill))
  },

  'bill:detail': ({ id } = {}) => {
    const bill = bills.find((b) => b.id === id && bonMejaAktif(b))
    if (!bill) return err(404, 'Bon tidak ditemukan.')
    return ok(bonRingkas(bill))
  },

  // Tambah ronde pesanan ke bon → tiket dapur baru berlabel MEJA
  'bill:tambahRonde': ({ id, items, catatan } = {}) => {
    const bill = bills.find((b) => b.id === id && bonMejaAktif(b))
    if (!bill) return err(404, 'Bon tidak ditemukan.')
    if (!Array.isArray(items) || items.length === 0) return err(422, 'Belum ada item pesanan.')

    const bersih = []
    for (const item of items) {
      const p = produkToko(bill.toko_id).find((x) => x.id === item.idProduk)
      if (!p) return err(422, 'Item tidak ditemukan di katalog.')
      const qty = Number(item.kuantitas)
      if (!Number.isFinite(qty) || qty <= 0) return err(422, `Kuantitas "${p.nama}" tidak valid.`)
      bersih.push({
        idProduk: p.id, nama: p.nama, kuantitas: qty, harga: p.harga_jual, satuan: p.satuan,
        catatan: item.catatan ? String(item.catatan).slice(0, 120) : null
      })
    }

    const ronde = bill.rounds.length + 1
    const order = tiketDapurBon(bill, bersih, ronde)
    orders.push(order)
    bill.rounds.push({ ronde, waktu: new Date().toISOString(), order_id: order.id, items: bersih, sumber: 'KASIR' })
    if (catatan) bill.catatan = String(catatan).slice(0, 300)
    // Pesanan bertambah setelah pra-bon dicetak → pra-bon lama tak berlaku
    if (bill.status === 'BILL') { bill.status = 'BUKA'; bill.bill_dicetak = false }
    bill.updated_at = new Date().toISOString()
    return ok({ bill: bonRingkas(bill), order })
  },

  // Ubah jumlah tamu (pax)
  'bill:setPax': ({ id, pax } = {}) => {
    const bill = bills.find((b) => b.id === id && bonMejaAktif(b))
    if (!bill) return err(404, 'Bon tidak ditemukan.')
    bill.pax = Math.max(1, Math.min(Number(pax) || 1, 99))
    bill.updated_at = new Date().toISOString()
    return ok(bonRingkas(bill))
  },

  // Cetak pra-bon (hitungan, BELUM dibayar) — tidak menyentuh sesi/transaksi
  'bill:cetak': ({ id } = {}) => {
    const bill = bills.find((b) => b.id === id && bonMejaAktif(b))
    if (!bill) return err(404, 'Bon tidak ditemukan.')
    const items = bonItems(bill)
    if (items.length === 0) return err(422, 'Bon masih kosong.')
    bill.bill_dicetak = true
    bill.status = 'BILL'
    bill.updated_at = new Date().toISOString()
    const total = bonTotal(bill)
    const prabon = {
      id: bill.id,
      nomor: bill.nomor,
      tanggal: new Date().toISOString(),
      status: 'BELUM DIBAYAR',
      pelanggan: bill.pelanggan,
      kasir: USER.name,
      meja: bonLabel(bill),
      pax: bill.pax,
      tipe_pembayaran: 'BON — BELUM DIBAYAR',
      subtotal: total,
      total_diskon: 0,
      total_pajak: 0,
      grand_total: total,
      dibayar: 0,
      kembalian: 0,
      items: items.map((it) => ({
        nama: it.nama, kuantitas: it.kuantitas, satuan: it.satuan, harga: it.harga,
        diskon_persen: 0, pajak_persen: 0, subtotal: round2(it.harga * it.kuantitas)
      }))
    }
    return ok({ bill: bonRingkas(bill), prabon })
  },

  // Lunasi bon → terbitkan struk, catat ke sesi, tutup meja (jadi kosong)
  'bill:bayar': ({ id, tipePembayaran = 'TUNAI', dibayar } = {}) => {
    const bill = bills.find((b) => b.id === id && bonMejaAktif(b))
    if (!bill) return err(404, 'Bon tidak ditemukan.')
    const sesi = sesiAktif(bill.toko_id)
    if (!sesi) return err(409, 'Belum ada sesi kasir terbuka.')
    const agregat = bonItems(bill)
    if (agregat.length === 0) return err(422, 'Bon masih kosong.')

    const strukItems = agregat.map((it) => {
      const p = produkToko(bill.toko_id).find((x) => x.id === it.idProduk)
      return hitungItem(p || { nama: it.nama, harga_jual: it.harga, pajak_persen: 0, satuan: it.satuan }, it.kuantitas, 0)
    })
    const grand = round2(strukItems.reduce((s, i) => s + i.subtotal, 0))
    const bayar = dibayar === undefined || dibayar === null || dibayar === '' ? grand : Number(dibayar)
    if (!Number.isFinite(bayar) || bayar < grand) return err(422, 'Jumlah dibayar kurang dari total tagihan.')

    // Penjualan tetap mengurangi stok barang ber-kelola-stok (sama seperti
    // trx:checkout) — konsumsi dicatat saat bon dilunasi. Tidak memblokir bila
    // stok minus: makanan sudah disajikan, oversell hanya jadi sinyal.
    for (const it of agregat) {
      const p = produkToko(bill.toko_id).find((x) => x.id === it.idProduk)
      if (p && p.kelola_stok) p.stok = round2(Math.max(0, p.stok - it.kuantitas))
    }

    const struk = buatStruk({
      tokoId: bill.toko_id,
      items: strukItems,
      tipePembayaran,
      dibayar: bayar,
      namaPelanggan: bill.pelanggan,
      tanggal: new Date()
    })
    struk.meja = bonLabel(bill)
    transaksi = [struk, ...transaksi]
    tambahKeSesi(sesi, struk)

    // Tutup bon + bebaskan meja; selesaikan tiket dapur yang masih berjalan
    const terminal = lifecycleStates(bill.toko_id).slice(-1)[0]
    for (const r of bill.rounds) {
      const o = orders.find((x) => x.id === r.order_id)
      if (!o) continue
      if (o.stage !== terminal) { o.stage = terminal; o.updated_at = new Date().toISOString() }
      o.bayar = 'LUNAS'
    }
    bill.status = 'LUNAS'
    bill.meja_ids = []
    bill.updated_at = new Date().toISOString()
    return ok({ struk })
  },

  // Gabung dua bon → satu tagihan (rombongan lintas meja)
  'bill:gabung': ({ idUtama, idGabung } = {}) => {
    if (!idUtama || !idGabung || idUtama === idGabung) return err(422, 'Pilih dua meja berbeda.')
    const utama = bills.find((b) => b.id === idUtama && bonMejaAktif(b))
    const lain = bills.find((b) => b.id === idGabung && bonMejaAktif(b))
    if (!utama || !lain) return err(404, 'Bon tidak ditemukan.')
    if (utama.toko_id !== lain.toko_id) return err(422, 'Meja beda toko tidak bisa digabung.')

    utama.meja_ids = [...utama.meja_ids, ...lain.meja_ids]
    utama.pax = Math.min(99, utama.pax + lain.pax)
    const offset = utama.rounds.length
    lain.rounds.forEach((r, i) => utama.rounds.push({ ...r, ronde: offset + i + 1 }))
    if (utama.status === 'BILL') { utama.status = 'BUKA'; utama.bill_dicetak = false }
    utama.updated_at = new Date().toISOString()

    // Semua tiket dapur ikut label meja gabungan
    const gabLabel = bonLabel(utama)
    for (const r of utama.rounds) {
      const o = orders.find((x) => x.id === r.order_id)
      if (o) { o.meja = gabLabel; o.bill_id = utama.id }
    }
    lain.status = 'GABUNG'
    lain.meja_ids = []
    lain.rounds = []
    lain.updated_at = new Date().toISOString()
    return ok(bonRingkas(utama))
  },

  // Batalkan bon (bebaskan meja tanpa pembayaran) — koreksi/reset
  'bill:batal': ({ id } = {}) => {
    const bill = bills.find((b) => b.id === id && bonMejaAktif(b))
    if (!bill) return err(404, 'Bon tidak ditemukan.')
    const terminal = lifecycleStates(bill.toko_id).slice(-1)[0]
    for (const r of bill.rounds) {
      const o = orders.find((x) => x.id === r.order_id)
      if (o && o.stage !== terminal) { o.stage = terminal; o.updated_at = new Date().toISOString() }
    }
    const dibebaskan = [...bill.meja_ids]
    bill.status = 'BATAL'
    bill.meja_ids = []
    bill.updated_at = new Date().toISOString()
    return ok({ dibebaskan })
  },

  // Konfirmasi pembayaran order QR meja (kasir): terbitkan struk + nomor
  // antrian, lalu dorong ke tahap pertama lifecycle (masuk dapur).
  'order:konfirmasiBayar': ({ id, tipePembayaran = 'TUNAI' } = {}) => {
    const order = orders.find((o) => o.id === id)
    if (!order) return err(404, 'Pesanan tidak ditemukan.')
    if (order.stage !== 'MENUNGGU_BAYAR') return err(409, 'Pesanan ini tidak sedang menunggu pembayaran.')
    const sesi = sesiAktif()
    if (!sesi) return err(409, 'Belum ada sesi kasir terbuka.')

    const strukItems = order.items.map((item) => {
      const p = produkToko(order.toko_id).find((x) => x.id === item.idProduk)
      return hitungItem(p || { nama: item.nama, harga_jual: item.harga, pajak_persen: 0, satuan: null }, item.kuantitas, 0)
    })
    const struk = buatStruk({
      tokoId: order.toko_id,
      items: strukItems,
      tipePembayaran,
      namaPelanggan: order.pelanggan,
      tanggal: new Date()
    })
    order.stage = lifecycleStates(order.toko_id)[0] || 'ANTRIAN'
    order.no_antrian = nomorAntrianBerikut(order.toko_id)
    order.bayar = 'LUNAS'
    order.updated_at = new Date().toISOString()
    struk.no_antrian = order.no_antrian
    struk.token_lacak = order.token_lacak
    transaksi = [struk, ...transaksi]
    tambahKeSesi(sesi, struk)
    return ok(order)
  },

  // Nota "bayar saat ambil" (laundry): masuk papan proses TANPA struk;
  // struk terbit saat pelunasan (order:lunasi) di tahap penyerahan.
  'order:simpanNota': ({ items, idPelanggan, catatan } = {}) => {
    const manifest = MANIFESTS[activeTokoId]
    if (!(manifest?.transaction_flow || []).includes('PAYMENT_OR_LATER')) {
      return err(422, 'Toko ini tidak mendukung bayar saat ambil.')
    }
    if (!sesiAktif()) return err(409, 'Belum ada sesi kasir terbuka.')
    if (!Array.isArray(items) || items.length === 0) return err(422, 'Keranjang masih kosong.')

    const bersih = []
    let total = 0
    for (const item of items) {
      const p = produkAktif().find((x) => x.id === item.idProduk)
      if (!p) return err(422, 'Item tidak ditemukan di katalog.')
      const qty = Number(item.kuantitas)
      if (!Number.isFinite(qty) || qty <= 0) return err(422, `Kuantitas "${p.nama}" tidak valid.`)
      bersih.push({ idProduk: p.id, nama: p.nama, kuantitas: qty, harga: p.harga_jual, satuan: p.satuan })
      total = round2(total + p.harga_jual * qty)
    }

    const cust = idPelanggan ? pelanggan.find((c) => c.id === idPelanggan) : null
    const order = buatOrder({
      tokoId: activeTokoId,
      items: bersih,
      total,
      pelangganNama: cust ? cust.nama : null
    })
    order.bayar = 'BELUM'
    if (catatan) order.catatan = String(catatan).slice(0, 300)
    orders.push(order)

    // Nota tanda terima (bentuk struk agar bisa dicetak) — belum lunas
    const nota = {
      id: order.id,
      nomor: order.nomor,
      tanggal: order.created_at,
      status: 'BELUM LUNAS',
      pelanggan: order.pelanggan,
      kasir: USER.name,
      tipe_pembayaran: 'BAYAR SAAT AMBIL',
      subtotal: total,
      total_diskon: 0,
      total_pajak: 0,
      grand_total: total,
      dibayar: 0,
      kembalian: 0,
      no_antrian: order.no_antrian,
      token_lacak: order.token_lacak,
      items: bersih.map((i) => ({
        nama: i.nama, kuantitas: i.kuantitas, satuan: i.satuan,
        harga: i.harga, diskon_persen: 0, pajak_persen: 0,
        subtotal: round2(i.harga * i.kuantitas)
      }))
    }
    return ok({ order, nota })
  },

  // Pelunasan nota bayar-saat-ambil: terbitkan struk + selesaikan order
  'order:lunasi': ({ id, tipePembayaran = 'TUNAI' } = {}) => {
    const order = orders.find((o) => o.id === id)
    if (!order) return err(404, 'Pesanan tidak ditemukan.')
    if (order.bayar !== 'BELUM') return err(409, 'Pesanan ini sudah lunas.')
    const sesi = sesiAktif(order.toko_id)
    if (!sesi) return err(409, 'Belum ada sesi kasir terbuka.')

    const strukItems = order.items.map((item) => {
      const p = produkToko(order.toko_id).find((x) => x.id === item.idProduk)
      return hitungItem(p || { nama: item.nama, harga_jual: item.harga, pajak_persen: 0, satuan: item.satuan }, item.kuantitas, 0)
    })
    const struk = buatStruk({
      tokoId: order.toko_id,
      items: strukItems,
      tipePembayaran,
      namaPelanggan: order.pelanggan,
      tanggal: new Date()
    })
    struk.no_antrian = order.no_antrian
    struk.token_lacak = order.token_lacak
    transaksi = [struk, ...transaksi]
    tambahKeSesi(sesi, struk)

    order.bayar = 'LUNAS'
    const states = lifecycleStates(order.toko_id)
    order.stage = states[states.length - 1] // SELESAI/diserahkan
    order.updated_at = new Date().toISOString()
    return ok({ order, struk })
  },

  // ---------- Pesanan hidup (KDS / Papan Proses) ----------

  'order:list': ({ stage } = {}) => {
    const states = lifecycleStates(activeTokoId)
    const terminal = states[states.length - 1]
    let rows = orders.filter((o) => o.toko_id === activeTokoId)
    rows = stage ? rows.filter((o) => o.stage === stage) : rows.filter((o) => o.stage !== terminal)
    rows = [...rows].sort((a, b) => a.created_at.localeCompare(b.created_at))
    return ok(rows)
  },

  'order:transition': ({ id, to } = {}) => {
    const order = orders.find((o) => o.id === id)
    if (!order) return err(404, 'Pesanan tidak ditemukan.')
    const states = lifecycleStates(order.toko_id)
    const idx = states.indexOf(order.stage)
    if (idx === -1 || idx === states.length - 1) return err(409, 'Pesanan sudah selesai.')
    const next = states[idx + 1]
    if (to && to !== next) {
      return err(409, `Transisi tidak valid: ${order.stage} → ${to}. Berikutnya harus ${next}.`)
    }
    order.stage = next
    order.updated_at = new Date().toISOString()
    return ok(order)
  },

  'config:get': () => ok({
    company: COMPANY,
    pengaturan: { stok_minimum_tampil: 0, tampilkan_stok_habis: true },
    payment_methods: ['TUNAI', 'TRANSFER', 'QRIS'],
    modules: { multi_satuan: false }
  }),

  'produk:list': ({ q, kategoriId, perPage = 50, page = 1 } = {}) => {
    let rows = produkAktif()
    if (kategoriId) {
      const kat = kategoriToko(activeTokoId).find((k) => k.id === kategoriId)
      if (kat) rows = rows.filter((p) => p.kategori === kat.nama)
    }
    if (q) {
      const needle = String(q).toLowerCase()
      rows = rows.filter((p) =>
        p.nama.toLowerCase().includes(needle) ||
        p.kode.toLowerCase().includes(needle) ||
        (p.barcode || '').includes(needle))
    }
    const size = Math.min(Number(perPage) || 50, 100)
    const halaman = Math.max(Number(page) || 1, 1)
    const mulai = (halaman - 1) * size
    return ok(rows.slice(mulai, mulai + size), {
      current_page: halaman,
      last_page: Math.max(Math.ceil(rows.length / size), 1),
      per_page: size,
      total: rows.length
    })
  },

  'produk:barcode': ({ barcode } = {}) => {
    const p = produkAktif().find((x) => x.barcode === String(barcode))
    return p ? ok(p) : err(404, 'Produk dengan barcode tersebut tidak ditemukan.')
  },

  'produk:detail': ({ id } = {}) => {
    const p = produkAktif().find((x) => x.id === id)
    return p ? ok(p) : err(404, 'Produk tidak ditemukan.')
  },

  'master:kategori': () => ok(kategoriToko(activeTokoId)),
  'master:gudang': () => ok(GUDANG),
  'master:satuan': () => ok(SATUAN),

  'pelanggan:list': ({ q } = {}) => {
    if (!q) return ok(pelanggan)
    const needle = String(q).toLowerCase()
    return ok(pelanggan.filter((c) =>
      c.nama.toLowerCase().includes(needle) || (c.telepon || '').includes(needle)))
  },

  'pelanggan:create': ({ nama, telepon } = {}) => {
    if (!nama || !String(nama).trim()) return err(422, 'Nama pelanggan wajib diisi.')
    counter.cust += 1
    const baru = {
      id: `CUST-${counter.cust}`,
      kode: `PLG-${String(counter.cust).padStart(3, '0')}`,
      nama: String(nama).trim(),
      telepon: telepon ? String(telepon) : null
    }
    pelanggan = [baru, ...pelanggan]
    return ok(baru)
  },

  'pelanggan:detail': ({ id } = {}) => {
    const c = pelanggan.find((x) => x.id === id)
    return c ? ok(c) : err(404, 'Pelanggan tidak ditemukan.')
  },

  'sesi:aktif': () => ok(sesiAktif()),

  'sesi:list': ({ tanggalDari, tanggalSampai } = {}) => {
    let rows = sesiList.filter((s) => s.toko_id === activeTokoId)
    if (tanggalDari) rows = rows.filter((s) => isoDate(new Date(s.waktu_buka)) >= tanggalDari)
    if (tanggalSampai) rows = rows.filter((s) => isoDate(new Date(s.waktu_buka)) <= tanggalSampai)
    return ok(rows.map((s) => ({
      id: s.id,
      nomor: s.nomor,
      status: s.status,
      waktu_buka: s.waktu_buka,
      waktu_tutup: s.waktu_tutup,
      kasir: s.kasir
    })))
  },

  'sesi:buka': ({ gudangId, kasAwal } = {}) => {
    if (sesiAktif()) return err(409, 'Masih ada sesi kasir yang terbuka.')
    const kas = Number(kasAwal)
    if (!gudangId) return err(422, 'Gudang wajib dipilih.')
    if (!Number.isFinite(kas) || kas < 0) return err(422, 'Kas awal tidak valid.')
    const sesi = buatSesi({ tokoId: activeTokoId, buka: new Date(), kasAwal: kas, gudangId })
    sesiList = [sesi, ...sesiList]
    return ok(sesi)
  },

  'sesi:tutup': ({ id, kasAkhirFisik } = {}) => {
    const sesi = sesiList.find((s) => s.id === id)
    if (!sesi) return err(404, 'Sesi tidak ditemukan.')
    if (sesi.status === 'TUTUP') return err(409, 'Sesi sudah ditutup.')
    const fisik = Number(kasAkhirFisik)
    if (!Number.isFinite(fisik)) return err(422, 'Kas akhir fisik tidak valid.')
    sesi.status = 'TUTUP'
    sesi.waktu_tutup = new Date().toISOString()
    sesi.kas_akhir_fisik = round2(fisik)
    sesi.selisih = round2(fisik - sesi.kas_akhir_sistem)
    return ok(sesi)
  },

  'sesi:rekap': ({ id } = {}) => {
    const sesi = sesiList.find((s) => s.id === id)
    return sesi ? ok(sesi) : err(404, 'Sesi tidak ditemukan.')
  },

  'trx:checkout': ({ items, tipePembayaran, dibayar, idPelanggan, catatan } = {}) => {
    const sesi = sesiAktif()
    if (!sesi) return err(409, 'Belum ada sesi kasir terbuka.')
    if (!Array.isArray(items) || items.length === 0) return err(422, 'Keranjang masih kosong.')

    const rincian = []
    for (const item of items) {
      const p = produkAktif().find((x) => x.id === item.idProduk)
      if (!p) return err(422, 'Produk tidak ditemukan di katalog demo.')
      const qty = Number(item.kuantitas)
      if (!Number.isFinite(qty) || qty <= 0) return err(422, `Kuantitas "${p.nama}" tidak valid.`)
      if (p.kelola_stok && qty > p.stok) return err(422, `Stok "${p.nama}" hanya tersisa ${p.stok}.`)
      rincian.push({ p, qty, diskon: Number(item.diskonPersen) || 0 })
    }

    const strukItems = rincian.map(({ p, qty, diskon }) => hitungItem(p, qty, diskon))
    const grand = round2(strukItems.reduce((s, i) => s + i.subtotal, 0))
    const bayar = Number(dibayar)
    if (!Number.isFinite(bayar) || bayar < grand) return err(422, 'Jumlah dibayar kurang dari total tagihan.')

    for (const { p, qty } of rincian) {
      if (p.kelola_stok) p.stok = round2(p.stok - qty)
    }

    const cust = idPelanggan ? pelanggan.find((c) => c.id === idPelanggan) : null
    const struk = buatStruk({
      tokoId: activeTokoId,
      items: strukItems,
      tipePembayaran: tipePembayaran || 'TUNAI',
      dibayar: bayar,
      namaPelanggan: cust ? cust.nama : null,
      tanggal: new Date()
    })
    if (catatan) struk.catatan = String(catatan)

    // POS universal: toko ber-lifecycle (bakso/laundry) → checkout juga
    // menerbitkan PESANAN dengan nomor antrian yang masuk papan KDS/Proses.
    if (pakaiAntrian(activeTokoId)) {
      const order = buatOrder({
        tokoId: activeTokoId,
        items: strukItems.map((i) => ({ nama: i.nama, kuantitas: i.kuantitas })),
        total: grand,
        pelangganNama: cust ? cust.nama : null
      })
      orders.push(order)
      struk.no_antrian = order.no_antrian
      struk.token_lacak = order.token_lacak
    }

    transaksi = [struk, ...transaksi]
    tambahKeSesi(sesi, struk)
    return { ...ok(struk), status: 201 }
  },

  'trx:list': ({ status, tanggalDari, tanggalSampai } = {}) => {
    let rows = transaksi.filter((t) => t.toko_id === activeTokoId)
    if (status) rows = rows.filter((t) => t.status === status)
    if (tanggalDari) rows = rows.filter((t) => isoDate(new Date(t.tanggal)) >= tanggalDari)
    if (tanggalSampai) rows = rows.filter((t) => isoDate(new Date(t.tanggal)) <= tanggalSampai)
    return ok(rows.map((t) => ({
      id: t.id,
      nomor: t.nomor,
      tanggal: t.tanggal,
      grand_total: t.grand_total,
      tipe_pembayaran: t.tipe_pembayaran,
      status: t.status
    })))
  },

  'trx:detail': ({ id } = {}) => {
    const t = transaksi.find((x) => x.id === id)
    return t ? ok(t) : err(404, 'Transaksi tidak ditemukan.')
  },

  'trx:batal': ({ id } = {}) => {
    const t = transaksi.find((x) => x.id === id)
    if (!t) return err(404, 'Transaksi tidak ditemukan.')
    if (t.status === 'DIBATALKAN') return err(409, 'Transaksi sudah dibatalkan.')
    t.status = 'DIBATALKAN'
    // Kembalikan stok produk kelola-stok (pada katalog toko transaksi itu)
    for (const item of t.items) {
      const p = produkToko(t.toko_id).find((x) => x.nama === item.nama)
      if (p && p.kelola_stok) p.stok = round2(p.stok + Number(item.kuantitas))
    }
    const sesi = sesiList.find((s) =>
      s.toko_id === t.toko_id && isoDate(new Date(s.waktu_buka)) === isoDate(new Date(t.tanggal)))
    if (sesi) kurangiDariSesi(sesi, t)
    return ok(t)
  },

  'laporan:penjualanHarian': ({ tanggalDari, tanggalSampai } = {}) => {
    const perHari = new Map()
    for (const t of transaksi) {
      if (t.toko_id !== activeTokoId || t.status !== 'SELESAI') continue
      const tgl = isoDate(new Date(t.tanggal))
      if (tanggalDari && tgl < tanggalDari) continue
      if (tanggalSampai && tgl > tanggalSampai) continue
      const row = perHari.get(tgl) || { tanggal: tgl, jumlah_transaksi: 0, total_omzet: 0 }
      row.jumlah_transaksi += 1
      row.total_omzet = round2(row.total_omzet + t.grand_total)
      perHari.set(tgl, row)
    }
    const rows = [...perHari.values()].sort((a, b) => a.tanggal.localeCompare(b.tanggal))
    const totalOmzet = round2(rows.reduce((s, r) => s + r.total_omzet, 0))
    const totalTrx = rows.reduce((s, r) => s + r.jumlah_transaksi, 0)
    return ok({
      rows,
      total: {
        jumlah_transaksi: totalTrx,
        total_omzet: totalOmzet,
        rata_rata: totalTrx > 0 ? round2(totalOmzet / totalTrx) : 0
      }
    })
  },

  'laporan:penjualanProduk': ({ tanggalDari, tanggalSampai } = {}) => {
    const perProduk = new Map()
    for (const t of transaksi) {
      if (t.toko_id !== activeTokoId || t.status !== 'SELESAI') continue
      const tgl = isoDate(new Date(t.tanggal))
      if (tanggalDari && tgl < tanggalDari) continue
      if (tanggalSampai && tgl > tanggalSampai) continue
      for (const item of t.items) {
        const row = perProduk.get(item.nama) || { produk: item.nama, qty_terjual: 0, total_nilai: 0 }
        row.qty_terjual = round2(row.qty_terjual + Number(item.kuantitas))
        row.total_nilai = round2(row.total_nilai + Number(item.subtotal))
        perProduk.set(item.nama, row)
      }
    }
    return ok([...perProduk.values()].sort((a, b) => b.total_nilai - a.total_nilai))
  },

  'laporan:stok': () => ok(
    produkAktif()
      .filter((p) => p.kelola_stok)
      .map((p) => ({ id: p.id, kode: p.kode, produk: p.nama, stok: p.stok }))
  ),

  'laporan:rekapKasir': ({ tanggalDari, tanggalSampai } = {}) => {
    let rows = sesiList.filter((s) => s.toko_id === activeTokoId)
    if (tanggalDari) rows = rows.filter((s) => isoDate(new Date(s.waktu_buka)) >= tanggalDari)
    if (tanggalSampai) rows = rows.filter((s) => isoDate(new Date(s.waktu_buka)) <= tanggalSampai)
    return ok(rows)
  }
}

/** Info menu untuk halaman pemesanan QR meja (tracker.js). Null bila tak sah. */
function menuInfo(kodeMeja) {
  if (!active || !kodeMeja) return null
  const meja = TABLES.find((t) => t.kode === kodeMeja)
  if (!meja) return null
  const manifest = MANIFESTS[meja.toko_id]
  if (!manifest || !manifest.capabilities.includes('tables_qr')) return null
  const toko = TOKOS.find((t) => t.id === meja.toko_id)
  return {
    tokoNama: toko ? toko.nama : COMPANY.nama,
    mejaNomor: meja.nomor,
    products: produkToko(meja.toko_id).map((p) => ({ id: p.id, nama: p.nama, harga: p.harga_jual, kategori: p.kategori }))
  }
}

/**
 * Buat order dari HP pelanggan (QR meja).
 * - Toko OPEN_BILL (warung dine-in): pesanan menempel ke BON MEJA berjalan
 *   (dibuka otomatis bila belum ada) dan langsung masuk dapur; bayar di akhir.
 * - Toko lain: perilaku lama → order MENUNGGU_BAYAR, dikonfirmasi kasir.
 */
function createTableOrder(kodeMeja, { nama, catatan, items } = {}) {
  const info = menuInfo(kodeMeja)
  if (!info) return { ok: false, message: 'Meja tidak dikenal.' }
  const meja = TABLES.find((t) => t.kode === kodeMeja)

  const bersih = []
  let total = 0
  for (const item of items || []) {
    const p = produkToko(meja.toko_id).find((x) => x.id === item.idProduk)
    const qty = Math.min(Math.max(Number(item.qty) || 0, 0), 20)
    if (!p || qty <= 0) continue
    bersih.push({ idProduk: p.id, nama: p.nama, kuantitas: qty, harga: p.harga_jual, satuan: p.satuan, catatan: null })
    total += p.harga_jual * qty
  }
  if (bersih.length === 0) return { ok: false, message: 'Pilih minimal satu menu.' }

  const manifest = MANIFESTS[meja.toko_id]
  const openBill = (manifest?.transaction_flow || []).includes('OPEN_BILL')

  if (openBill) {
    let bill = bonUntukMeja(meja.id)
    if (!bill) {
      bill = buatBon({
        tokoId: meja.toko_id,
        mejaIds: [meja.id],
        pax: 1,
        pelangganNama: nama ? String(nama).slice(0, 60) : null
      })
      bills.push(bill)
    }
    const ronde = bill.rounds.length + 1
    const order = tiketDapurBon(bill, bersih, ronde)
    if (catatan) order.catatan = String(catatan).slice(0, 300)
    orders.push(order)
    bill.rounds.push({ ronde, waktu: new Date().toISOString(), order_id: order.id, items: bersih, sumber: 'QR' })
    if (bill.status === 'BILL') { bill.status = 'BUKA'; bill.bill_dicetak = false }
    bill.updated_at = new Date().toISOString()
    return { ok: true, order, tokoNama: info.tokoNama }
  }

  const order = buatOrder({
    tokoId: meja.toko_id,
    items: bersih,
    total,
    pelangganNama: `${String(nama || 'Tanpa nama').slice(0, 60)} · Meja ${meja.nomor}`,
    stage: 'MENUNGGU_BAYAR',
    tanpaAntrian: true
  })
  order.bayar = 'BELUM'
  if (catatan) order.catatan = String(catatan).slice(0, 300)
  orders.push(order)
  return { ok: true, order, tokoNama: info.tokoNama }
}

/** Data papan antrian publik (layar TV) untuk toko aktif. */
function queueBoardInfo() {
  if (!active) return null
  const states = lifecycleStates(activeTokoId)
  if (states.length < 2) return null
  const toko = TOKOS.find((t) => t.id === activeTokoId)
  const terminal = states[states.length - 1]
  // Papan menampilkan nomor antrian ATAU nomor meja — pesanan bon dine-in
  // tidak bernomor antrian (identitasnya meja) tetapi tetap tampil di TV.
  const rows = orders
    .filter((o) => o.toko_id === activeTokoId && o.stage !== terminal &&
      o.stage !== 'MENUNGGU_BAYAR' && (o.no_antrian || o.meja))
    .map((o) => ({ label: o.no_antrian || o.meja, no_antrian: o.no_antrian, stage: o.stage, meja: !o.no_antrian }))
  return {
    tokoNama: toko ? toko.nama : COMPANY.nama,
    states: states.slice(0, -1),
    labels: STAGE_LABELS,
    rows
  }
}

/** Data untuk halaman pelacakan pelanggan (tracker.js). Null bila tak ada. */
function trackingInfo(token) {
  if (!active || !token) return null
  const order = orders.find((o) => o.token_lacak === token)
  if (!order) return null
  const toko = TOKOS.find((t) => t.id === order.toko_id)
  return {
    order,
    states: lifecycleStates(order.toko_id),
    labels: STAGE_LABELS,
    tokoNama: toko ? toko.nama : COMPANY.nama
  }
}

module.exports = { isActive, start, stop, handlers, trackingInfo, menuInfo, createTableOrder, queueBoardInfo }
