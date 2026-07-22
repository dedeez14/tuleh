// Papan Pesanan generik (KDS dapur / Papan Proses laundry / Antrian).
// Kolom TIDAK di-hardcode — dibaca dari manifest.lifecycle.states toko aktif,
// sehingga satu layar ini melayani bakso (4 tahap) maupun laundry (7 tahap).

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { esc, fmtIDR, fmtNumber, fmtTime, debounce } from '../utils/format.js'
import { toast, icons, emptyStateHTML, loadingHTML, showModal } from '../components/ui.js'

const POLL_MS = 4000
// Ambang umur pesanan: alur pendek (dapur F&B) dihitung menit; alur panjang
// bertahap (laundry dsb., >4 tahap) wajarnya berjam-jam.
const UMUR_CEPAT = { warn: 10, danger: 15 }        // menit
const UMUR_PANJANG = { warn: 240, danger: 480 }    // menit (4 jam / 8 jam)

function fmtUmur(menit) {
  if (menit < 60) return `${menit} mnt`
  return `${Math.floor(menit / 60)} j ${menit % 60} mnt`
}

// Label manusiawi untuk kode tahap yang umum; selain ini → Title Case otomatis
const STAGE_LABELS = {
  MENUNGGU_BAYAR: 'Menunggu Bayar',
  ANTRIAN: 'Antrian',
  DIPROSES: 'Diproses',
  READY: 'Siap',
  PENCUCIAN: 'Pencucian',
  PENGERINGAN: 'Pengeringan',
  LIPAT: 'Lipat & Kemas',
  SIAP_AMBIL: 'Siap Diambil',
  SELESAI: 'Selesai'
}

function stageLabel(stage) {
  if (STAGE_LABELS[stage]) return STAGE_LABELS[stage]
  return String(stage || '')
    .toLowerCase()
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ')
}

function umurMenit(order) {
  const t = new Date(order.created_at).getTime()
  if (!Number.isFinite(t)) return 0
  return Math.max(0, Math.floor((Date.now() - t) / 60000))
}

// Bunyi "ting" singkat saat pesanan baru masuk (tanpa berkas audio)
let audioCtx = null
function ting() {
  try {
    audioCtx = audioCtx || new AudioContext()
    const osc = audioCtx.createOscillator()
    const gain = audioCtx.createGain()
    osc.type = 'sine'
    osc.frequency.value = 1046 // C6
    gain.gain.setValueAtTime(0.15, audioCtx.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.35)
    osc.connect(gain).connect(audioCtx.destination)
    osc.start()
    osc.stop(audioCtx.currentTime + 0.35)
  } catch {
    // Audio tidak tersedia — abaikan
  }
}

export const OrdersScreen = {
  id: 'orders',
  title: 'Pesanan',
  icon: icons.kanban,

  async render(container) {
    const { manifest } = getState()
    const states = manifest?.lifecycle?.states || []

    if (states.length < 2) {
      container.innerHTML = `<div class="screen-page">${emptyStateHTML({
        icon: icons.kanban,
        title: 'Toko ini tidak memakai alur pesanan',
        desc: 'Papan pesanan hanya tersedia untuk bidang usaha dengan tahapan (mis. kuliner atau laundry).'
      })}</div>`
      return
    }

    const terminal = states[states.length - 1]
    const kolom = states.slice(0, -1) // tahap terminal tidak jadi kolom
    const umur = states.length > 4 ? UMUR_PANJANG : UMUR_CEPAT
    let alive = true
    let busy = false
    let idSebelumnya = null // untuk deteksi pesanan baru (bunyi ting)

    container.innerHTML = `
      <div class="ord">
        <div class="ord__bar">
          <div>
            <h1 class="ord__title">Papan Pesanan</h1>
            <p class="ord__sub">Kolom mengikuti tahapan toko — klik tombol pada kartu untuk memajukan pesanan.</p>
          </div>
          <div class="u-flex">
            <span class="ord__tv mono u-faint u-hidden" id="ord-tv"></span>
            <span class="ord__live"><span class="badge__dot"></span> auto-refresh ${POLL_MS / 1000} dtk</span>
            <button type="button" class="icon-btn" id="ord-refresh" title="Muat ulang">${icons.refresh}</button>
          </div>
        </div>
        <div class="ord__board" id="ord-board">${loadingHTML('Memuat pesanan…')}</div>
      </div>`

    const board = container.querySelector('#ord-board')

    function kartuHTML(order, stageIdx) {
      // Order QR meja yang belum dibayar → aksi khusus "Konfirmasi Bayar"
      const belumBayar = order.stage === 'MENUNGGU_BAYAR'
      const next = belumBayar ? states[0] : states[stageIdx + 1]
      const isTerakhir = !belumBayar && next === terminal
      const menit = umurMenit(order)
      const umurCls = menit >= umur.danger ? ' ord-card__age--danger' : menit >= umur.warn ? ' ord-card__age--warn' : ''
      const itemsHTML = (order.items || [])
        .map((i) => `<li><span class="num">${fmtNumber(i.kuantitas)}×</span> ${esc(i.nama)}</li>`)
        .join('')
      return `
        <div class="ord-card${order.meja ? ' ord-card--meja' : ''}" data-id="${esc(order.id)}">
          <div class="ord-card__top">
            ${order.meja
              ? `<span class="ord-card__meja">${esc(order.meja)}</span>`
              : `<span class="ord-card__no mono">${esc(order.no_antrian || order.nomor || '')}</span>`}
            <span class="ord-card__age num${umurCls}">${fmtUmur(menit)}</span>
          </div>
          ${order.meja && order.ronde ? `<div class="ord-card__ronde">Ronde ${esc(order.ronde)}</div>` : ''}
          ${order.pelanggan && order.pelanggan !== order.meja ? `<div class="ord-card__cust">${esc(order.pelanggan)}</div>` : ''}
          ${order.bayar === 'BELUM' && !belumBayar ? '<span class="badge badge--warn">BELUM BAYAR</span>' : ''}
          <ul class="ord-card__items">${itemsHTML}</ul>
          <div class="ord-card__foot">
            <span class="ord-card__meta num">${fmtIDR(order.total)} · ${fmtTime(order.created_at)}</span>
            ${belumBayar
              ? `<button type="button" class="btn btn--sm btn--primary" data-confirm-pay>
                   Konfirmasi Bayar
                 </button>`
              : isTerakhir && order.bayar === 'BELUM'
                ? `<button type="button" class="btn btn--sm btn--dark" data-lunasi>
                     Lunasi & Serahkan
                   </button>`
                : `<button type="button" class="btn btn--sm ${isTerakhir ? 'btn--dark' : 'btn--primary'}"
                          data-next="${esc(next)}">
                    ${isTerakhir ? `${stageLabel(next)} ✓` : `→ ${stageLabel(next)}`}
                  </button>`}
          </div>
        </div>`
    }

    function renderBoard(rows) {
      // Kolom "Menunggu Bayar" (order QR meja) muncul hanya bila ada isinya
      const adaPrePay = rows.some((o) => o.stage === 'MENUNGGU_BAYAR')
      const semuaKolom = adaPrePay ? ['MENUNGGU_BAYAR', ...kolom] : kolom
      board.innerHTML = `
        <div class="ord__cols" style="--ord-cols:${semuaKolom.length}">
          ${semuaKolom.map((stage) => {
            const idx = kolom.indexOf(stage)
            const isi = rows.filter((o) => o.stage === stage)
            return `
              <section class="ord-col">
                <header class="ord-col__head">
                  <span>${esc(stageLabel(stage))}</span>
                  <span class="ord-col__count num">${isi.length}</span>
                </header>
                <div class="ord-col__body">
                  ${isi.length ? isi.map((o) => kartuHTML(o, idx)).join('') : '<div class="ord-col__empty">Tidak ada pesanan</div>'}
                </div>
              </section>`
          }).join('')}
        </div>`
    }

    async function muat({ tampilkanLoading = false } = {}) {
      if (busy) return
      busy = true
      if (tampilkanLoading) board.innerHTML = loadingHTML('Memuat pesanan…')
      const result = await api.order.list({})
      busy = false
      if (!alive) return
      if (!result.ok) {
        board.innerHTML = emptyStateHTML({ icon: icons.alert, title: 'Gagal memuat pesanan', desc: firstError(result) })
        return
      }
      const rows = Array.isArray(result.data) ? result.data : []
      const idSekarang = new Set(rows.map((o) => o.id))
      if (idSebelumnya && [...idSekarang].some((id) => !idSebelumnya.has(id))) ting()
      idSebelumnya = idSekarang
      renderBoard(rows)
    }

    board.addEventListener('click', async (e) => {
      const card = e.target.closest('.ord-card')
      if (!card) return

      const confirmBtn = e.target.closest('[data-confirm-pay]')
      if (confirmBtn) {
        confirmBtn.disabled = true
        const result = await api.order.konfirmasiBayar({ id: card.dataset.id, tipePembayaran: 'TUNAI' })
        if (!alive) return
        if (!result.ok) {
          confirmBtn.disabled = false
          toast(firstError(result), 'error')
          return
        }
        toast(`Pembayaran dikonfirmasi — antrian ${result.data?.no_antrian || ''} masuk dapur.`, 'success')
        muat()
        return
      }

      const lunasiBtn = e.target.closest('[data-lunasi]')
      if (lunasiBtn) {
        // Pelunasan nota bayar-saat-ambil: pilih metode, terbitkan struk, serahkan
        const metodeList = getState().paymentMethods?.length ? getState().paymentMethods : ['TUNAI', 'TRANSFER', 'QRIS']
        const body = document.createElement('div')
        body.innerHTML = `
          <p class="u-muted" style="margin-bottom:var(--sp-3)">
            Pilih metode pembayaran pelunasan — struk akan tercetak dan pesanan
            ditandai selesai/diserahkan.
          </p>
          <div class="segmented" id="lns-metode">
            ${metodeList.map((m, i) => `
              <button type="button" class="segmented__item${i === 0 ? ' is-active' : ''}" data-m="${esc(m)}">${esc(m)}</button>`).join('')}
          </div>`
        const footer = document.createElement('div')
        footer.innerHTML = `<button type="button" class="btn btn--primary" id="lns-ok">Lunasi & Serahkan</button>`
        const { close } = showModal({ title: 'Pelunasan Nota', body, footer })
        let metode = metodeList[0]
        body.querySelector('#lns-metode').addEventListener('click', (ev) => {
          const b = ev.target.closest('[data-m]')
          if (!b) return
          metode = b.dataset.m
          body.querySelectorAll('[data-m]').forEach((x) => x.classList.toggle('is-active', x === b))
        })
        footer.querySelector('#lns-ok').addEventListener('click', async (ev) => {
          ev.currentTarget.disabled = true
          const result = await api.order.lunasi({ id: card.dataset.id, tipePembayaran: metode })
          if (!alive) return
          if (!result.ok) {
            ev.currentTarget.disabled = false
            toast(firstError(result), 'error')
            return
          }
          close()
          toast(`Nota ${result.data?.order?.no_antrian || ''} lunas & diserahkan.`, 'success')
          muat()
        })
        return
      }

      const btn = e.target.closest('[data-next]')
      if (!btn) return
      btn.disabled = true
      const result = await api.order.transition({ id: card.dataset.id, to: btn.dataset.next })
      if (!alive) return
      if (!result.ok) {
        btn.disabled = false
        toast(firstError(result), 'error')
        return
      }
      if (btn.dataset.next === terminal) {
        toast(`Pesanan ${result.data?.no_antrian || ''} selesai.`, 'success')
      }
      muat()
    })

    container.querySelector('#ord-refresh').addEventListener('click', debounce(() => muat({ tampilkanLoading: true }), 200))

    // Tampilkan alamat papan antrian TV bila server LAN aktif
    api.app.info().then((info) => {
      if (!alive || !info.ok) return
      const tracking = info.data?.tracking
      const tvEl = container.querySelector('#ord-tv')
      if (tracking?.running && tvEl) {
        tvEl.textContent = `Layar TV: ${tracking.baseUrl}/antrian`
        tvEl.classList.remove('u-hidden')
      }
    })

    await muat({ tampilkanLoading: true })
    const timer = setInterval(muat, POLL_MS)

    return () => {
      alive = false
      clearInterval(timer)
    }
  }
}
