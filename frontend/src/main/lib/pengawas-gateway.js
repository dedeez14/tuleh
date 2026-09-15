'use strict'

// Pengawas gateway Go lokal (mpos-backend) — inti gateway.js tanpa Electron agar teruji.
//
//  - pastikan(upstream): pakai ulang gateway yang sudah berjalan HANYA bila upstream DAN
//    versinya sama dengan aplikasi (gateway versi lama bisa belum mengenal rute baru);
//    selain itu nyalakan binary bawaan dengan MPOS_UPSTREAM + MPOS_VERSION.
//  - Proses gateway keluar tanpa diminta → onBerubah(status tidak berjalan) SEGERA (aplikasi
//    kembali ke koneksi langsung), lalu dicoba dinyalakan ulang dengan mundur.
//  - laporGagal(): klien HTTP mendapati koneksi ke gateway ditolak (mis. gateway eksternal
//    mati) → sama: kembali langsung + jadwalkan pemulihan.
//  - hentikan(): dimatikan saat aplikasi keluar (gateway eksternal dibiarkan hidup).

// Jeda nyala-ulang (infrastruktur, bukan data bisnis): cepat dulu, lalu melambat.
const JEDA_NYALA_ULANG_MS = [1000, 5000, 15000, 60000, 300000]
const PORTS = [8787, 8788, 8789, 8790]
const START_WAIT_MS = 2500
const START_POLL_MS = 250

function jedaNyalaUlang(percobaan) {
  return JEDA_NYALA_ULANG_MS[Math.min(Math.max(percobaan, 1), JEDA_NYALA_ULANG_MS.length) - 1]
}

/**
 * @param {object} d
 * @param {() => string} d.exePath
 * @param {(p: string) => boolean} d.existsSync
 * @param {(exe: string, env: object) => import('node:child_process').ChildProcess} d.spawn
 * @param {(port: number) => Promise<object|null>} d.probe   data /healthz atau null
 * @param {string} d.versiApp
 * @param {(status: object) => void} [d.onBerubah]
 * @param {(baris: string) => void} [d.log]
 */
function buatPengawasGateway({
  exePath, existsSync, spawn, probe, versiApp,
  onBerubah = () => {}, log = () => {},
  ports = PORTS, sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  jadwal = setTimeout, batalJadwal = clearTimeout, sekarang = () => Date.now(),
  startWaitMs = START_WAIT_MS, startPollMs = START_POLL_MS
}) {
  let child = null
  let upstreamDiminta = null // upstream yang harus dilayani (null = dihentikan)
  let timerUlang = null
  let percobaanUlang = 0
  let sedangMemastikan = null
  let state = { running: false, port: null, upstream: null, external: false, version: null }

  const kosong = () => ({ running: false, port: null, upstream: null, external: false, version: null })

  function status() {
    return { ...state, versiApp, percobaanUlang, menungguNyalaUlang: !!timerUlang }
  }

  function siar() {
    try { onBerubah(status()) } catch { /* abaikan */ }
  }

  function jadwalkanNyalaUlang(alasan) {
    if (!upstreamDiminta || timerUlang) return
    percobaanUlang += 1
    const jeda = jedaNyalaUlang(percobaanUlang)
    log(`[gateway] ${alasan}; coba nyalakan ulang dalam ${jeda} ms (percobaan ${percobaanUlang})`)
    timerUlang = jadwal(() => {
      timerUlang = null
      if (!upstreamDiminta) return
      pastikan(upstreamDiminta).then((r) => {
        if (!r.ok) jadwalkanNyalaUlang(`gagal menyalakan (${r.reason})`)
      })
    }, jeda)
    if (timerUlang && typeof timerUlang.unref === 'function') timerUlang.unref()
    siar()
  }

  function pasangPendengar(proc, port, upstream) {
    const teruskan = (sumber) => (chunk) => {
      for (const baris of String(chunk).split(/\r?\n/)) if (baris.trim()) log(`[gateway:${sumber}] ${baris}`)
    }
    if (proc.stdout && proc.stdout.on) proc.stdout.on('data', teruskan('out'))
    if (proc.stderr && proc.stderr.on) proc.stderr.on('data', teruskan('err'))
    proc.on('exit', (code, signal) => {
      if (child !== proc) return
      child = null
      const tadinyaJalan = state.running && state.port === port && !state.external
      state = kosong()
      if (tadinyaJalan) {
        siar() // aplikasi langsung kembali ke koneksi langsung
        jadwalkanNyalaUlang(`proses keluar (kode ${code}${signal ? `, sinyal ${signal}` : ''})`)
      }
    })
    proc.on('error', (err) => {
      log(`[gateway] galat proses: ${err && err.message}`)
      if (child === proc) child = null
    })
    return { port, upstream }
  }

  async function nyalakan(upstream) {
    // Upstream lokal = pengguna menunjuk server lokal sendiri → jangan tumpuk gateway (hindari loop).
    let host
    try {
      host = new URL(upstream).hostname
    } catch {
      return { ok: false, reason: 'upstream tidak valid' }
    }
    if (host === 'localhost' || host === '127.0.0.1') return { ok: false, reason: 'upstream lokal' }
    if (!existsSync(exePath())) return { ok: false, reason: 'binary tidak ditemukan' }

    const portBebas = []
    for (const port of ports) {
      const health = await probe(port)
      if (health) {
        if (health.upstream === upstream && health.version === versiApp) {
          state = { running: true, port, upstream, external: child === null, version: health.version }
          return { ok: true, port, external: state.external }
        }
        if (health.upstream === upstream) log(`[gateway] port ${port}: gateway versi ${health.version} ≠ aplikasi ${versiApp} — tidak dipakai ulang`)
        continue // port terisi gateway lain — cari port lain
      }
      portBebas.push(port)
    }

    for (const port of portBebas) {
      const proc = spawn(exePath(), { MPOS_LISTEN: `127.0.0.1:${port}`, MPOS_UPSTREAM: upstream, MPOS_VERSION: versiApp })
      child = proc
      pasangPendengar(proc, port, upstream)
      const batas = sekarang() + startWaitMs
      while (sekarang() < batas) {
        await sleep(startPollMs)
        if (child !== proc) break // keluar saat start (mis. port direbut)
        const health = await probe(port)
        if (health && health.upstream === upstream) {
          if (health.version !== versiApp) log(`[gateway] binary bawaan melapor versi ${health.version} (aplikasi ${versiApp})`)
          state = { running: true, port, upstream, external: false, version: health.version }
          return { ok: true, port, external: false }
        }
      }
      if (child === proc) child = null
      try { proc.kill() } catch { /* sudah mati */ }
    }
    return { ok: false, reason: 'gagal memulai gateway' }
  }

  /** Pastikan gateway berjalan untuk upstream. Aman dipanggil berulang (digabung). */
  function pastikan(upstream) {
    upstreamDiminta = upstream
    if (sedangMemastikan) return sedangMemastikan
    sedangMemastikan = nyalakan(upstream).then((r) => {
      if (r.ok) percobaanUlang = 0
      siar()
      return r
    }).finally(() => { sedangMemastikan = null })
    return sedangMemastikan
  }

  /** Klien HTTP mendapati gateway tak menjawab (koneksi ditolak). */
  function laporGagal() {
    if (!state.running) return
    log('[gateway] koneksi ke gateway ditolak — kembali ke koneksi langsung')
    if (child) {
      try { child.kill() } catch { /* abaikan */ }
      child = null
    }
    state = kosong()
    siar()
    jadwalkanNyalaUlang('gateway tidak menjawab')
  }

  /** Matikan gateway HANYA bila kita yang menyalakannya; hentikan nyala-ulang. */
  function hentikan() {
    upstreamDiminta = null
    if (timerUlang) { batalJadwal(timerUlang); timerUlang = null }
    percobaanUlang = 0
    if (child) {
      const proc = child
      child = null
      try { proc.kill() } catch { /* abaikan */ }
    }
    state = kosong()
  }

  async function mulaiUlang(upstream) {
    hentikan()
    siar()
    return pastikan(upstream)
  }

  return { pastikan, laporGagal, hentikan, mulaiUlang, status }
}

module.exports = { buatPengawasGateway, jedaNyalaUlang, JEDA_NYALA_ULANG_MS, PORTS }
