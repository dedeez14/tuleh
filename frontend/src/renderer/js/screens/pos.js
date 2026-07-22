// Layar Kasir (POS) — katalog produk, keranjang, dan pembayaran.
// Keranjang disimpan di level modul agar tetap ada saat berpindah layar.

import { api, firstError } from '../api.js'
import { getState, subscribe } from '../state.js'
import { esc, fmtIDR, fmtNumber, parseAmount, debounce } from '../utils/format.js'
import { toast, showModal, confirmDialog, emptyStateHTML, loadingHTML, icons } from '../components/ui.js'
import { buildReceiptHTML, printReceipt } from '../components/receipt.js'
import { lineTotals, cartTotals, kembalian, shortfall, quickCashOptions, clampQty } from '../lib/cart.js'

const PER_PAGE = 50
const SEARCH_DEBOUNCE_MS = 250
const LOW_STOCK_THRESHOLD = 5
const CARD_FEEDBACK_MS = 320
const BARCODE_RE = /^\d{5,}$/

// ---------- State keranjang (module-level, bertahan antar layar) ----------

let cart = [] // [{ produk, kuantitas, diskonPersen }]
let pelanggan = null // { id, nama, kode?, telepon? } | null

function cartLines() {
  return cart.map((l) => ({
    harga: Number(l.produk.harga_jual) || 0,
    kuantitas: Number(l.kuantitas) || 0,
    diskonPersen: Number(l.diskonPersen) || 0,
    pajakPersen: Number(l.produk.pajak_persen) || 0
  }))
}

function stokInfo(produk) {
  const stok = Number(produk.stok)
  return {
    kelolaStok: !!produk.kelola_stok,
    stok: Number.isFinite(stok) ? stok : Infinity
  }
}

function inisialProduk(nama) {
  // Buang tanda baca per kata: 'Sepatu (pasang)' → 'SP'
  const kata = String(nama || '').trim().split(/\s+/)
    .map((w) => w.replace(/[^\p{L}\p{N}]/gu, ''))
    .filter(Boolean)
  const dua = kata.slice(0, 2).map((w) => w[0]).join('')
  return (dua || '?').toUpperCase()
}

// Terima desimal gaya Indonesia (koma) maupun titik: '4,5' → 4.5
function parseDesimal(v) {
  return Number(String(v).trim().replace(',', '.'))
}

// ---------- Layar ----------

export const PosScreen = {
  id: 'pos',
  title: 'Kasir',
  icon: icons.pos,
  async render(container) {
    let innerCleanup = null
    let hasSession = !!getState().session

    const renderInner = () => {
      if (typeof innerCleanup === 'function') {
        try { innerCleanup() } catch (err) { console.error('Cleanup layar kasir gagal:', err) }
        innerCleanup = null
      }
      innerCleanup = getState().session ? renderPos(container) : renderGuard(container)
    }

    const unsubscribe = subscribe((_state, patch) => {
      if (!('session' in patch)) return
      const now = !!getState().session
      if (now !== hasSession) {
        hasSession = now
        renderInner()
      }
    })

    renderInner()

    return () => {
      unsubscribe()
      if (typeof innerCleanup === 'function') {
        try { innerCleanup() } catch (err) { console.error('Cleanup layar kasir gagal:', err) }
        innerCleanup = null
      }
    }
  }
}

// ---------- Guard: belum ada sesi kasir ----------

function renderGuard(container) {
  container.innerHTML = `
    <div class="pos-guard">
      <div class="pos-guard__card">
        <div class="pos-guard__icon">${icons.session}</div>
        <h2 class="pos-guard__title">Belum ada sesi kasir</h2>
        <p class="pos-guard__desc">
          Transaksi hanya bisa dicatat saat sesi kasir terbuka.
          Buka sesi dengan kas awal untuk mulai melayani pelanggan.
        </p>
        <button type="button" class="btn btn--primary btn--lg" id="pos-open-session">
          Buka Sesi Kasir
        </button>
      </div>
    </div>`

  container.querySelector('#pos-open-session').addEventListener('click', async () => {
    const { showScreen } = await import('../app.js')
    showScreen('sessions')
  })
  return null
}

// ---------- Layar kasir utama ----------

function renderPos(container) {
  const kategori = getState().kategori || []
  let disposed = false
  let query = ''
  let kategoriId = ''
  let produkList = []
  let meta = null
  let loadSeq = 0

  container.innerHTML = `
    <div class="pos">
      <section class="pos-catalog" aria-label="Katalog produk">
        <div class="pos-catalog__bar">
          <form class="search-box pos-search" id="pos-search-form">
            <span class="search-box__icon">${icons.barcode}</span>
            <input class="input input--lg" id="pos-search" type="text"
                   placeholder="Cari produk / scan barcode…" autocomplete="off" spellcheck="false" />
            <span class="pos-search__keys"><span class="kbd">F2</span></span>
          </form>
          <div class="pos-chips" id="pos-chips" aria-label="Filter kategori">
            <button type="button" class="pos-chip is-active" data-id="">Semua</button>
            ${kategori.map((k) => `
              <button type="button" class="pos-chip" data-id="${esc(k.id)}">${esc(k.nama)}</button>`).join('')}
          </div>
        </div>
        <div class="pos-catalog__body" id="pos-grid">${loadingHTML('Memuat produk…')}</div>
      </section>

      <aside class="pos-cart" aria-label="Keranjang belanja">
        <div class="pos-cart__head">
          <div>
            <h2 class="pos-cart__title">Keranjang</h2>
            <div class="pos-cart__count" id="pos-count">0 item</div>
          </div>
          <button type="button" class="btn btn--ghost btn--sm" id="pos-clear">Kosongkan</button>
        </div>
        <div class="pos-cart__cust" id="pos-cust"></div>
        <div class="pos-cart__items" id="pos-items"></div>
        <div class="pos-cart__foot">
          <div class="pos-sum" id="pos-sum"></div>
          <button type="button" class="btn btn--primary btn--lg btn--block" id="pos-pay" disabled>
            Bayar <span class="pos-cart__paysep">•</span> <span class="pos-cart__paykey">F4</span>
          </button>
        </div>
      </aside>
    </div>`

  const searchForm = container.querySelector('#pos-search-form')
  const searchInput = container.querySelector('#pos-search')
  const chipsEl = container.querySelector('#pos-chips')
  const gridEl = container.querySelector('#pos-grid')
  const custEl = container.querySelector('#pos-cust')
  const itemsEl = container.querySelector('#pos-items')
  const sumEl = container.querySelector('#pos-sum')
  const countEl = container.querySelector('#pos-count')
  const payBtn = container.querySelector('#pos-pay')
  const clearBtn = container.querySelector('#pos-clear')

  // ---------- Katalog produk ----------

  function produkCardHTML(p) {
    const { kelolaStok, stok } = stokInfo(p)
    const habis = kelolaStok && stok <= 0
    let badge = ''
    if (habis) {
      badge = `<span class="badge badge--danger pos-card__badge">Habis</span>`
    } else if (kelolaStok && stok < LOW_STOCK_THRESHOLD) {
      badge = `<span class="badge badge--warn pos-card__badge">Sisa ${fmtNumber(stok)}</span>`
    }
    const media = p.gambar
      ? `<img class="pos-card__img" src="${esc(p.gambar)}" alt="" loading="lazy" />`
      : `<div class="pos-card__initial" aria-hidden="true">${esc(inisialProduk(p.nama))}</div>`
    return `
      <button type="button" class="pos-card" data-id="${esc(p.id)}" ${habis ? 'disabled' : ''}>
        <div class="pos-card__media">${media}${badge}</div>
        <div class="pos-card__name">${esc(p.nama)}</div>
        <div class="pos-card__code mono">${esc(p.kode)}</div>
        <div class="pos-card__price num">${fmtIDR(p.harga_jual)}</div>
      </button>`
  }

  function renderGrid() {
    if (!produkList.length) {
      gridEl.innerHTML = emptyStateHTML({
        icon: icons.box,
        title: 'Produk tidak ditemukan',
        desc: query
          ? `Tidak ada produk yang cocok dengan "${query}". Coba kata kunci lain.`
          : 'Belum ada produk pada kategori ini.'
      })
      return
    }
    const hasMore = meta && Number(meta.current_page) < Number(meta.last_page)
    gridEl.innerHTML = `
      <div class="pos-grid">${produkList.map(produkCardHTML).join('')}</div>
      ${hasMore ? `
        <div class="pos-more">
          <button type="button" class="btn btn--outline" id="pos-more-btn">Muat lebih banyak</button>
          <span class="pos-more__info">${fmtNumber(produkList.length)} dari ${fmtNumber(meta.total)} produk</span>
        </div>` : ''}`
  }

  async function loadProduk({ append = false } = {}) {
    const seq = ++loadSeq
    const page = append && meta ? Number(meta.current_page) + 1 : 1
    const moreBtn = gridEl.querySelector('#pos-more-btn')
    if (append && moreBtn) {
      moreBtn.disabled = true
      moreBtn.textContent = 'Memuat…'
    }
    if (!append) gridEl.innerHTML = loadingHTML('Memuat produk…')

    const result = await api.produk.list({
      q: query || undefined,
      kategoriId: kategoriId || undefined,
      gudangId: getState().session?.gudang_id,
      perPage: PER_PAGE,
      page
    })
    if (disposed || seq !== loadSeq) return

    if (!result.ok) {
      const message = firstError(result)
      if (append) {
        toast(message, 'error')
        const btn = gridEl.querySelector('#pos-more-btn')
        if (btn) {
          btn.disabled = false
          btn.textContent = 'Muat lebih banyak'
        }
      } else {
        gridEl.innerHTML = emptyStateHTML({ icon: icons.alert, title: 'Gagal memuat produk', desc: message })
      }
      return
    }

    meta = result.meta || null
    produkList = append ? [...produkList, ...(result.data || [])] : (result.data || [])
    renderGrid()
  }

  // ---------- Keranjang ----------

  function tambahJumlah(produk, jumlah) {
    const { kelolaStok, stok } = stokInfo(produk)
    const existing = cart.find((l) => String(l.produk.id) === String(produk.id))
    const current = existing ? Number(existing.kuantitas) : 0
    const next = clampQty(current + jumlah, { kelolaStok, stok })
    if (next <= current) {
      toast(`Stok "${produk.nama}" tinggal ${fmtNumber(stok)} dan sudah semua di keranjang.`, 'error')
      return false
    }
    cart = existing
      ? cart.map((l) => (l === existing ? { ...l, kuantitas: next } : l))
      : [...cart, { produk, kuantitas: next, diskonPersen: 0 }]
    renderCart()
    // Baris baru: gulir keranjang ke bawah agar kasir melihat item masuk
    if (!existing) itemsEl.scrollTop = itemsEl.scrollHeight
    return true
  }

  // Layanan kiloan (satuan Kg): tanya berat hasil timbangan, bukan langsung 1
  function bukaInputBerat(produk) {
    const body = document.createElement('div')
    body.innerHTML = `
      <div class="field">
        <label class="field__label" for="berat-in">Berat hasil timbangan (kg)</label>
        <input class="input input--lg num" id="berat-in" type="text" inputmode="decimal"
               placeholder="mis. 4,5" autocomplete="off" />
        <div class="field__hint num" id="berat-view">${fmtIDR(produk.harga_jual)} / kg</div>
      </div>
      <div class="u-flex" id="berat-cepat" style="flex-wrap:wrap">
        ${[1, 2, 3, 4, 5].map((n) => `
          <button type="button" class="btn btn--outline btn--sm" data-kg="${n}">${n} kg</button>`).join('')}
      </div>`
    const footer = document.createElement('div')
    footer.innerHTML = `<button type="button" class="btn btn--primary" id="berat-ok">Tambah ke Keranjang</button>`

    const { close } = showModal({ title: produk.nama, body, footer })
    const input = body.querySelector('#berat-in')
    const view = body.querySelector('#berat-view')

    input.addEventListener('input', () => {
      const kg = parseDesimal(input.value) || 0
      view.textContent = kg > 0
        ? `${fmtNumber(kg)} kg × ${fmtIDR(produk.harga_jual)} = ${fmtIDR(kg * produk.harga_jual)}`
        : `${fmtIDR(produk.harga_jual)} / kg`
    })

    body.querySelector('#berat-cepat').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-kg]')
      if (!btn) return
      input.value = btn.dataset.kg
      input.dispatchEvent(new Event('input'))
      input.focus()
    })

    const submit = () => {
      const kg = parseDesimal(input.value)
      if (!Number.isFinite(kg) || kg <= 0) {
        toast('Isi berat yang valid (mis. 4,5).', 'error')
        return
      }
      if (tambahJumlah(produk, Math.round(kg * 100) / 100)) close()
    }
    footer.querySelector('#berat-ok').addEventListener('click', submit)
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') submit()
    })
  }

  function addToCart(produk) {
    const { kelolaStok, stok } = stokInfo(produk)
    if (kelolaStok && stok <= 0) {
      toast(`Stok "${produk.nama}" sudah habis.`, 'error')
      return false
    }
    if (String(produk.satuan || '').toLowerCase() === 'kg') {
      bukaInputBerat(produk)
      return true
    }
    return tambahJumlah(produk, 1)
  }

  function setQty(line, rawQty) {
    const { kelolaStok, stok } = stokInfo(line.produk)
    const qty = clampQty(rawQty, { kelolaStok, stok })
    if (kelolaStok && Number(rawQty) > qty) {
      toast(`Stok "${line.produk.nama}" hanya ${fmtNumber(stok)}.`, 'error')
    }
    cart = qty <= 0
      ? cart.filter((l) => l !== line)
      : cart.map((l) => (l === line ? { ...l, kuantitas: qty } : l))
    renderCart()
  }

  function setDiskon(line, raw) {
    let v = Number(raw)
    if (!Number.isFinite(v) || v < 0) v = 0
    if (v > 100) v = 100
    cart = cart.map((l) => (l === line ? { ...l, diskonPersen: v } : l))
    renderCart()
  }

  function lineHTML(l) {
    const p = l.produk
    const line = lineTotals({
      harga: p.harga_jual,
      kuantitas: l.kuantitas,
      diskonPersen: l.diskonPersen,
      pajakPersen: p.pajak_persen
    })
    return `
      <div class="pos-line" data-id="${esc(p.id)}">
        <div class="pos-line__head">
          <span class="pos-line__name u-truncate" title="${esc(p.nama)}">${esc(p.nama)}</span>
          <button type="button" class="pos-line__del" data-act="del" aria-label="Hapus ${esc(p.nama)}">
            ${icons.trash}
          </button>
        </div>
        <div class="pos-line__price num">
          ${fmtIDR(p.harga_jual)}${p.satuan ? ` <span class="pos-line__unit">/ ${esc(p.satuan)}</span>` : ''}
        </div>
        <div class="pos-line__ctrl">
          <div class="pos-step">
            <button type="button" class="icon-btn pos-step__btn" data-act="minus" aria-label="Kurangi jumlah">
              ${icons.minus}
            </button>
            <input class="pos-step__qty num" data-act="qty" type="number" min="0" step="any"
                   value="${Number(l.kuantitas)}" aria-label="Jumlah" />
            <button type="button" class="icon-btn pos-step__btn" data-act="plus" aria-label="Tambah jumlah">
              ${icons.plus}
            </button>
          </div>
          <label class="pos-line__disc" title="Diskon baris (%)">
            <span class="pos-line__disc-label">Disk.</span>
            <input class="pos-line__disc-input num" data-act="disc" type="number" min="0" max="100" step="any"
                   value="${Number(l.diskonPersen) || 0}" aria-label="Diskon persen" /><span>%</span>
          </label>
          <span class="pos-line__total num">${fmtIDR(line.total)}</span>
        </div>
      </div>`
  }

  function renderCustomer() {
    if (pelanggan) {
      custEl.innerHTML = `
        <div class="pos-cust-chip">
          <span class="pos-cust-chip__icon">${icons.user}</span>
          <span class="u-truncate">${esc(pelanggan.nama)}</span>
          <button type="button" class="pos-cust-chip__x" data-act="cust-clear" aria-label="Lepas pelanggan">
            ${icons.x}
          </button>
        </div>`
    } else {
      custEl.innerHTML = `
        <button type="button" class="btn btn--outline btn--sm" data-act="cust-add">
          ${icons.user}<span>+ Pelanggan</span>
        </button>`
    }
  }

  function renderSummary(totals) {
    // Baris diskon hanya merah/minus saat ada diskon
    const adaDiskon = Number(totals.totalDiskon) > 0
    sumEl.innerHTML = `
      <div class="pos-sum__row"><span>Subtotal</span><span class="num">${fmtIDR(totals.subtotal)}</span></div>
      <div class="pos-sum__row${adaDiskon ? ' pos-sum__row--disc' : ''}"><span>Diskon</span><span class="num">${adaDiskon ? '−' : ''}${fmtIDR(totals.totalDiskon)}</span></div>
      <div class="pos-sum__row"><span>Pajak</span><span class="num">${fmtIDR(totals.totalPajak)}</span></div>
      <div class="pos-sum__total">
        <span class="pos-sum__total-label">Total</span>
        <span class="pos-sum__total-value num">${fmtIDR(totals.grandTotal)}</span>
      </div>`
  }

  function renderCart() {
    if (disposed) return
    const totals = cartTotals(cartLines())
    countEl.textContent = cart.length
      ? `${cart.length} item • ${fmtNumber(totals.qtyCount)} qty`
      : '0 item'
    renderCustomer()
    itemsEl.innerHTML = cart.length
      ? cart.map(lineHTML).join('')
      : emptyStateHTML({
          icon: icons.box,
          title: 'Keranjang kosong',
          desc: 'Klik produk di katalog atau scan barcode untuk menambahkan.'
        })
    renderSummary(totals)
    payBtn.disabled = cart.length === 0
    clearBtn.disabled = cart.length === 0
  }

  // ---------- Modal pelanggan ----------

  function openCustomerModal() {
    const body = document.createElement('div')
    body.className = 'pos-cust-modal'
    body.innerHTML = `
      <div class="search-box">
        <span class="search-box__icon">${icons.search}</span>
        <input class="input" id="cust-q" type="text" placeholder="Cari nama atau telepon…" autocomplete="off" />
      </div>
      <div class="pos-cust-results" id="cust-results">${loadingHTML('Memuat pelanggan…')}</div>
      <button type="button" class="pos-cust-newlink" id="cust-newlink">
        ${icons.plus}<span>Tambah pelanggan baru</span>
      </button>
      <form class="pos-cust-form u-hidden" id="cust-form" novalidate>
        <div class="field">
          <label class="field__label" for="cust-nama">Nama pelanggan</label>
          <input class="input" id="cust-nama" type="text" maxlength="150" required />
        </div>
        <div class="field">
          <label class="field__label" for="cust-telp">Telepon (opsional)</label>
          <input class="input" id="cust-telp" type="tel" maxlength="30" />
        </div>
        <div class="field__error u-hidden" id="cust-error"></div>
        <button type="submit" class="btn btn--primary btn--block" id="cust-save">Simpan &amp; pilih</button>
      </form>`

    const { close } = showModal({ title: 'Pilih Pelanggan', body })

    const qInput = body.querySelector('#cust-q')
    const resultsEl = body.querySelector('#cust-results')
    const formEl = body.querySelector('#cust-form')
    const errEl = body.querySelector('#cust-error')
    const saveBtn = body.querySelector('#cust-save')
    let rows = []
    let custSeq = 0

    async function cariPelanggan(q) {
      const seq = ++custSeq
      resultsEl.innerHTML = loadingHTML('Mencari pelanggan…')
      const result = await api.pelanggan.list({ q: q || undefined })
      if (seq !== custSeq) return
      if (!result.ok) {
        resultsEl.innerHTML = emptyStateHTML({
          icon: icons.alert, title: 'Gagal memuat pelanggan', desc: firstError(result)
        })
        return
      }
      rows = result.data || []
      if (!rows.length) {
        resultsEl.innerHTML = emptyStateHTML({
          icon: icons.user,
          title: 'Pelanggan tidak ditemukan',
          desc: 'Coba kata kunci lain, atau tambah pelanggan baru di bawah.'
        })
        return
      }
      resultsEl.innerHTML = rows.map((p) => `
        <button type="button" class="pos-cust-item" data-id="${esc(p.id)}">
          <span class="pos-cust-item__name">${esc(p.nama)}</span>
          <span class="pos-cust-item__sub">${esc(p.kode || '')}${p.telepon ? ` • ${esc(p.telepon)}` : ''}</span>
        </button>`).join('')
    }

    qInput.addEventListener('input', debounce(() => cariPelanggan(qInput.value.trim()), SEARCH_DEBOUNCE_MS))
    cariPelanggan('')

    resultsEl.addEventListener('click', (e) => {
      const item = e.target.closest('.pos-cust-item')
      if (!item) return
      const chosen = rows.find((p) => String(p.id) === item.dataset.id)
      if (!chosen) return
      pelanggan = chosen
      renderCart()
      close()
    })

    body.querySelector('#cust-newlink').addEventListener('click', () => {
      formEl.classList.toggle('u-hidden')
      if (!formEl.classList.contains('u-hidden')) body.querySelector('#cust-nama').focus()
    })

    formEl.addEventListener('submit', async (e) => {
      e.preventDefault()
      errEl.classList.add('u-hidden')
      const nama = body.querySelector('#cust-nama').value.trim()
      const telepon = body.querySelector('#cust-telp').value.trim()
      if (!nama) {
        errEl.textContent = 'Nama pelanggan wajib diisi.'
        errEl.classList.remove('u-hidden')
        return
      }
      saveBtn.disabled = true
      saveBtn.textContent = 'Menyimpan…'
      const result = await api.pelanggan.create({ nama, telepon: telepon || undefined })
      if (!result.ok) {
        saveBtn.disabled = false
        saveBtn.innerHTML = 'Simpan &amp; pilih'
        errEl.textContent = firstError(result)
        errEl.classList.remove('u-hidden')
        return
      }
      pelanggan = result.data || { nama }
      renderCart()
      toast(`Pelanggan "${nama}" ditambahkan.`, 'success')
      close()
    })
  }

  // ---------- Modal pembayaran ----------

  function openPaymentModal() {
    if (!cart.length || document.querySelector('.modal-overlay')) return

    const grandTotal = cartTotals(cartLines()).grandTotal
    const stateNow = getState()
    const methods = Array.isArray(stateNow.paymentMethods) && stateNow.paymentMethods.length
      ? stateNow.paymentMethods
      : ['TUNAI', 'TRANSFER', 'QRIS']
    let metode = methods.includes('TUNAI') ? 'TUNAI' : methods[0]

    const body = document.createElement('div')
    body.className = 'pos-pay'
    body.innerHTML = `
      <div class="segmented pos-pay__methods" id="pay-methods">
        ${methods.map((m) => `
          <button type="button" class="segmented__item pos-pay__method" data-metode="${esc(m)}">${esc(m)}</button>`).join('')}
      </div>
      <div class="pos-pay__bill">
        <span class="pos-pay__bill-label">Total tagihan</span>
        <span class="pos-pay__bill-amount num">${fmtIDR(grandTotal)}</span>
      </div>
      <div class="field">
        <label class="field__label" for="pay-input">Dibayar</label>
        <input class="input input--lg num" id="pay-input" type="text" inputmode="numeric"
               placeholder="0" autocomplete="off" />
        <div class="field__hint num" id="pay-fmt">${fmtIDR(0)}</div>
      </div>
      <div class="pos-pay__quick" id="pay-quick"></div>
      <div class="pos-pay__status" id="pay-status"></div>
      <div class="field">
        <label class="field__label" for="pay-note">Catatan (opsional)</label>
        <textarea class="textarea" id="pay-note" rows="2" placeholder="Misal: pesanan dibungkus"></textarea>
      </div>
      <div class="field__error u-hidden" id="pay-error"></div>`

    // Toko dengan alur "bayar saat ambil" (mis. laundry) dapat menyimpan nota
    // tanpa pembayaran — pelunasan dilakukan di Papan Proses saat penyerahan.
    const bolehBayarNanti = (getState().manifest?.transactionFlow || []).includes('PAYMENT_OR_LATER')

    const footer = document.createElement('div')
    footer.className = 'pos-pay__footer'
    footer.innerHTML = `
      ${bolehBayarNanti ? `
        <button type="button" class="btn btn--outline btn--block" id="pay-later">
          Simpan Nota — Bayar Saat Ambil
        </button>` : ''}
      <button type="button" class="btn btn--primary btn--lg btn--block" id="pay-submit" disabled>
        Selesaikan Transaksi
      </button>`

    const modal = showModal({
      title: 'Pembayaran',
      body,
      footer,
      size: 'md',
      onClose: () => {
        if (!disposed && document.contains(searchInput)) searchInput.focus()
      }
    })

    const payInput = body.querySelector('#pay-input')
    const payFmt = body.querySelector('#pay-fmt')
    const quickEl = body.querySelector('#pay-quick')
    const statusEl = body.querySelector('#pay-status')
    const noteEl = body.querySelector('#pay-note')
    const errorEl = body.querySelector('#pay-error')
    const submitBtn = footer.querySelector('#pay-submit')

    function updateStatus() {
      const dibayar = parseAmount(payInput.value)
      payFmt.textContent = fmtIDR(dibayar)
      const kurang = shortfall(dibayar, grandTotal)
      if (!payInput.value.trim()) {
        statusEl.className = 'pos-pay__status pos-pay__status--idle'
        statusEl.textContent = 'Masukkan uang diterima atau pilih nominal cepat.'
      } else if (kurang > 0) {
        statusEl.className = 'pos-pay__status pos-pay__status--short'
        statusEl.innerHTML = `<span>Kurang</span><span class="num">${fmtIDR(kurang)}</span>`
      } else {
        statusEl.className = 'pos-pay__status pos-pay__status--ok'
        statusEl.innerHTML = `<span>Kembalian</span><span class="num">${fmtIDR(kembalian(dibayar, grandTotal))}</span>`
      }
      submitBtn.disabled = kurang > 0
    }

    function applyMetode() {
      body.querySelectorAll('.pos-pay__method').forEach((btn) => {
        btn.classList.toggle('is-active', btn.dataset.metode === metode)
      })
      if (metode === 'TUNAI') {
        quickEl.classList.remove('u-hidden')
        quickEl.innerHTML = quickCashOptions(grandTotal)
          .map((v) => `<button type="button" class="pos-pay__cash num" data-value="${v}">${Number(v) === grandTotal ? 'Uang Pas' : fmtIDR(v)}</button>`)
          .join('')
      } else {
        quickEl.classList.add('u-hidden')
        payInput.value = fmtNumber(grandTotal)
      }
      updateStatus()
      payInput.focus()
      payInput.select()
    }

    body.querySelector('#pay-methods').addEventListener('click', (e) => {
      const btn = e.target.closest('.pos-pay__method')
      if (!btn) return
      metode = btn.dataset.metode
      applyMetode()
    })

    quickEl.addEventListener('click', (e) => {
      const btn = e.target.closest('.pos-pay__cash')
      if (!btn) return
      payInput.value = fmtNumber(Number(btn.dataset.value))
      updateStatus()
      payInput.focus()
    })

    payInput.addEventListener('input', updateStatus)
    payInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !submitBtn.disabled) submitBtn.click()
    })

    function showSuccess(struk) {
      const change = Number(struk.kembalian) || 0
      body.className = ''
      body.innerHTML = `
        <div class="pos-done">
          <div class="pos-done__icon">${icons.check}</div>
          <div class="pos-done__title">Transaksi berhasil</div>
          <div class="pos-done__no mono">${esc(struk.nomor || '')}</div>
          ${struk.no_antrian ? `
            <div class="pos-done__queue">
              <span class="pos-done__queue-label">Nomor Antrian</span>
              <span class="pos-done__queue-no mono">${esc(struk.no_antrian)}</span>
            </div>` : ''}
          ${change > 0 ? `
            <div class="pos-done__change">
              <span>Kembalian</span>
              <span class="pos-done__change-val num">${fmtIDR(change)}</span>
            </div>` : ''}
          <div class="pos-done__receipt">${buildReceiptHTML(struk)}</div>
        </div>`
      footer.className = 'pos-done__actions'
      footer.innerHTML = `
        <button type="button" class="btn btn--outline" id="pay-print">${icons.print}<span>Cetak Struk</span></button>
        <button type="button" class="btn btn--primary" id="pay-new">Transaksi Baru</button>`
      footer.querySelector('#pay-print').addEventListener('click', () => printReceipt(struk))
      footer.querySelector('#pay-new').addEventListener('click', () => modal.close())
    }

    async function submitCheckout() {
      const dibayar = parseAmount(payInput.value)
      if (shortfall(dibayar, grandTotal) > 0) return
      errorEl.classList.add('u-hidden')
      submitBtn.disabled = true
      submitBtn.textContent = 'Memproses…'

      const result = await api.trx.checkout({
        items: cart.map((l) => ({
          idProduk: l.produk.id,
          harga: Number(l.produk.harga_jual) || 0,
          kuantitas: Number(l.kuantitas) || 0,
          diskonPersen: Number(l.diskonPersen) || 0,
          pajakPersen: Number(l.produk.pajak_persen) || 0
        })),
        tipePembayaran: metode,
        dibayar,
        idPelanggan: pelanggan ? pelanggan.id : undefined,
        catatan: noteEl.value.trim() || undefined
      })

      if (!result.ok) {
        submitBtn.disabled = false
        submitBtn.textContent = 'Selesaikan Transaksi'
        errorEl.textContent = firstError(result)
        errorEl.classList.remove('u-hidden')
        if (result.status === 409 && !footer.querySelector('#pay-goto-session')) {
          const gotoBtn = document.createElement('button')
          gotoBtn.type = 'button'
          gotoBtn.id = 'pay-goto-session'
          gotoBtn.className = 'btn btn--outline btn--block'
          gotoBtn.textContent = 'Buka Sesi Kasir'
          gotoBtn.addEventListener('click', async () => {
            modal.close()
            const { showScreen } = await import('../app.js')
            showScreen('sessions')
          })
          footer.prepend(gotoBtn)
        }
        return
      }

      // Transaksi tercatat — kosongkan keranjang & segarkan stok katalog.
      cart = []
      pelanggan = null
      if (!disposed) {
        renderCart()
        loadProduk()
      }
      showSuccess(result.data)
    }

    submitBtn.addEventListener('click', submitCheckout)

    const laterBtn = footer.querySelector('#pay-later')
    if (laterBtn) {
      laterBtn.addEventListener('click', async () => {
        laterBtn.disabled = true
        laterBtn.textContent = 'Menyimpan nota…'
        const result = await api.order.simpanNota({
          items: cart.map((l) => ({
            idProduk: l.produk.id,
            harga: Number(l.produk.harga_jual) || 0,
            kuantitas: Number(l.kuantitas) || 0
          })),
          idPelanggan: pelanggan ? pelanggan.id : undefined,
          catatan: noteEl.value.trim() || undefined
        })
        if (!result.ok) {
          laterBtn.disabled = false
          laterBtn.textContent = 'Simpan Nota — Bayar Saat Ambil'
          errorEl.textContent = firstError(result)
          errorEl.classList.remove('u-hidden')
          return
        }
        cart = []
        pelanggan = null
        if (!disposed) renderCart()
        // Panel sukses memakai nota tanda-terima (belum lunas) + QR lacak
        showSuccess(result.data.nota)
      })
    }

    applyMetode()
  }

  // ---------- Event katalog ----------

  gridEl.addEventListener('click', (e) => {
    if (e.target.closest('#pos-more-btn')) {
      loadProduk({ append: true })
      return
    }
    const card = e.target.closest('.pos-card')
    if (!card || card.disabled) return
    const produk = produkList.find((p) => String(p.id) === card.dataset.id)
    if (!produk) return
    if (addToCart(produk)) {
      card.classList.remove('is-added')
      void card.offsetWidth
      card.classList.add('is-added')
      setTimeout(() => card.classList.remove('is-added'), CARD_FEEDBACK_MS)
    }
  })

  chipsEl.addEventListener('click', (e) => {
    const chip = e.target.closest('.pos-chip')
    if (!chip || chip.classList.contains('is-active')) return
    chipsEl.querySelectorAll('.pos-chip').forEach((c) => c.classList.toggle('is-active', c === chip))
    kategoriId = chip.dataset.id || ''
    loadProduk()
  })

  searchInput.addEventListener('input', debounce(() => {
    if (disposed) return
    const value = searchInput.value.trim()
    if (value === query) return
    query = value
    loadProduk()
  }, SEARCH_DEBOUNCE_MS))

  // Enter di kotak cari: barcode dulu (alur scanner fisik), 404 → pencarian teks.
  searchForm.addEventListener('submit', async (e) => {
    e.preventDefault()
    const value = searchInput.value.trim()

    if (BARCODE_RE.test(value)) {
      const result = await api.produk.byBarcode({
        barcode: value,
        gudangId: getState().session?.gudang_id
      })
      if (disposed) return
      if (result.ok && result.data) {
        addToCart(result.data)
        query = ''
        searchInput.value = ''
        searchInput.focus()
        return
      }
      if (!result.ok && result.status !== 404) {
        toast(firstError(result), 'error')
        return
      }
    }

    query = value
    loadProduk()
  })

  // ---------- Event keranjang ----------

  itemsEl.addEventListener('click', (e) => {
    const row = e.target.closest('.pos-line')
    if (!row) return
    const line = cart.find((l) => String(l.produk.id) === row.dataset.id)
    if (!line) return
    if (e.target.closest('[data-act="del"]')) setQty(line, 0)
    else if (e.target.closest('[data-act="minus"]')) setQty(line, Number(line.kuantitas) - 1)
    else if (e.target.closest('[data-act="plus"]')) setQty(line, Number(line.kuantitas) + 1)
  })

  itemsEl.addEventListener('change', (e) => {
    const row = e.target.closest('.pos-line')
    if (!row) return
    const line = cart.find((l) => String(l.produk.id) === row.dataset.id)
    if (!line) return
    if (e.target.matches('[data-act="qty"]')) setQty(line, Number(e.target.value))
    else if (e.target.matches('[data-act="disc"]')) setDiskon(line, e.target.value)
  })

  custEl.addEventListener('click', (e) => {
    if (e.target.closest('[data-act="cust-clear"]')) {
      pelanggan = null
      renderCart()
    } else if (e.target.closest('[data-act="cust-add"]')) {
      openCustomerModal()
    }
  })

  clearBtn.addEventListener('click', async () => {
    if (!cart.length) return
    const yes = await confirmDialog({
      title: 'Kosongkan keranjang?',
      message: `${cart.length} item akan dihapus dari keranjang.`,
      confirmText: 'Kosongkan',
      danger: true
    })
    if (!yes || disposed) return
    cart = []
    renderCart()
  })

  payBtn.addEventListener('click', openPaymentModal)

  // ---------- Pintasan keyboard ----------

  function isEditableTarget(el) {
    return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' ||
      el.tagName === 'SELECT' || el.isContentEditable)
  }

  function onKeydown(e) {
    if (e.key === 'F4') {
      e.preventDefault()
      if (cart.length) openPaymentModal()
      return
    }
    const modalOpen = !!document.querySelector('.modal-overlay')
    if (e.key === 'F2' && !modalOpen) {
      e.preventDefault()
      searchInput.focus()
      searchInput.select()
      return
    }
    if (e.key === '/' && !modalOpen && !isEditableTarget(e.target)) {
      e.preventDefault()
      searchInput.focus()
      searchInput.select()
    }
  }
  document.addEventListener('keydown', onKeydown)

  // ---------- Mulai ----------

  renderCart()
  loadProduk()
  searchInput.focus()

  return () => {
    disposed = true
    loadSeq += 1
    document.removeEventListener('keydown', onKeydown)
  }
}
