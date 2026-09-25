'use strict'

// Pengurai antrean (padanan Android `pengurai.dart`): kirim pesan MENUNGGU yang SIAP
// sesuai urutan dibuat. Tanpa head-of-line blocking: satu baris yang terus ditolak
// server (5xx pada muatan tertentu) mendapat mundur SENDIRI (`cobaLagiSetelah`) dan
// pengurai lanjut ke baris lain yang siap — urutan FIFO hanya di antara baris yang siap.
// Aman karena semua tulis idempoten lewat `client_ref`.
//
// Mode PER BARIS — `kirim(path, body, pesan)` disuntik (pesan.tokoId = toko saat dibuat): mengembalikan
// envelope api-client { ok, status, data, message, errors, gangguan?, gateway?, timeout? } — status 0 =
// tidak sampai ke server, status -1 = timeout (mungkin sudah sampai). Keputusan per jawaban:
//
//   sukses                          → TERKIRIM
//   JARINGAN (0 / gateway tak terjangkau / 429) → jeda GLOBAL (semua menunggu, urutan utuh);
//                                     dilewati begitu koneksi pulih
//   SERVER (5xx/408 dari server)    → mundur per baris, lanjut; setelah batas dari server
//                                     (GET /config: antrean_maks_percobaan_galat_server,
//                                     antrean_maks_umur_jam) → TINJAU dengan pesan server terakhir.
//                                     Batas tak dikirim server → tetap menunggu + peringatan UI.
//   TIMEOUT (-1)                    → mundur per baris, lanjut (tidak dihitung galat server); umur lewat
//                                     antrean_maks_umur_jam → TINJAU "mungkin sudah sampai" (pemulih memeriksanya)
//   402 langganan / 426 update      → jeda global, baris TETAP menunggu (tidak ditinjau)
//   401 sesi berakhir               → berhenti; putaran berikutnya menunggu token (siapKirim)
//   4xx lain                        → TINJAU
//
// Mode BATCH v2 (Fase 4; aktif bila GET /config `sync_batch.versi ≥ 2` dan `kirimBatch` disuntik):
// baris berjenis batch (checkout, refund, batal, bayar bon, transisi pesanan) dikumpulkan ke SEGMEN
// BERURUTAN (≤25 op, ≤1,5 MB) dan dikirim satu POST /sync/v2/batch; baris jenis lain (pengeluaran,
// stok masuk) memotong segmen dan dikirim per baris di posisinya. Hasil dipetakan per client_ref:
//   OK                               → TERKIRIM (hasil: id, nomor, kode, peringatan, data)
//   retriable:false                  → TINJAU "<label kode>: <pesan server>"
//   DITUNDA                          → MENUNGGU, dikirim lagi ±3 dtk tanpa menaikkan percobaan
//   GALAT_SERVER / hasil hilang      → mundur per baris seperti 5xx (batas tinjau /config)
//   retriable:true lain (PRASYARAT, SESI_TIDAK_ADA, SESI_BEDA_TOKO, kode baru) → jeda panjang 1–60 mnt
// Jawaban batch non-200: 401/402/426/jaringan → jeda global seperti per baris; 404 atau 503
// BATCH_TIDAK_TERSEDIA → per baris sampai /config berikutnya; 409 BATCH_REF_BENTROK → ref bergaram
// sekali; 413 → segmen dibelah; 429 BATCH_BERJALAN → tidak ada POST batch dari perangkat ini selama Retry-After
// (bawaan 5 dtk; baris endpoint tunggal tetap jalan); 429 tanpa kode →
// jeda jaringan; 5xx/408/422/409 berulang/4xx lain → mundur per baris. Patch non-item membersihkan `kode`.
//
// Urutan (kedua mode, `_penahan`): refund/batal atas transaksi LOKAL (`/transaksi/lokal:<ref>/…`) ditahan tanpa
// penalti sampai induknya TERKIRIM (batch: atau satu segmen → `transaksi_ref`; per baris: jalur & `items[].baris`
// ditulis ulang ke id server); induk TINJAU → anak ikut TINJAU `INDUK_TINJAU` (pulih saat induk dikirim ulang atau
// kembali MENUNGGU/TERKIRIM lewat pemulih — diperiksa di awal tiap putaran).
// Checkout/bayar bon toko T menunggu stok masuk/opname/buka sesi/buka bon toko T yang lebih tua.

const { STATUS, badanWaktuRapi, refIndukLokal } = require('./antrean')
const { jenisGangguan } = require('../lib/klasifikasi-http')
const { tipeBatch, BATAS_OP_SEGMEN, BATAS_BYTE_SEGMEN, labelKode, opDariBaris, clientRefBatch, ukuranJson, hasilDariItem, gantiRujukanLokal } = require('./operasi-batch')

const JEDA_MUNDUR_MS = [5000, 15000, 45000, 120000, 600000]

// Jeda panjang untuk item batch yang BELUM bisa dijalankan (menunggu sesi dibuka / transaksi asal
// tercatat): bukan galat server, jadi tidak dihitung menuju batas tinjau galat server.
const JEDA_LAMA_MS = [60000, 300000, 900000, 1800000, 3600000]

// DITUNDA: dikirim lagi sebentar lagi tanpa menaikkan percobaan, tetapi tidak "segera" — server yang
// sedang padat tidak dihantam ulang tiap detik.
const JEDA_TUNDA_MS = 3000

// 429 BATCH_BERJALAN tanpa Retry-After: tunggu 5 dtk (kontrak §13.5 / K-7, sama dengan Retry-After server;
// menggantikan 3 dtk A-7). Tanpa menaikkan percobaan.
const JEDA_BERJALAN_MS = 5000

// Penjualan/pembayaran bon toko T tidak dikirim selagi baris jenis ini (toko T, lebih tua, akun sama) belum
// tercatat: stok masuk sebelum jual, sesi & bon dibuka sebelum dipakai. Penahan gugur saat penentunya
// TERKIRIM, TINJAU, atau dibatalkan — batas tinjau /config tetap mencegah tertahan selamanya.
const PENAHAN_KAUSAL = new Set(['STOK_MASUK', 'OPNAME', 'SESI_BUKA', 'BILL_BUKA'])
const JENIS_TERTAHAN_KAUSAL = new Set(['CHECKOUT', 'BILL_BAYAR'])

// Baris TINJAU `INDUK_TINJAU` yang dipulihkan (induk dikirim ulang / kembali menunggu / sudah tercatat).
const PATCH_PULIH_TURUNAN = Object.freeze({ status: STATUS.MENUNGGU, percobaan: 0, galatServer: 0, cobaLagiSetelah: null, sebabTunda: null, kode: null, galat: null })
// Anak PRASYARAT yang dibebaskan karena induknya tercatat: jeda & kode/galat PRASYARAT sudah basi.
const PATCH_BEBAS_PRASYARAT = Object.freeze({ cobaLagiSetelah: null, sebabTunda: null, kode: null, galat: null })

const PESAN_INDUK_TINJAU = 'Menunggu transaksi asal ditinjau — kirim ulang atau batalkan transaksi asalnya dulu.'
const PESAN_INDUK_TIDAK_DIKENAL = 'Transaksi asal belum punya nomor server yang bisa dirujuk. Batalkan data ini lalu ulangi dari Riwayat setelah transaksi asal tersinkron.'

// Mekanika UI (bukan kebijakan bisnis): setelah sekian galat server beruntun pada satu baris,
// panel Sinkronisasi menampilkan peringatan menetap walau server tidak mengirim batas tinjau.
const AMBANG_PERINGATAN_PERCOBAAN = 10

// Penyebab tunda baris (disimpan di `sebabTunda`). BATCH = jeda milik baris dari hasil item batch.
const SEBAB = Object.freeze({ JARINGAN: 'JARINGAN', SERVER: 'SERVER', TIMEOUT: 'TIMEOUT', LANGGANAN: 'LANGGANAN', UPDATE: 'UPDATE', BATCH: 'BATCH' })

function mundur(percobaan) {
  return JEDA_MUNDUR_MS[Math.min(Math.max(percobaan, 1), JEDA_MUNDUR_MS.length) - 1]
}

function jedaLama(percobaan) {
  return JEDA_LAMA_MS[Math.min(Math.max(percobaan, 1), JEDA_LAMA_MS.length) - 1]
}

const PESAN_TIMEOUT_SETELAH_KIRIM =
  'Server tidak menjawab setelah data dikirim. Periksa di Riwayat apakah sudah tercatat sebelum mengirim ulang.'

function angkaPositif(v) {
  if (v === null || v === undefined || v === '' || typeof v === 'boolean') return null
  const n = Number(v)
  return Number.isFinite(n) && n > 0 ? n : null
}

/** Bilangan bulat positif (pecahan dipotong ke bawah — paritas Flutter `toInt()`); < 1 / tak sah → null. */
function bulatPositif(v) {
  const n = angkaPositif(v)
  return n === null || n < 1 ? null : Math.floor(n)
}

/**
 * Jeda (ms) dari `Retry-After` pada amplop: field `retryAfter` (detik) atau header `Retry-After`
 * (objek Headers / objek biasa). null bila tak ada / tak sah; dibatasi jeda mundur terpanjang.
 */
function jedaRetryAfter(res) {
  if (!res) return null
  let v = res.retryAfter
  const h = res.headers
  if ((v === undefined || v === null) && h && typeof h === 'object') {
    v = typeof h.get === 'function' ? h.get('retry-after') : h[Object.keys(h).find((k) => k.toLowerCase() === 'retry-after')]
  }
  const detik = angkaPositif(v)
  return detik === null ? null : Math.min(detik * 1000, JEDA_MUNDUR_MS[JEDA_MUNDUR_MS.length - 1])
}

/**
 * Kebijakan tinjau otomatis dari data GET /config (field aditif server). Tidak ada / tidak
 * sah → null (tanpa tinjau otomatis; jangan mengarang batas).
 */
function kebijakanDariConfig(config) {
  const c = config && typeof config === 'object' ? config : {}
  const maksPercobaan = angkaPositif(c.antrean_maks_percobaan_galat_server)
  return {
    maksPercobaanGalatServer: maksPercobaan === null ? null : Math.floor(maksPercobaan),
    maksUmurJam: angkaPositif(c.antrean_maks_umur_jam)
  }
}

/** Blok `sync_batch` GET /config → { versi, maksOperasi, maksByte }. Tanpa blok (server lama, Mode Demo) = versi 0. */
function syncBatchDariConfig(config) {
  const sb = config && typeof config === 'object' && config.sync_batch && typeof config.sync_batch === 'object' ? config.sync_batch : null
  if (!sb) return { versi: 0, maksOperasi: null, maksByte: null }
  // Batas op per segmen = yang terkecil dari maks_operasi dan saran_operasi_per_segmen server (paritas Flutter).
  // Pecahan dibulatkan ke bawah: 10.5 op → 10 (bukan segmen 11 op karena `length >= 10.5`).
  const maks = bulatPositif(sb.maks_operasi)
  const saran = bulatPositif(sb.saran_operasi_per_segmen)
  const maksOperasi = maks === null ? saran : saran === null ? maks : Math.min(maks, saran)
  return { versi: Math.floor(Number(sb.versi) || 0), maksOperasi, maksByte: bulatPositif(sb.maks_byte) }
}

const milikSendiri = (p) => p.sebabTunda === SEBAB.SERVER || p.sebabTunda === SEBAB.TIMEOUT || p.sebabTunda === SEBAB.BATCH

/** Baris per-muatan (SERVER/TIMEOUT/BATCH) memakai jedanya sendiri; penyebab lain mengikuti jeda global. */
function siapPerBaris(p, kini) {
  if (p.status !== STATUS.MENUNGGU) return false
  return !milikSendiri(p) || !p.cobaLagiSetelah || p.cobaLagiSetelah <= kini
}

/** Kode mesin pertama pada `errors.kode` amplop gagal (mis. BATCH_REF_BENTROK); null bila tak ada. */
function kodeGalat(res) {
  const k = res && res.errors && res.errors.kode
  return Array.isArray(k) && k.length ? String(k[0]) : null
}

class Pengurai {
  /**
   * @param {object} o
   * @param {(badan: {client_ref: string, device_id: string, operations: object[]}) => Promise<object>} [o.kirimBatch]
   *        POST /sync/v2/batch; tanpa ini hanya mode per baris
   * @param {() => string|null} [o.pemilikAktif]  kunci pemilik akun aktif; tidak diberikan = tanpa saringan
   * @param {(l: {pesan: string, jumlah: number}) => void} [o.laporGalat]  diagnostik (amplop batch ditolak 422)
   * @param {() => {maksPercobaanGalatServer: number|null, maksUmurJam: number|null}|null} [o.kebijakan]
   * @param {() => boolean} [o.siapKirim]  false = jangan kirim (mis. belum ada token setelah 401)
   */
  constructor({ antrean, kirim, kirimBatch = null, pemilikAktif = null, laporGalat = null, koneksi = null, setelahBerubah = null, pemulih = null, kebijakan = () => null, siapKirim = () => true, sekarang = () => Date.now(), jadwal = setTimeout, batalJadwal = clearTimeout }) {
    this.antrean = antrean
    this.kirim = kirim
    this.kirimBatch = kirimBatch
    this.pemilikAktif = pemilikAktif
    this.laporGalat = laporGalat
    this.koneksi = koneksi
    // Pemulih baris TINJAU "mungkin sudah sampai" (lihat pemulih.js); null = tanpa.
    this.pemulih = pemulih
    this.kebijakan = kebijakan
    this.siapKirim = siapKirim
    this.setelahBerubah = setelahBerubah
    this.sekarang = sekarang
    this._jadwalFn = jadwal
    this._batalJadwal = batalJadwal
    this._timer = null
    this._berjalan = false
    this._janji = null
    this._jeda = null // jeda global { sampai, sebab, percobaan }
    // Versi batch terakhir dari /config disimpan di antrean → start dingin langsung memakai mode yang benar.
    const pr = typeof antrean.perangkat === 'function' ? antrean.perangkat() : null
    this._syncBatch = { versi: pr ? Math.floor(Number(pr.syncBatchVersi) || 0) : 0, maksOperasi: null, maksByte: null }
    this._batchMati = false // server menjawab 404/503 BATCH_TIDAK_TERSEDIA → per baris sampai /config berikutnya
    this._batasOpAdaptif = BATAS_OP_SEGMEN
    // 429 BATCH_BERJALAN: kunci batch akun ini masih dipegang server → TIDAK ada POST batch (segmen mana pun)
    // sampai waktu ini; tanpa ini putaran ±1 dtk berikutnya mem-POST segmen lain dan menghabiskan limiter pos-sync.
    this._batchTundaSampai = null
  }

  _ubah() { if (this.setelahBerubah) { try { this.setelahBerubah() } catch { /* abaikan */ } } }

  _kebijakan() {
    let k = null
    try { k = this.kebijakan() } catch { k = null }
    return { maksPercobaanGalatServer: (k && k.maksPercobaanGalatServer) || null, maksUmurJam: (k && k.maksUmurJam) || null }
  }

  /** Jeda global masih berlaku? Jeda jaringan gugur begitu koneksi terbukti pulih. */
  _jedaAktif(kini) {
    if (!this._jeda || this._jeda.sampai <= kini) return false
    if (this._jeda.sebab === SEBAB.JARINGAN && this.koneksi && this.koneksi.online === true) return false
    return true
  }

  _pasangJeda(sebab) {
    const percobaan = this._jeda && this._jeda.sebab === sebab ? this._jeda.percobaan + 1 : 1
    const panjang = sebab === SEBAB.UPDATE ? JEDA_MUNDUR_MS[JEDA_MUNDUR_MS.length - 1] : mundur(percobaan)
    this._jeda = { sebab, percobaan, sampai: this.sekarang() + panjang }
    return this._jeda
  }

  /** Status untuk diagnosis/UI. */
  status() {
    return { jeda: this._jeda ? { ...this._jeda } : null, modeBatch: this.modeBatch() }
  }

  /** Terapkan blok sync_batch dari /config (juga salinan offline). Mengembalikan mode batch sesudahnya. */
  aturSyncBatch(sb) {
    const s = sb && typeof sb === 'object' ? sb : {}
    this._syncBatch = { versi: Math.floor(Number(s.versi) || 0), maksOperasi: bulatPositif(s.maksOperasi), maksByte: bulatPositif(s.maksByte) }
    this._batchMati = false
    if (typeof this.antrean.aturPerangkat === 'function') this.antrean.aturPerangkat({ syncBatchVersi: this._syncBatch.versi })
    return this.modeBatch()
  }

  modeBatch() {
    return typeof this.kirimBatch === 'function' && this._syncBatch.versi >= 2 && !this._batchMati
  }

  /** undefined = tanpa saringan pemilik; null = akun belum diketahui (tak ada baris yang dikirim). */
  _pemilik() {
    if (typeof this.pemilikAktif !== 'function') return undefined
    try { return this.pemilikAktif() || null } catch { return null }
  }

  _milik(p, pemilik) {
    return pemilik === undefined || (pemilik !== null && p.pemilik === pemilik)
  }

  async _putaran() {
    let sukses = 0
    const kini = this.sekarang()
    const pemilik = this._pemilik()
    const semua = this.antrean.semua()
    for (const p of semua) {
      if (this._jedaAktif(this.sekarang())) break
      if (!this._milik(p, pemilik) || !siapPerBaris(p, kini)) continue
      const tahan = this._penahan(p, semua, null)
      if (tahan === 'tahan') continue
      if (tahan === 'indukTinjau') { this._tinjauIndukTinjau(p); this._ubah(); continue }
      // Endpoint tunggal tidak mengenal "lokal:<ref>": rujukan diganti id server induk yang sudah terkirim.
      const induk = refIndukLokal(p.path)
      if (induk) {
        const q = this.antrean.cari(induk)
        const ganti = q ? gantiRujukanLokal(p, q) : null
        if (!ganti) {
          this._tinjau(p.clientRef, { sebabTunda: null, cobaLagiSetelah: null, kode: 'INDUK_TIDAK_DIKENAL', galat: PESAN_INDUK_TIDAK_DIKENAL })
          this._ubah()
          continue
        }
        this.antrean.perbarui(p.clientRef, { path: ganti.path, body: ganti.body })
      }
      const hasil = await this._kirim(p)
      if (hasil === 'terkirim') sukses++
      if (hasil === 'berhenti') return { sukses, berhenti: true }
    }
    return { sukses, berhenti: false }
  }

  /**
   * Penahan urutan untuk satu baris (tanpa menaikkan percobaan):
   *   'tahan'       — penentunya belum tercatat (induk lokal menunggu di luar segmen ini / stok masuk toko sama);
   *   'indukTinjau' — induk lokalnya TINJAU → baris ini ikut ditinjau;
   *   null          — boleh dikirim.
   * `dalamSegmen` = clientRef yang sudah masuk segmen batch berjalan (null di mode per baris).
   */
  _penahan(p, semua, dalamSegmen) {
    const induk = refIndukLokal(p.path)
    if (induk) {
      const q = this.antrean.cari(induk)
      if (q) {
        if (q.status === STATUS.TINJAU) return 'indukTinjau'
        if (q.status !== STATUS.TERKIRIM && !(dalamSegmen && dalamSegmen.has(induk))) return 'tahan'
      }
    }
    if (JENIS_TERTAHAN_KAUSAL.has(p.jenis)) {
      const tokoSama = (q) => q.tokoId == null || p.tokoId == null || q.tokoId === p.tokoId
      const penentu = semua.find((q) => q.urut < p.urut && PENAHAN_KAUSAL.has(q.jenis) &&
        (q.status === STATUS.MENUNGGU || q.status === STATUS.MENGIRIM) && q.pemilik === p.pemilik && tokoSama(q))
      if (penentu) return 'tahan'
    }
    return null
  }

  /** Satu putaran menurut mode; server yang ternyata tak mendukung batch → lanjut per baris di putaran yang sama. */
  async _satuPutaran() {
    this._pulihkanTurunan()
    if (!this.modeBatch()) return this._putaran()
    const b = await this._putaranBatch()
    if (!b.pindahPerBaris) return b
    const lanjut = await this._putaran()
    return { sukses: b.sukses + lanjut.sukses, berhenti: lanjut.berhenti }
  }

  async _putaranBatch() {
    let sukses = 0
    const kini = this.sekarang()
    const pemilik = this._pemilik()
    const deviceId = this.antrean.perangkat().id
    const batasOp = Math.max(1, Math.min(BATAS_OP_SEGMEN, this._syncBatch.maksOperasi || BATAS_OP_SEGMEN, this._batasOpAdaptif))
    const batasByte = this._syncBatch.maksByte ? Math.min(BATAS_BYTE_SEGMEN, Math.floor(this._syncBatch.maksByte * 0.7)) : BATAS_BYTE_SEGMEN
    const semua = this.antrean.semua()
    const batchDitunda = this._batchTundaSampai !== null && this._batchTundaSampai > kini
    let segmen = []
    let dalamSegmen = new Set()
    let ukuran = 0
    const kirimSegmen = async () => {
      if (segmen.length === 0) return 'lanjut'
      const isi = segmen
      segmen = []
      dalamSegmen = new Set()
      ukuran = 0
      const r = await this._kirimSegmen(isi, deviceId)
      sukses += r.sukses
      return r.hasil
    }
    const akhiri = (hasil) => (hasil === 'berhenti' ? { sukses, berhenti: true } : { sukses, berhenti: false, pindahPerBaris: true })
    const tahanan = (p) => {
      const t = this._penahan(p, semua, dalamSegmen)
      if (t === 'indukTinjau') { this._tinjauIndukTinjau(p); this._ubah() }
      return t
    }

    for (const p of semua) {
      if (this._jedaAktif(this.sekarang())) break
      if (!this._milik(p, pemilik) || !siapPerBaris(p, kini)) continue
      // Jeda batch tingkat perangkat: baris jenis batch menunggu; jenis lain (endpoint tunggal) tetap jalan.
      if (batchDitunda && tipeBatch(p.jenis)) continue
      if (tahanan(p)) continue
      if (tipeBatch(p.jenis)) {
        const t = this.antrean.transaksiLokal(p.clientRef)
        const op = opDariBaris(p, { deviceId, kini, nomorLokal: t ? t.nomorLokal : null })
        const n = ukuranJson(op)
        if (segmen.length > 0 && (segmen.length >= batasOp || ukuran + n > batasByte)) {
          const h = await kirimSegmen()
          if (h !== 'lanjut') return akhiri(h)
          if (this._jedaAktif(this.sekarang())) break
          // Induk yang tadi satu segmen kini sudah dijawab: nilai ulang penahan untuk segmen baru.
          if (p.status !== STATUS.MENUNGGU || tahanan(p)) continue
        }
        segmen.push({ p, op, nomorLokal: t ? t.nomorLokal : null })
        dalamSegmen.add(p.clientRef)
        ukuran += n
        continue
      }
      // Jenis di luar batch (pengeluaran, stok masuk): segmen sebelumnya dikirim dulu agar urutan kausal utuh.
      const h = await kirimSegmen()
      if (h !== 'lanjut') return akhiri(h)
      if (this._jedaAktif(this.sekarang())) break
      const hasil = await this._kirim(p)
      if (hasil === 'terkirim') sukses++
      if (hasil === 'berhenti') return { sukses, berhenti: true }
    }
    if (!this._jedaAktif(this.sekarang())) {
      const h = await kirimSegmen()
      if (h !== 'lanjut') return akhiri(h)
    }
    return { sukses, berhenti: false }
  }

  async _kirimBatchAman(badan) {
    try {
      return await this.kirimBatch(badan)
    } catch (err) {
      return { ok: false, status: 0, gangguan: true, message: err && err.message ? err.message : 'gagal' }
    }
  }

  async _kirimSegmen(isi, deviceId) {
    const baris = isi.map((x) => x.p)
    this.antrean.perbaruiBanyak(baris.map((p) => ({ clientRef: p.clientRef, patch: { status: STATUS.MENGIRIM } })))
    // Operasi dibangun ulang menurut jam SAAT kiriman ini: umur_detik segmen berikutnya (setelah segmen lain
    // menunggu jawaban) dan kiriman bergaram tidak memakai jam awal putaran yang sudah basi.
    const badan = (garam) => {
      const saatKirim = this.sekarang()
      return { client_ref: clientRefBatch(deviceId, baris, garam), device_id: deviceId, operations: isi.map((x) => opDariBaris(x.p, { deviceId, kini: saatKirim, nomorLokal: x.nomorLokal })) }
    }
    let res = await this._kirimBatchAman(badan(0))
    // Ref sama dengan isi berbeda (komposisi kembar setelah antrean dipulihkan): ref bergaram, sekali saja.
    if (!res.ok && res.status === 409 && kodeGalat(res) === 'BATCH_REF_BENTROK') res = await this._kirimBatchAman(badan(1))
    return this._olahJawabanBatch(baris, res)
  }

  /** Jawaban satu POST batch → status semua baris segmen. Mengembalikan { sukses, hasil: 'lanjut'|'berhenti'|'perBaris' }. */
  _olahJawabanBatch(baris, res) {
    const kini = this.sekarang()
    const kode = kodeGalat(res)
    const semua = (patch) => this.antrean.perbaruiBanyak(baris.map((p) => ({ clientRef: p.clientRef, patch: typeof patch === 'function' ? patch(p) : patch })))
    const selesai = (hasil) => { this._ubah(); return { sukses: 0, hasil } }

    if (res.ok) {
      const data = res.data
      if (!data || data.versi !== 2 || !Array.isArray(data.results)) return this._jawabanServerLama(baris, data)
      return this._petakanHasil(baris, data.results)
    }
    // Server/gateway belum mengenal batch v2 di koneksi ini: kembali per baris tanpa menghukum baris.
    if (res.status === 404 || (res.status === 503 && kode === 'BATCH_TIDAK_TERSEDIA')) {
      this._batchMati = true
      semua({ status: STATUS.MENUNGGU, kode: null })
      return selesai('perBaris')
    }
    if (res.status === 429 && kode === 'BATCH_BERJALAN') {
      const tunggu = jedaRetryAfter(res) ?? JEDA_BERJALAN_MS
      this._batchTundaSampai = kini + tunggu
      semua({ status: STATUS.MENUNGGU, sebabTunda: SEBAB.BATCH, cobaLagiSetelah: kini + tunggu, kode: 'BATCH_BERJALAN', galat: 'Server masih memproses kiriman sebelumnya; dikirim lagi sebentar.' })
      return selesai('berhenti')
    }
    if (res.status === 413 || res.gateway === 'body-too-large' || kode === 'BATCH_TERLALU_BESAR') {
      if (baris.length === 1) {
        this._tinjau(baris[0].clientRef, { sebabTunda: null, cobaLagiSetelah: null, kode: 'BATCH_TERLALU_BESAR', galat: 'Data ini terlalu besar untuk dikirim ke server. Batalkan lalu catat ulang dalam beberapa transaksi, atau hubungi dukungan.' })
      } else {
        this._batasOpAdaptif = Math.max(1, Math.floor(baris.length / 2))
        semua({ status: STATUS.MENUNGGU, kode: null })
      }
      return selesai('lanjut')
    }
    if (res.status === 402) {
      const jeda = this._pasangJeda(SEBAB.LANGGANAN)
      semua({ status: STATUS.MENUNGGU, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.LANGGANAN, kode: null, galat: res.message ? String(res.message) : pesanServer(res) })
      return selesai('berhenti')
    }
    if (res.status === 426) {
      const jeda = this._pasangJeda(SEBAB.UPDATE)
      semua({ status: STATUS.MENUNGGU, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.UPDATE, kode: null, galat: res.message ? String(res.message) : null })
      return selesai('berhenti')
    }
    if (res.status === 401) {
      semua({ status: STATUS.MENUNGGU, kode: null })
      return selesai('berhenti')
    }
    const gangguan = jenisGangguan(res)
    if (gangguan === 'JARINGAN') {
      const jeda = this._pasangJeda(SEBAB.JARINGAN)
      semua((p) => ({
        status: STATUS.MENUNGGU, percobaan: (p.percobaan || 0) + 1, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.JARINGAN, kode: null,
        galat: res.status === 429 ? 'Server membatasi permintaan; dicoba lagi otomatis.' : 'Tidak dapat terhubung ke server.'
      }))
      if (this.koneksi) this.koneksi.tandaiOffline()
      return selesai('berhenti')
    }
    if (gangguan === 'TIMEOUT') {
      semua((p) => this._patchTimeout(p, kini))
      // Anak satu segmen yang induknya kini TINJAU (terlalu tua) → INDUK_TINJAU walau anak itu sendiri juga tua,
      // agar kirim ulang induk / pemulih memulihkannya; turunan lain yang masih menunggu ikut ditinjau.
      for (const p of baris) {
        const indukRef = refIndukLokal(p.path)
        const q = indukRef ? this.antrean.cari(indukRef) : null
        if (q && q.status === STATUS.TINJAU && p.kode !== 'INDUK_TINJAU') this._tinjauIndukTinjau(p)
      }
      for (const p of baris) if (p.status === STATUS.TINJAU) this._kaskadeTinjau(p.clientRef)
      return selesai('lanjut')
    }
    // 5xx/408, 409 berulang, 422 amplop cacat (bug app), 4xx lain: jawaban tidak menilai baris satu per satu
    // → mundur per baris sebagai galat server (batas tinjau dari /config tetap berlaku).
    if (res.status === 422 && typeof this.laporGalat === 'function') {
      try { this.laporGalat({ pesan: `Kiriman batch sinkron ditolak server (422): ${pesanServer(res)}`, jumlah: baris.length }) } catch { /* abaikan */ }
    }
    for (const p of baris) this._tundaGalatServer(p, pesanServer(res), { status: res.status })
    return selesai('lanjut')
  }

  /** Hasil per item (dicocokkan lewat idempotency_key = clientRef, bukan indeks). */
  _petakanHasil(baris, results) {
    const kini = this.sekarang()
    const peta = new Map()
    for (const it of results) if (it && typeof it.idempotency_key === 'string') peta.set(it.idempotency_key, it)
    let sukses = 0
    let langganan = false
    for (const p of baris) {
      const it = peta.get(p.clientRef)
      if (!it) {
        this._tundaGalatServer(p, 'Server tidak mengembalikan hasil untuk data ini', { kode: 'GALAT_SERVER' })
        continue
      }
      if (it.accepted === true) {
        this.antrean.selesai(p.clientRef, hasilDariItem(it))
        this._bebaskanAnak(p.clientRef)
        sukses++
        continue
      }
      const kode = typeof it.kode === 'string' && it.kode ? it.kode : 'GALAT_SERVER'
      const pesan = String(it.message || it.reason || labelKode(kode))
      if (kode === 'DITUNDA') {
        this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU, sebabTunda: SEBAB.BATCH, cobaLagiSetelah: kini + JEDA_TUNDA_MS, kode, galat: 'Ditunda server (batas waktu kiriman); dikirim lagi sebentar.' })
      } else if (kode === 'GALAT_SERVER') {
        this._tundaGalatServer(p, pesan, { kode })
      } else if (kode === 'LANGGANAN') {
        const jeda = langganan && this._jeda ? this._jeda : this._pasangJeda(SEBAB.LANGGANAN)
        langganan = true
        this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.LANGGANAN, kode, galat: pesan })
      } else if (it.retriable === true) {
        this._tundaLama(p, kode, pesan)
      } else {
        this._tinjau(p.clientRef, { sebabTunda: null, cobaLagiSetelah: null, kode, galat: `${labelKode(kode)}: ${pesan}` })
      }
    }
    // Anak yang dijawab PRASYARAT karena induknya ditolak di batch yang sama ikut ditinjau (rancangan C.7.3).
    for (const p of baris) {
      if (p.status !== STATUS.MENUNGGU) continue
      const indukRef = refIndukLokal(p.path)
      const q = indukRef ? this.antrean.cari(indukRef) : null
      if (q && q.status === STATUS.TINJAU) this._tinjauIndukTinjau(p)
    }
    if (!langganan) this._jeda = null
    if (this.koneksi) this.koneksi.tandaiOnline()
    if (sukses > 0) this._batasOpAdaptif = Math.min(BATAS_OP_SEGMEN, this._batasOpAdaptif * 2)
    this._ubah()
    return { sukses, hasil: langganan ? 'berhenti' : 'lanjut' }
  }

  /**
   * Jawaban 200 tanpa `data.versi === 2` = server v1 menjawab di rute batch (rollback deploy / salinan
   * /config basi): yang sudah diterima dicatat, sisanya kembali ke antrean dan kiriman pindah ke per baris.
   */
  _jawabanServerLama(baris, data) {
    const hasil = data && Array.isArray(data.results) ? data.results : []
    const peta = new Map(hasil.filter((it) => it && typeof it.idempotency_key === 'string').map((it) => [it.idempotency_key, it]))
    let sukses = 0
    for (const p of baris) {
      const it = peta.get(p.clientRef)
      if (it && it.accepted === true) {
        this.antrean.selesai(p.clientRef, hasilDariItem(it))
        this._bebaskanAnak(p.clientRef)
        sukses++
      } else {
        this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU, kode: null })
      }
    }
    this._batchMati = true
    this._ubah()
    return { sukses, hasil: 'perBaris' }
  }

  /** Item belum bisa dijalankan (retriable, bukan galat server): jeda panjang bertingkat; umur lewat batas → TINJAU. */
  _tundaLama(p, kode, pesan) {
    const percobaan = (p.percobaan || 0) + 1
    const k = this._kebijakan()
    const umurJam = (this.sekarang() - (Number(p.dibuat) || this.sekarang())) / 3600000
    if (k.maksUmurJam !== null && umurJam >= k.maksUmurJam) {
      this._tinjau(p.clientRef, { percobaan, sebabTunda: null, cobaLagiSetelah: null, kode, galat: `${labelKode(kode)}: ${pesan} (tertunda lebih dari ${k.maksUmurJam} jam; perlu ditinjau)` })
      return
    }
    this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU, percobaan, sebabTunda: SEBAB.BATCH, cobaLagiSetelah: this.sekarang() + jedaLama(percobaan), kode, galat: `${labelKode(kode)}: ${pesan}` })
  }

  /**
   * Patch baris yang tak dijawab tepat waktu SETELAH terkirim (bukan galat server): mundur per baris; umur lewat
   * batas /config → TINJAU "mungkin sudah sampai" (checkout diperiksa pemulih ke daftar transaksi server).
   */
  _patchTimeout(p, kini) {
    const percobaan = (p.percobaan || 0) + 1
    const k = this._kebijakan()
    const umurJam = (kini - (Number(p.dibuat) || kini)) / 3600000
    if (k.maksUmurJam !== null && umurJam >= k.maksUmurJam) {
      return { status: STATUS.TINJAU, percobaan, cobaLagiSetelah: null, sebabTunda: null, kode: null, galat: `${PESAN_TIMEOUT_SETELAH_KIRIM} (tertunda lebih dari ${k.maksUmurJam} jam; perlu ditinjau)` }
    }
    return { status: STATUS.MENUNGGU, percobaan, cobaLagiSetelah: kini + mundur(percobaan), sebabTunda: SEBAB.TIMEOUT, kode: null, galat: 'Server tidak menjawab tepat waktu; dicoba lagi otomatis.' }
  }

  /** Galat server untuk baris INI: mundur per baris; lewat batas /config → TINJAU. */
  _tundaGalatServer(p, pesan, { status = null, kode = null } = {}) {
    const percobaan = (p.percobaan || 0) + 1
    const galatServer = (p.galatServer || 0) + 1
    const k = this._kebijakan()
    const umurJam = (this.sekarang() - (Number(p.dibuat) || this.sekarang())) / 3600000
    const lewatPercobaan = k.maksPercobaanGalatServer !== null && galatServer >= k.maksPercobaanGalatServer
    const lewatUmur = k.maksUmurJam !== null && umurJam >= k.maksUmurJam
    if (lewatPercobaan || lewatUmur) {
      this._tinjau(p.clientRef, {
        percobaan, galatServer, cobaLagiSetelah: null, sebabTunda: null, kode,
        galat: `${pesan} (gagal ${galatServer}× di server${lewatUmur && !lewatPercobaan ? `, tertunda lebih dari ${k.maksUmurJam} jam` : ''}; perlu ditinjau)`
      })
    } else {
      this.antrean.perbarui(p.clientRef, {
        status: STATUS.MENUNGGU, percobaan, galatServer, cobaLagiSetelah: this.sekarang() + mundur(galatServer), sebabTunda: SEBAB.SERVER, kode,
        galat: `${pesan} (${status ? `HTTP ${status}; ` : ''}dicoba lagi otomatis)`
      })
    }
  }

  /** Pindahkan baris ke TINJAU; turunan lokal yang masih menunggu ikut ditinjau (berantai). */
  _tinjau(ref, patch) {
    this.antrean.perbarui(ref, { ...patch, status: STATUS.TINJAU })
    this._kaskadeTinjau(ref)
  }

  /** Turunan lokal `ref` yang masih menunggu ikut TINJAU `INDUK_TINJAU` (berantai). */
  _kaskadeTinjau(ref) {
    for (const q of this.antrean.semua()) {
      if (q.status === STATUS.MENUNGGU && refIndukLokal(q.path) === ref) this._tinjauIndukTinjau(q)
    }
  }

  _tinjauIndukTinjau(p) {
    this._tinjau(p.clientRef, { sebabTunda: null, cobaLagiSetelah: null, kode: 'INDUK_TINJAU', galat: PESAN_INDUK_TINJAU })
  }

  /** Induk baru saja tercatat: anak yang sedang jeda panjang karena PRASYARAT boleh langsung dikirim. */
  _bebaskanAnak(ref) {
    const patches = []
    for (const q of this.antrean.semua()) {
      if (q.status === STATUS.MENUNGGU && q.kode === 'PRASYARAT' && refIndukLokal(q.path) === ref) {
        patches.push({ clientRef: q.clientRef, patch: { ...PATCH_BEBAS_PRASYARAT } })
      }
    }
    if (patches.length) this.antrean.perbaruiBanyak(patches)
  }

  /**
   * Awal setiap putaran: induk bisa berubah lewat jalur di luar pengurai (pemulih "mungkin sudah sampai" memanggil
   * antrean langsung — TERKIRIM bila cocok, MENUNGGU bila belum tercatat). Anak `INDUK_TINJAU` yang induknya kini
   * MENUNGGU/TERKIRIM kembali MENUNGGU (penahan menanganinya), anak PRASYARAT dari induk TERKIRIM dibebaskan.
   */
  _pulihkanTurunan() {
    const patches = []
    for (const q of this.antrean.semua()) {
      const indukRef = refIndukLokal(q.path)
      const induk = indukRef ? this.antrean.cari(indukRef) : null
      if (!induk) continue
      if (q.status === STATUS.TINJAU && q.kode === 'INDUK_TINJAU' && (induk.status === STATUS.MENUNGGU || induk.status === STATUS.TERKIRIM)) {
        patches.push({ clientRef: q.clientRef, patch: { ...PATCH_PULIH_TURUNAN } })
      } else if (q.status === STATUS.MENUNGGU && q.kode === 'PRASYARAT' && induk.status === STATUS.TERKIRIM) {
        patches.push({ clientRef: q.clientRef, patch: { ...PATCH_BEBAS_PRASYARAT } })
      }
    }
    if (patches.length) {
      this.antrean.perbaruiBanyak(patches)
      this._ubah()
    }
  }

  /**
   * Kirim semua yang siap. Aman dipanggil berulang: selagi satu putaran berjalan, pemanggil
   * lain menunggu putaran itu (mis. "Sinkron sekarang" bersamaan dengan pemicu kembali-online).
   * Mengembalikan jumlah terkirim.
   */
  jalankan() {
    if (this._janji) return this._janji
    this._janji = this._jalankan().finally(() => { this._janji = null })
    return this._janji
  }

  async _jalankan() {
    this._berjalan = true
    let sukses = 0
    try {
      if (!this._jedaAktif(this.sekarang()) && this.siapKirim()) {
        const putaran = await this._satuPutaran()
        sukses += putaran.sukses
        // Baris "mungkin sudah sampai": pastikan ke server, lalu yang ternyata
        // belum tercatat dikirim ulang di putaran ini juga.
        if (!putaran.berhenti && this.pemulih) {
          let dipulihkan = 0
          try { dipulihkan = await this.pemulih.jalankan() } catch { dipulihkan = 0 }
          if (dipulihkan > 0) {
            this._ubah()
            sukses += (await this._satuPutaran()).sukses
          }
        }
      }
      this._jadwalkanUlang()
    } finally {
      this._berjalan = false
    }
    return sukses
  }

  async _kirim(p) {
    this.antrean.perbarui(p.clientRef, { status: STATUS.MENGIRIM })
    let res
    try {
      res = await this.kirim(p.path, badanWaktuRapi(p.body), p)
    } catch (err) {
      res = { ok: false, status: 0, gangguan: true, message: err && err.message ? err.message : 'gagal' }
    }
    if (res.ok) {
      // meta.idempoten = jawaban lama diulang; baris ini sudah tercatat pada
      // percobaan sebelumnya, bukan transaksi baru.
      const data = res.data || null
      if (data && res.meta && res.meta.idempoten === true) data._idempoten = true
      this.antrean.selesai(p.clientRef, data)
      this._bebaskanAnak(p.clientRef)
      this._jeda = null
      if (this.koneksi) this.koneksi.tandaiOnline()
      this._ubah()
      return 'terkirim'
    }

    const percobaan = (p.percobaan || 0) + 1
    const gangguan = jenisGangguan(res)

    // Server/gateway tak terjangkau: semua baris akan gagal sama → jeda global, urutan utuh.
    if (gangguan === 'JARINGAN') {
      const jeda = this._pasangJeda(SEBAB.JARINGAN)
      this.antrean.perbarui(p.clientRef, {
        status: STATUS.MENUNGGU, percobaan, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.JARINGAN, kode: null,
        galat: res.status === 429 ? 'Server membatasi permintaan; dicoba lagi otomatis.' : 'Tidak dapat terhubung ke server.'
      })
      if (this.koneksi) this.koneksi.tandaiOffline()
      this._ubah()
      return 'berhenti'
    }

    // Tidak ada jawaban dalam batas waktu: mundur untuk baris ini saja (server menolak duplikat
    // lewat client_ref bila ternyata sudah tercatat), lanjut ke baris lain.
    if (gangguan === 'TIMEOUT') {
      const patch = this._patchTimeout(p, this.sekarang())
      if (patch.status === STATUS.TINJAU) this._tinjau(p.clientRef, patch)
      else this.antrean.perbarui(p.clientRef, patch)
      this._ubah()
      return 'lanjut'
    }

    // Server menjawab 5xx/408 untuk muatan INI: mundur per baris, lanjut ke baris lain.
    if (gangguan === 'SERVER') {
      this._tundaGalatServer(p, pesanServer(res), { status: res.status })
      this._ubah()
      return 'lanjut'
    }

    // Langganan diblokir: penjualan tetap sah & tidak dibuang. Semua penulisan akan 402 →
    // jeda global; terkirim otomatis setelah langganan diperpanjang.
    if (res.status === 402) {
      const jeda = this._pasangJeda(SEBAB.LANGGANAN)
      this.antrean.perbarui(p.clientRef, {
        status: STATUS.MENUNGGU, percobaan, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.LANGGANAN, kode: null,
        galat: res.message ? String(res.message) : pesanServer(res)
      })
      this._ubah()
      return 'berhenti'
    }
    // Aplikasi wajib diperbarui: tunggu pembaruan (jeda panjang, tidak memukul server tiap detik).
    if (res.status === 426) {
      const jeda = this._pasangJeda(SEBAB.UPDATE)
      this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU, cobaLagiSetelah: jeda.sampai, sebabTunda: SEBAB.UPDATE, kode: null, galat: res.message ? String(res.message) : null })
      this._ubah()
      return 'berhenti'
    }
    // Sesi berakhir: tunggu masuk ulang (siapKirim → token ada lagi).
    if (res.status === 401) {
      this.antrean.perbarui(p.clientRef, { status: STATUS.MENUNGGU, kode: null })
      this._ubah()
      return 'berhenti'
    }
    // Ditolak server (400/403/404/409/422) → tinjau.
    this._tinjau(p.clientRef, { galat: pesanServer(res), sebabTunda: null, kode: null })
    this._ubah()
    return 'lanjut'
  }

  _jadwalkanUlang() {
    if (this._timer) { this._batalJadwal(this._timer); this._timer = null }
    const kini = this.sekarang()
    const jedaAktif = this._jedaAktif(kini)
    const pemilik = this._pemilik()
    const semua = this.antrean.semua()
    const tundaBatch = this.modeBatch() && this._batchTundaSampai !== null && this._batchTundaSampai > kini ? this._batchTundaSampai : null
    let terdekat = null
    for (const p of semua) {
      // Baris akun lain tidak pernah dikirim akun ini → tidak menjadwalkan apa pun.
      if (p.status !== STATUS.MENUNGGU || !this._milik(p, pemilik)) continue
      // Baris tertahan tidak menjadwalkan timer sendiri: penentunya yang membangunkan putaran.
      if (this._penahan(p, semua, null) === 'tahan') continue
      let t = milikSendiri(p) && p.cobaLagiSetelah ? p.cobaLagiSetelah : kini
      if (jedaAktif) t = Math.max(t, this._jeda.sampai)
      if (tundaBatch !== null && tipeBatch(p.jenis)) t = Math.max(t, tundaBatch)
      if (terdekat === null || t < terdekat) terdekat = t
    }
    if (terdekat === null) return
    // Belum boleh kirim (mis. menunggu masuk ulang) → periksa lagi dengan jeda wajar.
    const minimal = this.siapKirim() ? 1000 : JEDA_MUNDUR_MS[0]
    const jeda = Math.max(minimal, terdekat - kini)
    this._timer = this._jadwalFn(() => { this._timer = null; this.jalankan() }, jeda)
    if (this._timer && this._timer.unref) this._timer.unref()
  }

  /** Kirim ulang manual satu baris (reset hitungan & jeda) — turunan yang ikut ditinjau karenanya dipulihkan. */
  async kirimUlang(clientRef) {
    const p = this.antrean.cari(clientRef)
    // kirimUlangKe ikut sidik client_ref batch: kiriman ulang dari TINJAU tidak pernah dijawab dengan
    // jawaban batch lama yang tersimpan server, melainkan dinilai ulang.
    const patches = [{
      clientRef,
      patch: { status: STATUS.MENUNGGU, percobaan: 0, galatServer: 0, cobaLagiSetelah: null, sebabTunda: null, kode: null, kirimUlangKe: ((p && p.kirimUlangKe) || 0) + 1 }
    }]
    for (const q of this.antrean.semua()) {
      if (q.status === STATUS.TINJAU && q.kode === 'INDUK_TINJAU' && refIndukLokal(q.path) === clientRef) {
        patches.push({ clientRef: q.clientRef, patch: { ...PATCH_PULIH_TURUNAN } })
      }
    }
    this.antrean.perbaruiBanyak(patches)
    this._jeda = null
    this._ubah()
    return this.jalankan()
  }

  /** Sinkron manual / setelah masuk ulang: abaikan jeda global lalu kirim yang siap. */
  async sinkronSekarang() {
    this._jeda = null
    return this.jalankan()
  }

  hentikan() {
    if (this._timer) { this._batalJadwal(this._timer); this._timer = null }
  }
}

function pesanServer(res) {
  if (res.errors && typeof res.errors === 'object') {
    const k = Object.keys(res.errors)[0]
    const v = k ? res.errors[k] : null
    if (Array.isArray(v) && v.length) return String(v[0])
  }
  if (res.message) return String(res.message)
  return `Ditolak server (HTTP ${res.status}).`
}

module.exports = {
  Pengurai,
  mundur,
  jedaLama,
  kebijakanDariConfig,
  syncBatchDariConfig,
  JEDA_MUNDUR_MS,
  JEDA_LAMA_MS,
  JEDA_TUNDA_MS,
  JEDA_BERJALAN_MS,
  AMBANG_PERINGATAN_PERCOBAAN,
  SEBAB,
  PENAHAN_KAUSAL,
  PESAN_INDUK_TINJAU,
  PESAN_TIMEOUT_SETELAH_KIRIM
}
