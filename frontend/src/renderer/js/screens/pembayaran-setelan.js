// Pengaturan → Pembayaran (O/M). Dua lapis:
//  - DASAR: daftar Rekening Bank (maks 5) + QRIS statis (unggah/hapus). Selalu ada.
//  - MIDTRANS: hanya dirender bila data.midtrans.diizinkan === true (saklar platform).
// Server key TIDAK PERNAH disimpan/di-log di app; input pakai type=password.

import { api, firstError } from '../api.js'
import { refreshConfig } from '../app.js'
import { toast } from '../components/ui.js'
import { esc } from '../utils/format.js'

const ACCEPT = 'image/png,image/jpeg,image/webp'
const MAKS_BYTE = 2 * 1024 * 1024

export async function mountPembayaran(host) {
  host.innerHTML = `
    <section class="card">
      <div class="card__header"><h2 class="card__title">Pembayaran</h2></div>
      <div class="card__body" id="pb-body"><div class="field__hint">Memuat pengaturan pembayaran…</div></div>
    </section>`
  const body = host.querySelector('#pb-body')
  const res = await api.pembayaran.get()
  if (!res.ok) {
    body.innerHTML = `<div class="field__hint">${esc(firstError(res) || 'Gagal memuat pengaturan pembayaran.')}</div>
      <div class="set-actions"><button class="btn btn--outline btn--sm" id="pb-retry">Coba lagi</button></div>`
    body.querySelector('#pb-retry').addEventListener('click', () => mountPembayaran(host))
    return
  }
  render(host, res.data || {})
}

function render(host, data) {
  const body = host.querySelector('#pb-body')
  const bank = Array.isArray(data.bank) ? data.bank.slice(0, 5) : []
  const mt = data.midtrans || {}
  body.innerHTML = `
    <h3 class="set-keys__title">Rekening Bank / Transfer</h3>
    <div class="field__hint">Maksimal 5 rekening — ditampilkan di layar bayar Transfer.</div>
    <div id="pb-bank-list" class="pb-bank-list"></div>
    <div class="set-actions">
      <button type="button" class="btn btn--outline btn--sm" id="pb-bank-add">+ Tambah rekening</button>
      <button type="button" class="btn btn--primary btn--sm" id="pb-bank-save">Simpan Rekening</button>
    </div>

    <hr class="divider" />
    <h3 class="set-keys__title">QRIS Statis</h3>
    <div class="pu-logo-row">
      <div class="pu-logo pb-qr">${data.qr_statis ? `<img src="${esc(data.qr_statis)}" alt="QRIS statis" />` : '<span class="pu-logo__ph">Belum ada QR</span>'}</div>
      <div class="pu-logo-info">
        <button type="button" class="btn btn--outline btn--sm" id="pb-qr-upload">Unggah QRIS</button>
        ${data.qr_statis ? '<button type="button" class="btn btn--danger-outline btn--sm" id="pb-qr-hapus">Hapus QR</button>' : ''}
        <div class="field__hint">Gambar QRIS milik usaha (png/jpg/webp, maks 2 MB). Selalu tersedia sebagai fallback saat internet bermasalah.</div>
      </div>
    </div>

    ${mt.diizinkan === true ? midtransHTML(mt) : ''}`

  // --- Rekening bank ---
  const list = body.querySelector('#pb-bank-list')
  const tambahBaris = (r) => list.insertAdjacentHTML('beforeend', bankRowHTML(r || { bank: '', rekening: '', atas_nama: '' }))
  if (bank.length) bank.forEach(tambahBaris); else tambahBaris()
  bindBankRemoval(list)
  body.querySelector('#pb-bank-add').addEventListener('click', () => {
    if (list.querySelectorAll('.pb-bank-row').length >= 5) { toast('Maksimal 5 rekening.', 'info'); return }
    tambahBaris(); bindBankRemoval(list)
  })
  body.querySelector('#pb-bank-save').addEventListener('click', () => simpanBank(host, list))

  // --- QRIS statis ---
  body.querySelector('#pb-qr-upload').addEventListener('click', () => unggahQr(host))
  const hapusQr = body.querySelector('#pb-qr-hapus')
  if (hapusQr) hapusQr.addEventListener('click', () => hapusQrStatis(host))

  // --- Midtrans (bila diizinkan) ---
  if (mt.diizinkan === true) bindMidtrans(host, mt)
}

function bankRowHTML(r) {
  return `
    <div class="pb-bank-row">
      <input class="input pb-bank-bank" maxlength="40" placeholder="Bank / e-wallet" value="${esc(r.bank || '')}" />
      <input class="input pb-bank-rek mono" maxlength="40" placeholder="No. rekening" value="${esc(r.rekening || '')}" />
      <input class="input pb-bank-nama" maxlength="80" placeholder="Atas nama" value="${esc(r.atas_nama || '')}" />
      <button type="button" class="icon-btn pb-bank-del" title="Hapus baris" aria-label="Hapus">✕</button>
    </div>`
}

function bindBankRemoval(list) {
  list.querySelectorAll('.pb-bank-del').forEach((b) => {
    b.onclick = () => {
      const rows = list.querySelectorAll('.pb-bank-row')
      if (rows.length <= 1) { b.closest('.pb-bank-row').querySelectorAll('input').forEach((i) => { i.value = '' }); return }
      b.closest('.pb-bank-row').remove()
    }
  })
}

async function simpanBank(host, list) {
  const bank = []
  list.querySelectorAll('.pb-bank-row').forEach((row) => {
    const b = row.querySelector('.pb-bank-bank').value.trim()
    const rek = row.querySelector('.pb-bank-rek').value.trim()
    const nama = row.querySelector('.pb-bank-nama').value.trim()
    if (b || rek || nama) bank.push({ bank: b, rekening: rek, atas_nama: nama })
  })
  const r = await api.pembayaran.simpan({ bank })
  if (!r.ok) { toast(firstError(r) || 'Gagal menyimpan rekening.', 'error'); return }
  toast('Rekening disimpan.', 'success')
  await refreshConfig()
  render(host, r.data || {})
}

function unggahQr(host) {
  const input = document.createElement('input')
  input.type = 'file'; input.accept = ACCEPT
  input.addEventListener('change', async () => {
    const file = input.files && input.files[0]
    if (!file) return
    if (file.size > MAKS_BYTE) { toast('Ukuran file maksimal 2 MB.', 'error'); return }
    let bytes
    try { bytes = await file.arrayBuffer() } catch { toast('Gagal membaca file.', 'error'); return }
    toast('Mengunggah QRIS…', 'info')
    const r = await api.pembayaran.uploadQr({ bytes, filename: file.name, mime: file.type })
    if (!r.ok) { toast(firstError(r) || 'Gagal mengunggah QRIS.', 'error'); return }
    toast('QRIS statis tersimpan.', 'success')
    await refreshConfig()
    render(host, r.data || {})
  })
  input.click()
}

async function hapusQrStatis(host) {
  const r = await api.pembayaran.simpan({ hapusQr: true })
  if (!r.ok) { toast(firstError(r) || 'Gagal menghapus QRIS.', 'error'); return }
  toast('QRIS statis dihapus.', 'success')
  await refreshConfig()
  render(host, r.data || {})
}

function midtransHTML(mt) {
  if (mt.terpasang) {
    const env = (mt.lingkungan || '').toUpperCase()
    return `
      <hr class="divider" />
      <h3 class="set-keys__title">Midtrans — QRIS Otomatis</h3>
      <div class="pb-mt-head">
        <span class="badge badge--${mt.lingkungan === 'production' ? 'success' : 'info'}">${esc(env || 'TERPASANG')}</span>
        <span class="mono u-faint">${esc(mt.server_key_masked || '')}</span>
      </div>
      <label class="pu-check"><input type="checkbox" id="pb-mt-aktif" ${mt.aktif ? 'checked' : ''} /> <span>Aktifkan QRIS dinamis (terverifikasi)</span></label>
      <div class="field">
        <label class="field__label" for="pb-mt-webhook">Webhook URL (opsional)</label>
        <div class="pb-webhook">
          <input class="input mono" id="pb-mt-webhook" readonly value="${esc(mt.webhook_url || '')}" />
          <button type="button" class="btn btn--outline btn--sm" id="pb-mt-copy">Salin</button>
        </div>
        <div class="field__hint">Tempel di dashboard Midtrans → Settings → Configuration → Payment Notification URL (opsional — mempercepat konfirmasi; tanpa ini QRIS tetap jalan via polling).</div>
      </div>
      <div class="set-actions"><button type="button" class="btn btn--danger-outline btn--sm" id="pb-mt-hapus">Hapus Kredensial</button></div>`
  }
  return `
    <hr class="divider" />
    <h3 class="set-keys__title">Midtrans — QRIS Otomatis</h3>
    <div class="field__hint">Pasang kredensial Midtrans merchant Anda untuk QRIS dinamis terverifikasi. Server Key hanya dikirim ke server (tak disimpan di aplikasi).</div>
    <div class="field"><label class="field__label" for="pb-mt-mid">Merchant ID</label><input class="input" id="pb-mt-mid" autocomplete="off" /></div>
    <div class="field"><label class="field__label" for="pb-mt-ck">Client Key</label><input class="input" id="pb-mt-ck" autocomplete="off" /></div>
    <div class="field"><label class="field__label" for="pb-mt-sk">Server Key</label><input class="input" id="pb-mt-sk" type="password" autocomplete="off" /></div>
    <div class="set-actions"><button type="button" class="btn btn--primary btn--sm" id="pb-mt-save">Pasang & Verifikasi</button></div>`
}

function bindMidtrans(host, mt) {
  const body = host.querySelector('#pb-body')
  if (mt.terpasang) {
    body.querySelector('#pb-mt-aktif').addEventListener('change', async (e) => {
      const r = await api.pembayaran.midtransSimpan({ aktif: e.target.checked })
      if (!r.ok) { toast(firstError(r) || 'Gagal mengubah status.', 'error'); e.target.checked = !e.target.checked; return }
      toast(e.target.checked ? 'QRIS dinamis diaktifkan.' : 'QRIS dinamis dinonaktifkan.', 'success')
      await refreshConfig()
      render(host, r.data || {})
    })
    body.querySelector('#pb-mt-copy').addEventListener('click', async () => {
      const url = body.querySelector('#pb-mt-webhook').value
      try { await navigator.clipboard.writeText(url); toast('Webhook URL disalin.', 'success') }
      catch { const el = body.querySelector('#pb-mt-webhook'); el.select(); document.execCommand('copy'); toast('Webhook URL disalin.', 'success') }
    })
    body.querySelector('#pb-mt-hapus').addEventListener('click', async () => {
      const r = await api.pembayaran.midtransHapus()
      if (!r.ok) { toast(firstError(r) || 'Gagal menghapus kredensial.', 'error'); return }
      toast('Kredensial Midtrans dihapus.', 'success')
      await refreshConfig()
      render(host, r.data || {})
    })
  } else {
    body.querySelector('#pb-mt-save').addEventListener('click', async () => {
      const merchant_id = body.querySelector('#pb-mt-mid').value.trim()
      const client_key = body.querySelector('#pb-mt-ck').value.trim()
      const server_key = body.querySelector('#pb-mt-sk').value.trim()
      if (!merchant_id || !client_key || !server_key) { toast('Lengkapi Merchant ID, Client Key, dan Server Key.', 'error'); return }
      const btn = body.querySelector('#pb-mt-save'); btn.disabled = true
      const r = await api.pembayaran.midtransSimpan({ merchant_id, client_key, server_key })
      btn.disabled = false
      if (!r.ok) { toast(firstError(r) || 'Server Key ditolak Midtrans.', 'error'); return }
      toast('Kredensial Midtrans terverifikasi.', 'success')
      await refreshConfig()
      render(host, r.data || {})
    })
  }
}
