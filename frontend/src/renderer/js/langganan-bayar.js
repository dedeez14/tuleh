// Alur pembayaran langganan (Midtrans Snap) — kontrak docs/Tuleh-App-Pembayaran-
// Langganan.md. POST /langganan/bayar → dialog konfirmasi (nomor tagihan +
// harga_total) → buka redirect_url di BROWSER SISTEM (bukan webview) → state
// "Menunggu pembayaran…" yang mem-poll /langganan/status. LUNAS hanya dari
// /langganan/status (BUKAN dari kembalinya pengguna). Idempoten & aman diulang.

import { api, firstError } from './api.js'
import { getState, setState } from './state.js'
import { showModal, toast, icons } from './components/ui.js'
import { esc, fmtIDR, fmtDate } from './utils/format.js'

const POLL_MS = 20000 // status di-cache server ±60 dtk; 15–30 dtk wajar

export function mulaiPembayaran() {
  const before = getState().langganan || {}
  const akhirBefore = before.periode_akhir || ''
  const statusBefore = String(before.status || '').toUpperCase()
  const sisaBefore = Number(before.sisa_hari || 0)

  const body = document.createElement('div')
  body.className = 'bayar-flow'
  let timer = null
  const stop = () => { if (timer) { clearInterval(timer); timer = null } }
  const modal = showModal({ title: 'Perpanjang Langganan', body, size: 'sm', onClose: stop })

  function center(inner) { body.innerHTML = `<div class="bayar-flow__center">${inner}</div>` }

  function setLoading(msg) {
    center(`<div class="bayar-flow__spin" aria-hidden="true"></div><p>${esc(msg)}</p>`)
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
      if (r.status === 409) return setError(msg, { cs: true })           // belum punya langganan
      if (r.status === 503) return setError(msg, { retry: true })         // Midtrans gangguan
      if (r.status === 429) return setError('Terlalu sering mencoba. Tunggu sebentar lalu coba lagi.', { retry: true })
      return setError(msg)                                                // 422/lainnya: JANGAN auto-retry
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
        <p class="bayar-flow__hint">Anda akan diarahkan ke halaman pembayaran Midtrans (QRIS / VA / kartu) di peramban perangkat.</p>
        <div class="bayar-flow__actions">
          <button class="btn btn--ghost" type="button" data-modal-close>Batal</button>
          <button class="btn btn--primary" type="button" data-pay>Bayar Sekarang</button>
        </div>
      </div>`
    body.querySelector('[data-pay]').addEventListener('click', () => openAndWait(url))
  }

  async function bukaBrowser(url) {
    if (!url) return
    const r = await api.app.openExternal({ url })
    if (!r || !r.ok) { try { window.open(url, '_blank') } catch (e) { /* abaikan */ } }
  }

  async function openAndWait(url) {
    await bukaBrowser(url)
    setWaiting(url)
    stop()
    timer = setInterval(cek, POLL_MS)
  }

  function setWaiting(url) {
    center(`
      <div class="bayar-flow__spin" aria-hidden="true"></div>
      <p class="bayar-flow__title">Menunggu pembayaran…</p>
      <p class="bayar-flow__hint">Selesaikan pembayaran di peramban, lalu kembali ke sini. Status diperbarui otomatis (±1 menit setelah bayar).</p>
      <div class="bayar-flow__actions bayar-flow__actions--stack">
        <button class="btn btn--primary" type="button" data-check>Saya sudah bayar</button>
        <button class="btn btn--outline" type="button" data-reopen>Buka ulang halaman pembayaran</button>
        <button class="btn btn--ghost" type="button" data-modal-close>Tutup</button>
      </div>`)
    body.querySelector('[data-check]').addEventListener('click', cek)
    body.querySelector('[data-reopen]').addEventListener('click', () => bukaBrowser(url))
  }

  async function cek() {
    const r = await api.langganan.status()
    if (!r.ok || !r.data) return
    const s = r.data
    setState({ langganan: s }) // segarkan banner/notif dari sumber kebenaran
    const akhirNew = s.periode_akhir || ''
    const statusNew = String(s.status || '').toUpperCase()
    const lunas =
      (statusBefore !== 'AKTIF' && statusNew === 'AKTIF') ||
      (!akhirBefore && !!akhirNew) ||
      (akhirBefore && akhirNew && akhirNew > akhirBefore) ||
      (Number(s.sisa_hari || 0) > sisaBefore)
    if (lunas) { stop(); showSuccess(s) }
  }

  function showSuccess(s) {
    center(`
      <div class="bayar-flow__badge bayar-flow__badge--ok">${icons.check}</div>
      <p class="bayar-flow__title">Pembayaran berhasil 🎉</p>
      <p class="bayar-flow__hint">Langganan aktif${s.periode_akhir ? ` sampai <strong>${esc(fmtDate(s.periode_akhir))}</strong>` : ''}.</p>
      <div class="bayar-flow__actions"><button class="btn btn--primary" type="button" data-modal-close>Selesai</button></div>`)
    toast('Langganan diperpanjang.', 'success')
  }

  async function hubungiCS() {
    const r = await api.cs.kontak()
    if (r.ok && r.data && r.data.wa_link) await bukaBrowser(r.data.wa_link)
    else toast(firstError(r) || 'Kontak CS belum tersedia.', 'error')
  }

  minta()
  return modal
}
