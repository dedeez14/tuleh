// Alur pembayaran langganan (Midtrans Snap) — docs/Tuleh-App-Pembayaran-Langganan.md.
// POST /langganan/bayar → dialog konfirmasi (nomor + harga_total) → buka halaman
// Midtrans DI DALAM aplikasi (jendela modal Chromium; Android → peramban) → saat
// Midtrans melaporkan hasil (transaction_status) verifikasi ke /langganan/status.
// Uang selalu dari invoice.harga_total. Idempoten & aman diulang.

import { api, firstError } from './api.js'
import { getState, setState } from './state.js'
import { showModal, toast, icons } from './components/ui.js'
import { esc, fmtIDR, fmtDate } from './utils/format.js'

const POLL_MS = 20000
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

export function mulaiPembayaran() {
  const before = getState().langganan || {}
  const akhirBefore = before.periode_akhir || ''
  const statusBefore = String(before.status || '').toUpperCase()
  const sisaBefore = Number(before.sisa_hari || 0)

  const body = document.createElement('div')
  body.className = 'bayar-flow'
  let timer = null
  const stop = () => { if (timer) { clearInterval(timer); timer = null } }
  showModal({ title: 'Perpanjang Langganan', body, size: 'sm', onClose: stop })

  const center = (inner) => { body.innerHTML = `<div class="bayar-flow__center">${inner}</div>` }
  const setLoading = (msg) => center(`<div class="bayar-flow__spin" aria-hidden="true"></div><p>${esc(msg)}</p>`)

  // Sumber kebenaran: langganan aktif/periode maju/sisa naik dibanding sebelum bayar.
  function terdeteksiLunas(s) {
    const akhirNew = s.periode_akhir || ''
    const statusNew = String(s.status || '').toUpperCase()
    return (statusBefore !== 'AKTIF' && statusNew === 'AKTIF') ||
      (!akhirBefore && !!akhirNew) ||
      (akhirBefore && akhirNew && akhirNew > akhirBefore) ||
      (Number(s.sisa_hari || 0) > sisaBefore)
  }

  function setError(msg, { retry = false, cs = false } = {}) {
    center(`
      <div class="bayar-flow__badge bayar-flow__badge--err">${icons.alert}</div>
      <p>${esc(msg)}</p>
      <div class="bayar-flow__actions">
        ${retry ? '<button class="btn btn--primary" type="button" data-retry>Coba lagi</button>' : ''}
        ${cs ? '<button class="btn btn--outline" type="button" data-cs>Hubungi CS</button>' : ''}
        <button class="btn btn--ghost" type="button" data-modal-close>Tutup</button>
      </div>`)
    const r = body.querySelector('[data-retry]'); if (r) r.addEventListener('click', minta)
    const c = body.querySelector('[data-cs]'); if (c) c.addEventListener('click', hubungiCS)
  }

  async function minta() {
    setLoading('Menyiapkan pembayaran…')
    const r = await api.langganan.bayar()
    if (!r.ok) {
      const msg = firstError(r)
      if (r.status === 409) return setError(msg, { cs: true })
      if (r.status === 503) return setError(msg, { retry: true })
      if (r.status === 429) return setError('Terlalu sering mencoba. Tunggu sebentar lalu coba lagi.', { retry: true })
      return setError(msg) // 422/lainnya: JANGAN auto-retry
    }
    showConfirm(r.data || {})
  }

  function showConfirm(data) {
    const inv = data.invoice || {}
    const url = (data.pembayaran || {}).redirect_url
    body.innerHTML = `
      <div class="bayar-flow__confirm">
        <div class="bayar-flow__row"><span>No. tagihan</span><span class="mono">${esc(inv.nomor || '—')}</span></div>
        <div class="bayar-flow__row"><span>Jenis</span><span>${inv.jenis === 'BARU' ? 'Langganan baru' : 'Perpanjangan'}</span></div>
        <div class="bayar-flow__total"><span>Total bayar</span><strong class="num">${fmtIDR(inv.harga_total)}</strong></div>
        <p class="bayar-flow__hint">Pilih metode pembayaran (QRIS / VA / kartu) di jendela berikutnya.</p>
        <div class="bayar-flow__actions">
          <button class="btn btn--ghost" type="button" data-modal-close>Batal</button>
          <button class="btn btn--primary" type="button" data-pay>Bayar Sekarang</button>
        </div>
      </div>`
    body.querySelector('[data-pay]').addEventListener('click', () => bukaBayar(url))
  }

  // Buka halaman Midtrans (in-app di desktop; peramban di Android) & tindaklanjuti hasil.
  async function bukaBayar(url) {
    if (!url) return setError('Halaman pembayaran tidak tersedia. Coba lagi.', { retry: true })
    setLoading('Membuka halaman pembayaran…')
    const r = await api.langganan.jendelaBayar({ url })
    const result = (r && r.ok && r.data && r.data.result) || 'closed'
    if (result === 'settlement' || result === 'capture' || result === 'finished') return verifikasi()
    if (result === 'pending') return setPending()
    if (result === 'external') return setWaiting(url) // Android: bayar di peramban → poll
    return setWaiting(url) // closed/deny/cancel/expire/error → bisa coba lagi
  }

  // Midtrans lapor pembayaran selesai → konfirmasi ke /langganan/status (beberapa kali).
  async function verifikasi() {
    setLoading('Memverifikasi pembayaran…')
    for (let i = 0; i < 4; i++) {
      const r = await api.langganan.status()
      if (r.ok && r.data) { setState({ langganan: r.data }); if (terdeteksiLunas(r.data)) return showSuccess(r.data) }
      await sleep(3000)
    }
    showSuccessSoft() // settle di Midtrans tapi status server belum berubah
  }

  function setWaiting(url) {
    center(`
      <div class="bayar-flow__spin" aria-hidden="true"></div>
      <p class="bayar-flow__title">Menunggu pembayaran…</p>
      <p class="bayar-flow__hint">Selesaikan pembayaran, lalu kembali ke sini. Status diperbarui otomatis.</p>
      <div class="bayar-flow__actions bayar-flow__actions--stack">
        <button class="btn btn--primary" type="button" data-check>Saya sudah bayar</button>
        <button class="btn btn--outline" type="button" data-reopen>Buka ulang halaman pembayaran</button>
        <button class="btn btn--ghost" type="button" data-modal-close>Tutup</button>
      </div>`)
    body.querySelector('[data-check]').addEventListener('click', () => cek(true))
    body.querySelector('[data-reopen]').addEventListener('click', () => bukaBayar(url))
    stop()
    timer = setInterval(() => cek(false), POLL_MS)
  }

  async function cek(manual) {
    const r = await api.langganan.status()
    if (r.ok && r.data) {
      setState({ langganan: r.data })
      if (terdeteksiLunas(r.data)) { stop(); return showSuccess(r.data) }
    }
    if (manual) toast('Pembayaran belum terkonfirmasi. Tunggu sebentar lalu coba lagi.', 'info')
  }

  function setPending() {
    stop()
    center(`
      <div class="bayar-flow__badge bayar-flow__badge--ok">${icons.check}</div>
      <p class="bayar-flow__title">Pembayaran tercatat</p>
      <p class="bayar-flow__hint">Pembayaran Anda sedang diproses. Langganan aktif otomatis setelah dana masuk.</p>
      <div class="bayar-flow__actions"><button class="btn btn--primary" type="button" data-modal-close>Selesai</button></div>`)
  }

  function showSuccess(s) {
    stop()
    center(`
      <div class="bayar-flow__badge bayar-flow__badge--ok">${icons.check}</div>
      <p class="bayar-flow__title">Pembayaran berhasil 🎉</p>
      <p class="bayar-flow__hint">Langganan aktif${s && s.periode_akhir ? ` sampai <strong>${esc(fmtDate(s.periode_akhir))}</strong>` : ''}.</p>
      <div class="bayar-flow__actions"><button class="btn btn--primary" type="button" data-modal-close>Selesai</button></div>`)
    toast('Langganan diperpanjang.', 'success')
  }

  function showSuccessSoft() {
    stop()
    center(`
      <div class="bayar-flow__badge bayar-flow__badge--ok">${icons.check}</div>
      <p class="bayar-flow__title">Pembayaran diterima ✓</p>
      <p class="bayar-flow__hint">Langganan sedang diaktifkan (±beberapa menit). Bila belum aktif, tekan "Periksa status" atau hubungi CS.</p>
      <div class="bayar-flow__actions bayar-flow__actions--stack">
        <button class="btn btn--primary" type="button" data-recheck>Periksa status</button>
        <button class="btn btn--outline" type="button" data-cs>Hubungi CS</button>
        <button class="btn btn--ghost" type="button" data-modal-close>Tutup</button>
      </div>`)
    body.querySelector('[data-recheck]').addEventListener('click', verifikasi)
    const c = body.querySelector('[data-cs]'); if (c) c.addEventListener('click', hubungiCS)
  }

  async function hubungiCS() {
    const r = await api.cs.kontak()
    if (r.ok && r.data && r.data.wa_link) {
      const o = await api.app.openExternal({ url: r.data.wa_link })
      if (!o || !o.ok) { try { window.open(r.data.wa_link, '_blank') } catch (e) { /* abaikan */ } }
    } else toast(firstError(r) || 'Kontak CS belum tersedia.', 'error')
  }

  minta()
}
