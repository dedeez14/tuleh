// Peta Meja — bon berjalan (open bill) untuk warung dine-in.
// Alur (dari spesifikasi Taufiq): buka meja → catat pesanan → simpan ke dapur →
// tambah ronde → cetak bill (belum bayar) → bayar (F4) → meja kembali kosong.
// Satu layar, dua tampilan: PETA (grid meja) dan BON (input pesanan per meja).

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { esc, fmtIDR, fmtNumber } from '../utils/format.js'
import { toast, icons, showModal, confirmDialog, emptyStateHTML, loadingHTML } from '../components/ui.js'
import { printReceipt, buildReceiptHTML, printQR } from '../components/receipt.js'
import { quickCashOptions } from '../lib/cart.js'

const POLL_MS = 5000

export const PetaMejaScreen = {
  id: 'peta-meja',
  title: 'Meja',
  icon: icons.store,

  async render(container) {
    let alive = true
    let view = 'peta' // 'peta' | 'bon'
    let bonAktif = null // ringkasan bon di tampilan BON
    let ronde = [] // keranjang ronde baru: [{ produk, kuantitas }]
    let produkCache = null // katalog toko (dimuat sekali)
    let kategoriAktif = 'SEMUA'
    let qCari = ''
    let gabungMode = false
    let gabungPilih = [] // billId terpilih untuk digabung
    let lastTables = []

    container.innerHTML = `<div id="meja-root" class="meja-root">${loadingHTML('Memuat peta meja…')}</div>`
    const root = container.querySelector('#meja-root')

    // ---------- util ----------
    // Umur bon dalam kata durasi ('12 mnt', '1 j 5 mnt') — lebih jelas dari format jam
    function elapsed(iso) {
      const t = new Date(iso).getTime()
      if (!Number.isFinite(t)) return '—'
      const menit = Math.max(0, Math.floor((Date.now() - t) / 60000))
      const j = Math.floor(menit / 60)
      const m = menit % 60
      return j > 0 ? `${j} j ${m} mnt` : `${m} mnt`
    }

    function statusMeja(bill) {
      if (!bill) return { key: 'kosong', label: 'Kosong' }
      if (bill.status === 'BILL') return { key: 'bill', label: 'Minta bayar' }
      if (!bill.jumlah_item) return { key: 'belum', label: 'Belum order' }
      return { key: 'terisi', label: 'Sudah order' }
    }

    function updateTimers() {
      root.querySelectorAll('[data-since]').forEach((el) => {
        el.textContent = elapsed(el.getAttribute('data-since'))
      })
    }

    // ============================================================ PETA
    async function muatPeta({ loading = false } = {}) {
      if (!alive) return
      if (loading) root.innerHTML = `<div class="meja">${loadingHTML('Memuat peta meja…')}</div>`
      const res = await api.bill.peta()
      if (!alive) return
      if (!res.ok) {
        root.innerHTML = `<div class="meja">${emptyStateHTML({ icon: icons.alert, title: 'Gagal memuat peta meja', desc: firstError(res) })}</div>`
        return
      }
      lastTables = res.data.tables || []
      renderPeta()
    }

    function kartuMeja(t) {
      const st = statusMeja(t.bill)
      const dipilih = gabungMode && t.bill && gabungPilih.includes(t.bill.id)
      const isi = t.bill
        ? `<div class="meja-card__timer num" data-since="${esc(t.bill.dibuka_at)}">${elapsed(t.bill.dibuka_at)}</div>
           <div class="meja-card__pax">${t.bill.pax} org · ${esc(st.label)}</div>
           <div class="meja-card__total num">${fmtIDR(t.bill.total)}</div>
           ${t.bill.meja_ids.length > 1 ? `<div class="meja-card__grp">Gabung ${esc(t.bill.label)}</div>` : ''}`
        : `<div class="meja-card__empty">Ketuk untuk buka</div>`
      return `
        <button type="button" class="meja-card meja-card--${st.key}${dipilih ? ' is-selected' : ''}"
                data-meja="${esc(t.id)}" data-nomor="${esc(t.nomor)}" data-kode="${esc(t.kode)}"
                ${t.bill ? `data-bill="${esc(t.bill.id)}"` : ''}>
          <span class="meja-card__qr" data-qr role="button" title="QR pemesanan mandiri" aria-label="QR pemesanan Meja ${esc(t.nomor)}">${icons.qris}</span>
          <div class="meja-card__no">Meja ${esc(t.nomor)}</div>
          ${isi}
        </button>`
    }

    function renderPeta() {
      const tables = lastTables
      const terisi = tables.filter((t) => t.bill).length
      const q = qCari.trim().toLowerCase()
      const tampil = q
        ? tables.filter((t) => `meja ${t.nomor}`.toLowerCase().includes(q))
        : tables
      root.innerHTML = `
        <div class="meja">
          <div class="meja-head">
            <div>
              <h1 class="meja-title">Peta Meja</h1>
              <p class="meja-sub">${tables.length} meja · ${terisi} terisi · ${tables.length - terisi} kosong</p>
            </div>
            <div class="meja-head__act">
              <div class="search-box meja-cari"><span class="search-box__icon">${icons.search}</span>
                <input class="input" id="meja-cari" type="search" placeholder="Cari meja…" value="${esc(qCari)}" autocomplete="off" />
              </div>
              <button type="button" class="btn btn--sm ${gabungMode ? 'btn--primary' : 'btn--outline'}" id="meja-gabung-mode">
                ${gabungMode ? 'Batal Gabung' : 'Gabung Meja'}
              </button>
              <button type="button" class="icon-btn" id="meja-refresh" title="Muat ulang">${icons.refresh}</button>
            </div>
          </div>
          ${gabungMode ? `
            <div class="meja-gabung-bar">
              <span>Pilih 2+ meja terisi untuk digabung jadi satu bon.</span>
              <button type="button" class="btn btn--primary btn--sm" id="meja-gabung-ok" ${gabungPilih.length < 2 ? 'disabled' : ''}>
                Gabung ${gabungPilih.length ? `(${gabungPilih.length})` : ''}
              </button>
            </div>` : ''}
          <div class="meja-grid${gabungMode ? ' is-gabung' : ''}" id="meja-grid">
            ${tampil.map(kartuMeja).join('') || '<div class="u-muted" style="padding:var(--sp-4)">Tidak ada meja cocok.</div>'}
          </div>
          <div class="meja-legend">
            <span><i class="meja-dot meja-dot--kosong"></i> Kosong</span>
            <span><i class="meja-dot meja-dot--belum"></i> Belum order</span>
            <span><i class="meja-dot meja-dot--terisi"></i> Sudah order</span>
            <span><i class="meja-dot meja-dot--bill"></i> Minta bayar</span>
          </div>
        </div>`

      const cari = root.querySelector('#meja-cari')
      cari.addEventListener('input', () => {
        qCari = cari.value
        // Re-render hanya grid agar fokus input tetap
        const grid = root.querySelector('#meja-grid')
        const qq = qCari.trim().toLowerCase()
        const list = qq ? tables.filter((t) => `meja ${t.nomor}`.toLowerCase().includes(qq)) : tables
        grid.innerHTML = list.map(kartuMeja).join('') || '<div class="u-muted" style="padding:var(--sp-4)">Tidak ada meja cocok.</div>'
      })
      root.querySelector('#meja-refresh').addEventListener('click', () => muatPeta({ loading: true }))
      root.querySelector('#meja-gabung-mode').addEventListener('click', () => {
        gabungMode = !gabungMode
        gabungPilih = []
        renderPeta()
      })
      const okBtn = root.querySelector('#meja-gabung-ok')
      if (okBtn) okBtn.addEventListener('click', lakukanGabung)

      root.querySelector('#meja-grid').addEventListener('click', async (e) => {
        const card = e.target.closest('.meja-card')
        if (!card) return
        if (e.target.closest('[data-qr]')) { tampilkanQR(card.dataset.kode, card.dataset.nomor); return }
        const billId = card.dataset.bill
        if (gabungMode) {
          if (!billId) { toast('Hanya meja terisi yang bisa digabung.', 'info'); return }
          gabungPilih = gabungPilih.includes(billId) ? gabungPilih.filter((x) => x !== billId) : [...gabungPilih, billId]
          renderPeta()
          return
        }
        if (billId) await bukaBonView(billId)
        else await bukaMejaBaru(card.dataset.meja, card.dataset.nomor)
      })
    }

    async function lakukanGabung() {
      if (gabungPilih.length < 2) return
      const [utama, ...rest] = gabungPilih
      let gagal = false
      for (const g of rest) {
        const res = await api.bill.gabung({ idUtama: utama, idGabung: g })
        if (!alive) return
        if (!res.ok) { toast(firstError(res), 'error'); gagal = true; break }
      }
      gabungMode = false
      gabungPilih = []
      if (!gagal) toast('Meja digabung menjadi satu bon.', 'success')
      muatPeta()
    }

    async function tampilkanQR(kode, nomor) {
      const info = await api.app.info()
      if (!alive) return
      const base = info.ok && info.data?.tracking?.running ? info.data.tracking.baseUrl : null
      if (!base) { toast('Server pemesanan mandiri belum aktif — nyalakan di Pengaturan.', 'info'); return }
      const url = `${base}/o/${kode}`
      const res = await api.qr.make({ text: url })
      if (!alive) return
      if (!res.ok) { toast(firstError(res), 'error'); return }
      const body = document.createElement('div')
      body.innerHTML = `
        <div class="tbl-qr">
          <img class="tbl-qr__img" src="${esc(res.data.uri)}" alt="QR Meja ${esc(nomor)}" />
          <div class="tbl-qr__url mono">${esc(url)}</div>
          <div class="tbl-qr__hint">Pelanggan scan untuk pesan sendiri — pesanan masuk ke bon meja ini.</div>
        </div>`
      const footer = document.createElement('div')
      footer.innerHTML = `<button type="button" class="btn btn--primary btn--block" id="tqr-print">${icons.print} Cetak QR Meja</button>`
      const tokoNama = getState().company?.nama || getState().company?.name || 'Tuléh'
      showModal({ title: `QR Meja ${nomor}`, body, footer, size: 'sm' })
      footer.querySelector('#tqr-print').addEventListener('click', () => printQR({ nomor, tokoNama, url, qrUri: res.data.uri }))
    }

    function tanyaPax(nomor) {
      return new Promise((resolve) => {
        let done = false
        const body = document.createElement('div')
        body.innerHTML = `
          <div class="bill-pax-modal">
            <div class="u-muted">Berapa orang di Meja ${esc(nomor)}?</div>
            <div class="bill-pax-modal__ctrl">
              <button type="button" class="step step--lg" data-dec>−</button>
              <input class="input bill-pax-modal__in num" id="px-in" value="2" inputmode="numeric" />
              <button type="button" class="step step--lg" data-inc>+</button>
            </div>
          </div>`
        const footer = document.createElement('div')
        footer.innerHTML = `<button type="button" class="btn btn--ghost" id="px-batal">Batal</button>
          <button type="button" class="btn btn--primary" id="px-ok">Buka Meja</button>`
        const { close } = showModal({ title: `Buka Meja ${nomor}`, body, footer, size: 'sm', onClose: () => { if (!done) resolve(null) } })
        const inp = body.querySelector('#px-in')
        const get = () => parseInt(inp.value, 10) || 1
        body.querySelector('[data-dec]').addEventListener('click', () => { inp.value = String(Math.max(1, get() - 1)) })
        body.querySelector('[data-inc]').addEventListener('click', () => { inp.value = String(Math.min(99, get() + 1)) })
        footer.querySelector('#px-batal').addEventListener('click', () => { done = true; resolve(null); close() })
        footer.querySelector('#px-ok').addEventListener('click', () => { const v = Math.max(1, Math.min(99, get())); done = true; resolve(v); close() })
      })
    }

    async function bukaMejaBaru(mejaId, nomor) {
      const pax = await tanyaPax(nomor)
      if (pax === null || !alive) return
      const res = await api.bill.buka({ mejaId, pax })
      if (!alive) return
      if (!res.ok) { toast(firstError(res), 'error'); muatPeta(); return }
      await bukaBonView(res.data.id)
    }

    // ============================================================ BON
    async function pastikanProduk() {
      if (produkCache) return
      const res = await api.produk.list({ perPage: 100, gudangId: getState().session?.gudang_id })
      produkCache = res.ok && Array.isArray(res.data) ? res.data : []
    }

    // Kembali ke peta dengan pencarian bersih (hindari kata kunci bocor antar-view)
    function kePeta() {
      qCari = ''
      view = 'peta'
      muatPeta({ loading: true })
    }

    async function bukaBonView(billId) {
      const res = await api.bill.detail({ id: billId })
      if (!alive) return
      if (!res.ok) { toast(firstError(res), 'error'); muatPeta(); return }
      bonAktif = res.data
      ronde = []
      view = 'bon'
      qCari = '' // pencarian katalog bon mulai kosong (bukan warisan cari-meja)
      kategoriAktif = 'SEMUA'
      await pastikanProduk()
      if (!alive) return
      renderBon()
    }

    function tambahLokal(produk, delta = 1) {
      const i = ronde.findIndex((l) => l.produk.id === produk.id)
      if (i >= 0) {
        const q = ronde[i].kuantitas + delta
        ronde = q <= 0 ? ronde.filter((_, x) => x !== i) : ronde.map((l, x) => (x === i ? { ...l, kuantitas: q } : l))
      } else if (delta > 0) {
        ronde = [...ronde, { produk, kuantitas: 1 }]
      }
      renderRonde()
    }

    function renderGridBon() {
      const grid = root.querySelector('#bill-grid')
      if (!grid) return
      const q = qCari.trim().toLowerCase()
      let list = produkCache
      if (kategoriAktif !== 'SEMUA') list = list.filter((p) => p.kategori === kategoriAktif)
      if (q) list = list.filter((p) => (p.nama || '').toLowerCase().includes(q))
      grid.innerHTML = list.map((p) => `
        <button type="button" class="bill-prod" data-prod="${esc(p.id)}">
          <span class="bill-prod__nama">${esc(p.nama)}</span>
          <span class="bill-prod__harga num">${fmtIDR(p.harga_jual)}</span>
        </button>`).join('') || '<div class="u-muted" style="padding:var(--sp-4)">Menu tidak ditemukan.</div>'
    }

    function renderRonde() {
      const el = root.querySelector('#bill-ronde')
      if (!el) return
      el.innerHTML = ronde.length
        ? ronde.map((l, i) => `
          <div class="bill-line" data-i="${i}">
            <span class="bill-line__nama">${esc(l.produk.nama)}</span>
            <span class="bill-line__ctrl">
              <button type="button" class="step" data-dec>−</button>
              <span class="num">${fmtNumber(l.kuantitas)}</span>
              <button type="button" class="step" data-inc>+</button>
            </span>
            <span class="bill-line__sub num">${fmtIDR(l.produk.harga_jual * l.kuantitas)}</span>
          </div>`).join('')
        : '<div class="bill-ronde__empty">Ketuk menu untuk menambah pesanan.</div>'
      const simpan = root.querySelector('#bill-simpan')
      if (simpan) simpan.disabled = ronde.length === 0
    }

    function renderTerpesan() {
      const el = root.querySelector('#bill-terpesan')
      if (!el) return
      const items = bonAktif.items || []
      el.innerHTML = items.length
        ? items.map((it) => `
          <div class="bill-item">
            <span class="bill-item__q num">${fmtNumber(it.kuantitas)}×</span>
            <span class="bill-item__nama">${esc(it.nama)}</span>
            <span class="bill-item__sub num">${fmtIDR(it.harga * it.kuantitas)}</span>
          </div>`).join('')
        : '<div class="u-faint" style="padding:var(--sp-2) 0">Belum ada pesanan tersimpan.</div>'
    }

    function renderBon() {
      const b = bonAktif
      const st = statusMeja(b)
      const kategoriSet = ['SEMUA', ...new Set(produkCache.map((p) => p.kategori).filter(Boolean))]
      root.innerHTML = `
        <div class="bill">
          <section class="bill-catalog">
            <div class="bill-catalog__head">
              <button type="button" class="btn btn--ghost btn--sm" id="bill-kembali">← Peta Meja</button>
              <div class="search-box bill-cari"><span class="search-box__icon">${icons.search}</span>
                <input class="input" id="bill-cari" type="search" placeholder="Cari menu…" value="${esc(qCari)}" autocomplete="off" />
              </div>
            </div>
            <div class="bill-chips" id="bill-chips">
              ${kategoriSet.map((k) => `<button type="button" class="bill-chip${k === kategoriAktif ? ' is-active' : ''}" data-kat="${esc(k)}">${k === 'SEMUA' ? 'Semua' : esc(k)}</button>`).join('')}
            </div>
            <div class="bill-grid" id="bill-grid"></div>
          </section>
          <aside class="bill-panel">
            <div class="bill-panel__head">
              <div>
                <div class="bill-panel__meja">${esc(b.label)}</div>
                <div class="bill-panel__meta">
                  <span data-since="${esc(b.dibuka_at)}">${elapsed(b.dibuka_at)}</span> ·
                  <button type="button" class="linklike" id="bill-pax">${b.pax} org</button>
                </div>
              </div>
              <span class="badge badge--${st.key === 'bill' ? 'info' : 'mint'}">${esc(st.label)}</span>
            </div>

            <div class="bill-section__title">Pesanan Baru</div>
            <div class="bill-ronde" id="bill-ronde"></div>
            <button type="button" class="btn btn--primary btn--block" id="bill-simpan" disabled>Simpan Pesanan ke Dapur</button>

            <div class="bill-section__title">Sudah Dipesan${b.ronde ? ` · ${b.ronde} ronde` : ''}</div>
            <div class="bill-terpesan" id="bill-terpesan"></div>

            <div class="bill-total"><span>Total Bon</span><span class="num">${fmtIDR(b.total)}</span></div>
            <div class="bill-actions">
              <button type="button" class="btn btn--outline" id="bill-cetak">Cetak Bill</button>
              <button type="button" class="btn btn--dark" id="bill-bayar">Bayar · F4</button>
            </div>
            <button type="button" class="btn btn--danger-outline btn--sm btn--block bill-batal" id="bill-batal">Kosongkan Meja (batal)</button>
          </aside>
        </div>`

      renderGridBon()
      renderRonde()
      renderTerpesan()

      root.querySelector('#bill-kembali').addEventListener('click', kePeta)
      const cari = root.querySelector('#bill-cari')
      cari.addEventListener('input', () => { qCari = cari.value; renderGridBon() })
      root.querySelector('#bill-chips').addEventListener('click', (e) => {
        const chip = e.target.closest('[data-kat]')
        if (!chip) return
        kategoriAktif = chip.dataset.kat
        root.querySelectorAll('.bill-chip').forEach((c) => c.classList.toggle('is-active', c === chip))
        renderGridBon()
      })
      root.querySelector('#bill-grid').addEventListener('click', (e) => {
        const btn = e.target.closest('[data-prod]')
        if (!btn) return
        const p = produkCache.find((x) => x.id === btn.dataset.prod)
        if (p) tambahLokal(p, 1)
      })
      root.querySelector('#bill-ronde').addEventListener('click', (e) => {
        const line = e.target.closest('.bill-line')
        if (!line) return
        const l = ronde[Number(line.dataset.i)]
        if (!l) return
        if (e.target.closest('[data-inc]')) tambahLokal(l.produk, 1)
        else if (e.target.closest('[data-dec]')) tambahLokal(l.produk, -1)
      })
      root.querySelector('#bill-simpan').addEventListener('click', simpanRonde)
      root.querySelector('#bill-cetak').addEventListener('click', cetakBill)
      root.querySelector('#bill-bayar').addEventListener('click', openBayar)
      root.querySelector('#bill-batal').addEventListener('click', batalBon)
      root.querySelector('#bill-pax').addEventListener('click', ubahPax)
    }

    async function simpanRonde() {
      if (!ronde.length) return
      const btn = root.querySelector('#bill-simpan')
      if (btn) btn.disabled = true
      const items = ronde.map((l) => ({ idProduk: l.produk.id, kuantitas: l.kuantitas }))
      const res = await api.bill.tambahRonde({ id: bonAktif.id, items })
      if (!alive) return
      if (!res.ok) { toast(firstError(res), 'error'); if (btn) btn.disabled = false; return }
      bonAktif = res.data.bill
      ronde = []
      toast(`Pesanan dikirim ke dapur — ${res.data.order.meja}.`, 'success')
      renderBon()
    }

    async function cetakBill() {
      if (ronde.length > 0) { toast('Ada pesanan baru yang belum disimpan — tekan "Simpan Pesanan ke Dapur" dulu.', 'info'); return }
      const res = await api.bill.cetak({ id: bonAktif.id })
      if (!alive) return
      if (!res.ok) { toast(firstError(res), 'error'); return }
      bonAktif = res.data.bill
      const prabon = res.data.prabon
      // Tampilkan "hitungan (belum bayar)" di layar dulu, lalu opsi cetak
      const body = document.createElement('div')
      body.className = 'bill-prabon-preview'
      body.innerHTML = buildReceiptHTML(prabon)
      const footer = document.createElement('div')
      footer.innerHTML = `<button type="button" class="btn btn--ghost" id="pb-tutup">Tutup</button>
        <button type="button" class="btn btn--primary" id="pb-print">${icons.print} Cetak Bill</button>`
      const { close } = showModal({ title: 'Bill — Belum Dibayar', body, footer, size: 'sm' })
      footer.querySelector('#pb-tutup').addEventListener('click', () => close())
      footer.querySelector('#pb-print').addEventListener('click', () => printReceipt(prabon))
      renderBon()
    }

    async function ubahPax() {
      const pax = await tanyaPax(bonAktif.label.replace(/^Meja\s*/i, ''))
      if (pax === null || !alive) return
      const res = await api.bill.setPax({ id: bonAktif.id, pax })
      if (!alive) return
      if (!res.ok) { toast(firstError(res), 'error'); return }
      bonAktif = res.data
      renderBon()
    }

    async function batalBon() {
      const yakin = await confirmDialog({
        title: `Kosongkan ${bonAktif.label}?`,
        message: 'Bon dibatalkan tanpa pembayaran dan meja kembali kosong. Pesanan dapur yang belum selesai ikut dibatalkan.',
        confirmText: 'Ya, kosongkan',
        danger: true
      })
      if (!yakin || !alive) return
      const res = await api.bill.batal({ id: bonAktif.id })
      if (!alive) return
      if (!res.ok) { toast(firstError(res), 'error'); return }
      toast('Meja dikosongkan.', 'info')
      kePeta()
    }

    async function openBayar() {
      if (view !== 'bon' || !bonAktif) return
      if (ronde.length > 0) { toast('Ada pesanan baru yang belum disimpan — tekan "Simpan Pesanan ke Dapur" dulu.', 'info'); return }
      const b = bonAktif
      if (!b.items || !b.items.length) { toast('Bon masih kosong.', 'info'); return }
      const methods = getState().paymentMethods?.length ? getState().paymentMethods : ['TUNAI', 'TRANSFER', 'QRIS']
      let metode = methods[0]
      const body = document.createElement('div')
      body.innerHTML = `
        <div class="bill-pay__total">Total <strong class="num">${fmtIDR(b.total)}</strong> — ${esc(b.label)} · ${b.pax} org</div>
        <div class="segmented bill-pay__methods" id="bp-metode">
          ${methods.map((m, i) => `<button type="button" class="segmented__item${i === 0 ? ' is-active' : ''}" data-m="${esc(m)}">${esc(m)}</button>`).join('')}
        </div>
        <label class="field bill-pay__cash">
          <span class="field__label">Uang diterima (opsional untuk kembalian)</span>
          <input class="input" id="bp-bayar" inputmode="numeric" placeholder="${fmtIDR(b.total)}" />
        </label>
        <div class="bill-pay__saran" id="bp-saran">
          ${quickCashOptions(b.total).map((v, i) => `<button type="button" class="btn btn--outline btn--sm" data-uang="${v}">${i === 0 ? 'Uang Pas' : fmtIDR(v)}</button>`).join('')}
        </div>
        <div class="bill-pay__kembali" id="bp-kembali"></div>`
      const footer = document.createElement('div')
      footer.innerHTML = '<button type="button" class="btn btn--dark btn--block" id="bp-ok">Bayar & Tutup Meja</button>'
      const { close } = showModal({ title: `Pembayaran ${b.label}`, body, footer, size: 'md' })

      const parse = (v) => Number(String(v || '').replace(/[^\d]/g, '')) || 0
      const kembaliEl = body.querySelector('#bp-kembali')
      const bayarInp = body.querySelector('#bp-bayar')
      const hitungKembali = () => {
        const bayar = parse(bayarInp.value)
        if (!bayar) { kembaliEl.textContent = ''; return }
        const k = bayar - b.total
        kembaliEl.textContent = k >= 0 ? `Kembalian: ${fmtIDR(k)}` : `Kurang: ${fmtIDR(-k)}`
        kembaliEl.className = `bill-pay__kembali ${k >= 0 ? 'is-ok' : 'is-kurang'}`
      }
      bayarInp.addEventListener('input', hitungKembali)
      body.querySelector('#bp-saran').addEventListener('click', (e) => {
        const btn = e.target.closest('[data-uang]')
        if (!btn) return
        bayarInp.value = fmtNumber(Number(btn.dataset.uang))
        hitungKembali()
      })
      body.querySelector('#bp-metode').addEventListener('click', (e) => {
        const btn = e.target.closest('[data-m]')
        if (!btn) return
        metode = btn.dataset.m
        body.querySelectorAll('[data-m]').forEach((x) => x.classList.toggle('is-active', x === btn))
      })
      footer.querySelector('#bp-ok').addEventListener('click', async (e) => {
        const bayar = parse(bayarInp.value)
        if (bayar && bayar < b.total) { toast('Uang diterima kurang dari total.', 'error'); return }
        e.currentTarget.disabled = true
        const res = await api.bill.bayar({ id: bonAktif.id, tipePembayaran: metode, dibayar: bayar || undefined })
        if (!alive) return
        if (!res.ok) { e.currentTarget.disabled = false; toast(firstError(res), 'error'); return }
        close()
        showSukses(res.data.struk)
        kePeta()
      })
    }

    function showSukses(struk) {
      const body = document.createElement('div')
      body.innerHTML = `
        <div class="bill-sukses">
          <div class="bill-sukses__ic">${icons.check}</div>
          <div class="bill-sukses__t">${esc(struk.meja || 'Meja')} lunas</div>
          <div class="bill-sukses__v num">${fmtIDR(struk.grand_total)}</div>
          <div class="u-muted">${esc(struk.tipe_pembayaran)}${struk.kembalian > 0 ? ` · kembali ${fmtIDR(struk.kembalian)}` : ''}</div>
        </div>`
      const footer = document.createElement('div')
      footer.innerHTML = `<button type="button" class="btn btn--outline" id="bs-print">Cetak Struk</button>
        <button type="button" class="btn btn--primary" id="bs-ok">Selesai</button>`
      const { close } = showModal({ title: 'Pembayaran Berhasil', body, footer, size: 'sm' })
      footer.querySelector('#bs-print').addEventListener('click', () => printReceipt(struk))
      footer.querySelector('#bs-ok').addEventListener('click', () => close())
    }

    // ---------- keyboard + polling ----------
    function onKey(e) {
      if (e.key === 'F4' && view === 'bon') { e.preventDefault(); openBayar() }
    }
    document.addEventListener('keydown', onKey)

    const tick = setInterval(() => { if (alive) updateTimers() }, 1000)
    // Auto-refresh peta — dilewati saat kasir sedang mengetik di kotak cari meja
    // (agar tidak merebut fokus); timer tetap hidup via tick 1 dtk di atas.
    const poll = setInterval(() => {
      if (alive && view === 'peta' && document.activeElement?.id !== 'meja-cari') muatPeta()
    }, POLL_MS)

    await muatPeta({ loading: true })

    return () => {
      alive = false
      clearInterval(tick)
      clearInterval(poll)
      document.removeEventListener('keydown', onKey)
    }
  }
}
