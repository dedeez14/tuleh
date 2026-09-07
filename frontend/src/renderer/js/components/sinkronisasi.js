// Mode offline di tampilan: pita status di bawah topbar dan panel
// Sinkronisasi (daftar antrean, kirim ulang / batalkan). Padanan Android
// PitaKoneksi + SinkronisasiScreen. Istilah untuk kasir, bukan teknis.

import { api } from '../api.js'
import { esc, fmtIDR, fmtDateTime } from '../utils/format.js'
import { toast, confirmDialog, icons } from './ui.js'

let statusTerakhir = { online: true, ditarikPada: null, menunggu: 0, tinjau: 0, total: 0 }
const pendengar = new Set()

export function statusOffline() { return statusTerakhir }

export function langganStatusOffline(fn) {
  pendengar.add(fn)
  return () => pendengar.delete(fn)
}

function siar(status) {
  statusTerakhir = { ...statusTerakhir, ...(status || {}) }
  for (const fn of pendengar) { try { fn(statusTerakhir) } catch { /* abaikan */ } }
}

/** Mulai memantau status dari main (dipanggil sekali saat boot). */
export function mulaiPantauOffline() {
  if (!api.offline) return
  api.offline.onStatus((s) => siar(s))
  api.offline.status().then((r) => { if (r.ok && r.data) siar(r.data) })
}

function jam(ms) {
  if (!ms) return ''
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

/** Pita status: dipasang oleh kerangka; menyembunyikan diri saat semuanya beres. */
export function pasangPitaOffline(el, { onTinjau }) {
  let sibuk = false
  function render(s) {
    const tampil = !s.online || s.total > 0
    el.hidden = !tampil
    if (!tampil) return
    const bagian = []
    if (!s.online) bagian.push(s.ditarikPada ? `Offline · menampilkan data terakhir ${jam(s.ditarikPada)}` : 'Offline · server tidak terjangkau')
    else bagian.push('Tersambung')
    if (s.menunggu > 0) bagian.push(`${s.menunggu} menunggu dikirim`)
    if (s.tinjau > 0) bagian.push(`${s.tinjau} perlu ditinjau`)
    el.className = `pita-offline${s.online ? ' pita-offline--sinkron' : ''}${s.tinjau > 0 ? ' pita-offline--tinjau' : ''}`
    el.innerHTML = `
      <span class="pita-offline__ikon">${s.online ? icons.check || '' : ''}</span>
      <span class="pita-offline__teks">${esc(bagian.join(' · '))}</span>
      ${s.tinjau > 0 ? '<button type="button" class="btn btn--sm btn--outline" data-act="tinjau">Tinjau</button>' : ''}
      <button type="button" class="btn btn--sm btn--ghost" data-act="coba" ${sibuk ? 'disabled' : ''}>${sibuk ? 'Menyambung…' : (s.online ? 'Sinkron sekarang' : 'Coba lagi')}</button>`
  }
  el.addEventListener('click', async (e) => {
    const btn = e.target.closest('button[data-act]')
    if (!btn) return
    if (btn.dataset.act === 'tinjau') { onTinjau(); return }
    sibuk = true
    render(statusTerakhir)
    const r = await api.offline.sinkron()
    sibuk = false
    if (r.ok) {
      siar(r.data)
      toast(r.data.terkirim > 0 ? `${r.data.terkirim} data terkirim.` : 'Tersambung ke server.', 'success')
    } else {
      toast(r.message || 'Server belum terjangkau.', 'info')
      render(statusTerakhir)
    }
  })
  render(statusTerakhir)
  return langganStatusOffline(render)
}

const LABEL_STATUS = { MENUNGGU: 'Menunggu', MENGIRIM: 'Mengirim…', TINJAU: 'Perlu ditinjau', TERKIRIM: 'Terkirim' }

function ringkasBaris(p) {
  const b = p.body || {}
  switch (p.jenis) {
    case 'CHECKOUT': return `${(b.items || []).length} item · ${b.tipe_pembayaran || ''} · ${fmtIDR(b.dibayar)}`
    case 'PENGELUARAN': return `${b.keterangan || ''} · ${fmtIDR(b.nominal)}`
    case 'STOK_MASUK': return `Jumlah ${b.jumlah}`
    default: return ''
  }
}

/** Panel Sinkronisasi (dipasang di Pengaturan). */
export async function renderPanelSinkronisasi(container) {
  async function muat() {
    const [st, daftar] = await Promise.all([api.offline.status(), api.offline.daftar()])
    const s = st.ok ? st.data : statusTerakhir
    const rows = daftar.ok ? daftar.data : []
    const aktif = rows.filter((p) => p.status !== 'TERKIRIM')
    const terkirim = rows.filter((p) => p.status === 'TERKIRIM').slice(-10).reverse()
    container.innerHTML = `
      <div class="sinkron__status">
        <span class="badge ${s.online ? 'badge--success' : 'badge--warn'}">${s.online ? 'Server terjangkau' : 'Offline'}</span>
        <span class="sinkron__ringkas">${s.menunggu} menunggu dikirim · ${s.tinjau} perlu ditinjau</span>
        <button type="button" class="btn btn--primary btn--sm" data-act="sinkron">Sinkron sekarang</button>
      </div>
      ${aktif.length === 0
        ? '<div class="field__hint">Semua sudah terkirim. Transaksi yang dibuat saat offline akan tampil di sini.</div>'
        : `<div class="sinkron__daftar">${aktif.map((p) => `
          <div class="sinkron__baris${p.status === 'TINJAU' ? ' is-tinjau' : ''}" data-ref="${esc(p.clientRef)}">
            <div class="sinkron__main">
              <div class="sinkron__judul">${esc(p.label)} <span class="badge ${p.status === 'TINJAU' ? 'badge--danger' : 'badge--warn'}">${esc(LABEL_STATUS[p.status] || p.status)}</span></div>
              <div class="sinkron__desc">${esc(ringkasBaris(p))} · dibuat ${fmtDateTime(new Date(p.dibuat).toISOString())}${p.percobaan ? ` · percobaan ke-${p.percobaan}` : ''}</div>
              ${p.galat ? `<div class="sinkron__galat">${esc(p.galat)}</div>` : ''}
            </div>
            ${p.status === 'TINJAU' ? `
              <div class="sinkron__act">
                <button type="button" class="btn btn--outline btn--sm" data-act="batal">Batalkan</button>
                <button type="button" class="btn btn--primary btn--sm" data-act="ulang">Kirim ulang</button>
              </div>` : ''}
          </div>`).join('')}</div>`}
      ${terkirim.length ? `<h3 class="set-keys__title">Terkirim terakhir</h3>
        <div class="sinkron__terkirim">${terkirim.map((p) => `<div class="sinkron__ok">${icons.check || '✓'} ${esc(p.label)} · ${esc((p.hasil && (p.hasil.nomor || p.hasil.no)) || 'selesai')}</div>`).join('')}</div>` : ''}`
  }

  container.addEventListener('click', async (e) => {
    const btn = e.target.closest('button[data-act]')
    if (!btn) return
    const ref = btn.closest('[data-ref]')?.dataset.ref
    if (btn.dataset.act === 'sinkron') {
      btn.disabled = true
      const r = await api.offline.sinkron()
      toast(r.ok ? (r.data.terkirim > 0 ? `${r.data.terkirim} data terkirim.` : 'Sinkronisasi dijalankan.') : (r.message || 'Server belum terjangkau.'), r.ok ? 'success' : 'info')
      await muat()
    } else if (btn.dataset.act === 'ulang' && ref) {
      await api.offline.kirimUlang({ clientRef: ref })
      await muat()
    } else if (btn.dataset.act === 'batal' && ref) {
      const yes = await confirmDialog({
        title: 'Batalkan data ini?',
        message: 'Data dihapus dari komputer ini dan tidak akan dikirim ke server. Stok yang tadi dikurangi dikembalikan di tampilan.',
        confirmText: 'Batalkan',
        danger: true
      })
      if (!yes) return
      await api.offline.batalkan({ clientRef: ref })
      await muat()
    }
  })
  await muat()
  return langganStatusOffline(() => muat())
}
