// Layar Inventory (§4.2) — 3 card (Tambah Stok, Kurangi/Opname, Pelanggan Cepat)
// + Riwayat Perubahan Stok realtime (poll ~10 dtk). Server-backed (O/M); Mode
// Demo mensimulasikan penuh. Uang integer; stok bisa desimal; jumlah bertanda.

import { api, firstError } from '../api.js'
import { toast, icons, emptyStateHTML } from '../components/ui.js'
import { esc, fmtNumber, fmtDateTime } from '../utils/format.js'

const POLL_MS = 10000

export const InventoryScreen = {
  id: 'inventory',
  title: 'Inventory',
  icon: icons.box,

  async render(container) {
    const ctx = { container, produk: [], pickers: [], timer: null, alive: true }
    renderLayout(container)
    await loadProduk(ctx)
    bind(ctx)
    await refreshRiwayat(ctx)
    ctx.timer = setInterval(() => { if (ctx.alive && document.body.contains(container)) refreshRiwayat(ctx) }, POLL_MS)
    return () => { ctx.alive = false; if (ctx.timer) clearInterval(ctx.timer) }
  }
}

function renderLayout(container) {
  container.innerHTML = `
    <div class="screen-page">
      <div class="page-head">
        <div>
          <h1 class="page-head__title">Inventory</h1>
          <p class="page-head__desc">Tambah &amp; kurangi stok, dan pantau riwayat perubahan stok toko.</p>
        </div>
        <button type="button" class="btn btn--outline" id="inv-reload">${icons.refresh}<span>Muat ulang</span></button>
      </div>

      <div class="inv-cards">
        <div class="card inv-card">
          <div class="inv-card__head"><span class="inv-card__icon inv-card__icon--in">${icons.plus}</span><h2 class="inv-card__title">Tambah Stok (Masuk)</h2></div>
          <div class="field"><label class="field__label">Produk</label><div id="inv-in-picker"></div></div>
          <div class="field"><label class="field__label" for="inv-in-jml">Jumlah tambah</label><input type="text" inputmode="decimal" class="input" id="inv-in-jml" placeholder="mis. 12" autocomplete="off" /></div>
          <button type="button" class="btn btn--primary inv-card__submit" id="inv-in-go">${icons.plus}<span>Tambah Stok</span></button>
        </div>

        <div class="card inv-card">
          <div class="inv-card__head"><span class="inv-card__icon inv-card__icon--out">${icons.minus}</span><h2 class="inv-card__title">Kurangi Stok (Opname)</h2></div>
          <div class="field"><label class="field__label">Produk</label><div id="inv-out-picker"></div></div>
          <div class="field"><label class="field__label" for="inv-out-jml">Jumlah rusak / hilang</label><input type="text" inputmode="decimal" class="input" id="inv-out-jml" placeholder="mis. 2" autocomplete="off" /></div>
          <button type="button" class="btn btn--danger inv-card__submit" id="inv-out-go">${icons.minus}<span>Kurangi Stok</span></button>
        </div>

        <div class="card inv-card">
          <div class="inv-card__head"><span class="inv-card__icon inv-card__icon--cust">${icons.user}</span><h2 class="inv-card__title">Pelanggan Cepat</h2></div>
          <div class="field"><label class="field__label" for="inv-c-nama">Nama pelanggan</label><input type="text" class="input" id="inv-c-nama" placeholder="mis. Ibu Sari" maxlength="120" autocomplete="off" /></div>
          <div class="field"><label class="field__label" for="inv-c-wa">No WhatsApp</label><input type="tel" inputmode="tel" class="input" id="inv-c-wa" placeholder="mis. 0812xxxxxxx" maxlength="20" autocomplete="off" /></div>
          <button type="button" class="btn btn--primary inv-card__submit" id="inv-c-go">${icons.user}<span>Simpan Pelanggan</span></button>
          <div id="inv-c-result"></div>
        </div>
      </div>

      <div class="inv-riwayat-head">
        <h2 class="page-section__title">Riwayat Perubahan Stok</h2>
        <span class="inv-riwayat-live"><span class="badge__dot"></span>realtime</span>
      </div>
      <div id="inv-riwayat"></div>
    </div>`
}

async function loadProduk(ctx) {
  const r = await api.produk.list({ tipe: 'PRODUK', includeHabis: true, perPage: 100 })
  ctx.produk = (r.ok && Array.isArray(r.data) ? r.data : [])
    .filter((p) => p.kelola_stok) // hanya item ber-stok yang bisa ditambah/opname
    .map((p) => ({ id: p.id, kode: p.kode || '', nama: p.nama, stok: Number(p.stok) || 0 }))
  ctx.pickers.forEach((pk) => pk.setItems(ctx.produk))
}

function itemLabel(it) { return `${it.kode ? it.kode + ' · ' : ''}${it.nama}` }

/** Combobox produk searchable (server-backed list, filter lokal). */
function buatPicker(mount, placeholder) {
  mount.classList.add('inv-picker')
  mount.innerHTML = `
    <input type="text" class="input inv-picker__input" placeholder="${esc(placeholder)}" autocomplete="off" role="combobox" aria-expanded="false" />
    <div class="inv-picker__drop u-hidden"></div>`
  const input = mount.querySelector('.inv-picker__input')
  const drop = mount.querySelector('.inv-picker__drop')
  let items = []
  let selected = null

  function render(filter) {
    const f = String(filter || '').toLowerCase()
    const matches = items.filter((it) => !f || itemLabel(it).toLowerCase().includes(f)).slice(0, 40)
    drop.innerHTML = matches.length
      ? matches.map((it) => `<button type="button" class="inv-picker__opt" data-id="${esc(it.id)}"><span class="u-truncate">${esc(itemLabel(it))}</span><span class="inv-picker__stok">stok ${fmtNumber(it.stok)}</span></button>`).join('')
      : '<div class="inv-picker__empty">Tak ada produk cocok.</div>'
    drop.querySelectorAll('.inv-picker__opt').forEach((b) => b.addEventListener('mousedown', (e) => {
      e.preventDefault()
      selected = items.find((x) => x.id === b.dataset.id) || null
      if (selected) input.value = itemLabel(selected)
      close()
    }))
  }
  function open() { render(input.value === (selected ? itemLabel(selected) : '') ? '' : input.value); drop.classList.remove('u-hidden'); input.setAttribute('aria-expanded', 'true') }
  function close() { drop.classList.add('u-hidden'); input.setAttribute('aria-expanded', 'false') }

  input.addEventListener('focus', open)
  input.addEventListener('input', () => { selected = null; render(input.value); drop.classList.remove('u-hidden') })
  input.addEventListener('blur', () => setTimeout(close, 160))

  return {
    setItems(list) { items = list; if (selected) { const cur = items.find((x) => x.id === selected.id); selected = cur || null; input.value = cur ? itemLabel(cur) : '' } },
    get() { return selected },
    reset() { selected = null; input.value = '' }
  }
}

function bind(ctx) {
  const c = ctx.container
  const inPicker = buatPicker(c.querySelector('#inv-in-picker'), 'Cari produk…')
  const outPicker = buatPicker(c.querySelector('#inv-out-picker'), 'Cari produk…')
  ctx.pickers = [inPicker, outPicker]
  inPicker.setItems(ctx.produk)
  outPicker.setItems(ctx.produk)

  c.querySelector('#inv-reload').addEventListener('click', async () => { await loadProduk(ctx); await refreshRiwayat(ctx); toast('Data stok dimuat ulang.', 'info') })
  c.querySelector('#inv-in-go').addEventListener('click', () => mutasi(ctx, 'masuk', inPicker))
  c.querySelector('#inv-out-go').addEventListener('click', () => mutasi(ctx, 'opname', outPicker))
  c.querySelector('#inv-c-go').addEventListener('click', () => quickCustomer(ctx))
}

function parseQty(raw) {
  const n = Number(String(raw || '').replace(',', '.').trim())
  return Number.isFinite(n) ? n : NaN
}

async function mutasi(ctx, mode, picker) {
  const c = ctx.container
  const it = picker.get()
  const jmlEl = c.querySelector(mode === 'masuk' ? '#inv-in-jml' : '#inv-out-jml')
  const btn = c.querySelector(mode === 'masuk' ? '#inv-in-go' : '#inv-out-go')
  const jumlah = parseQty(jmlEl.value)
  if (!it) { toast('Pilih produk terlebih dahulu.', 'error'); return }
  if (!(jumlah > 0)) { toast('Isi jumlah yang valid (lebih dari 0).', 'error'); return }

  btn.disabled = true
  const call = mode === 'masuk'
    ? api.inventory.stokMasuk({ idProduk: it.id, jumlah })
    : api.inventory.opname({ idProduk: it.id, jumlah })
  const r = await call
  btn.disabled = false

  if (!r.ok) { toast(firstError(r), 'error'); return } // 422 "Stok tidak mencukupi…" apa adanya
  const baru = r.data && r.data.stok_sekarang != null ? Number(r.data.stok_sekarang) : it.stok
  // Perbarui stok di daftar produk (cermin di kedua picker)
  const ref = ctx.produk.find((x) => x.id === it.id)
  if (ref) ref.stok = baru
  ctx.pickers.forEach((pk) => pk.setItems(ctx.produk))
  jmlEl.value = ''
  toast(mode === 'masuk'
    ? `Stok "${it.nama}" bertambah — kini ${fmtNumber(baru)}.`
    : `Stok "${it.nama}" dikurangi — kini ${fmtNumber(baru)}.`, 'success')
  await refreshRiwayat(ctx)
}

async function quickCustomer(ctx) {
  const c = ctx.container
  const nama = c.querySelector('#inv-c-nama').value.trim()
  const noWhatsapp = c.querySelector('#inv-c-wa').value.trim()
  const btn = c.querySelector('#inv-c-go')
  const result = c.querySelector('#inv-c-result')
  if (!nama) { toast('Isi nama pelanggan.', 'error'); return }

  btn.disabled = true
  const r = await api.pelanggan.quick({ nama, noWhatsapp })
  btn.disabled = false
  if (!r.ok) { toast(firstError(r), 'error'); return }

  const d = r.data || {}
  c.querySelector('#inv-c-nama').value = ''
  c.querySelector('#inv-c-wa').value = ''
  toast(`Pelanggan "${esc(d.nama || nama)}" tersimpan.`, 'success')
  result.innerHTML = `
    <div class="inv-cust-result">
      <div><strong>${esc(d.nama || nama)}</strong>${d.telepon ? ` · ${esc(d.telepon)}` : ''}</div>
      ${d.wa_link ? `<a class="btn btn--outline btn--sm" href="${esc(d.wa_link)}" target="_blank" rel="noopener">Chat WhatsApp</a>` : ''}
    </div>`
}

const BADGE_TIPE = { PENJUALAN: 'badge--info', MASUK: 'badge--success', OPNAME: 'badge--warn' }

async function refreshRiwayat(ctx) {
  const body = ctx.container.querySelector('#inv-riwayat')
  if (!body) return
  const r = await api.inventory.riwayat({ perPage: 25 })
  if (!r.ok) {
    body.innerHTML = emptyStateHTML({ icon: icons.box, title: 'Riwayat belum tersedia', desc: firstError(r) })
    return
  }
  const rows = Array.isArray(r.data) ? r.data : []
  if (rows.length === 0) {
    body.innerHTML = emptyStateHTML({ icon: icons.box, title: 'Belum ada perubahan stok', desc: 'Tambah atau kurangi stok di atas — atau lakukan penjualan — untuk mengisi riwayat.' })
    return
  }
  const trs = rows.map((row) => {
    const jml = Number(row.jumlah) || 0
    const kelas = jml > 0 ? 'inv-jml--in' : (jml < 0 ? 'inv-jml--out' : '')
    const tanda = jml > 0 ? '+' : ''
    return `
      <tr>
        <td>${esc(row.item || '—')}</td>
        <td>${esc(fmtDateTime(row.tanggal))}</td>
        <td class="mono">${esc(row.sesi_kasir || '—')}</td>
        <td class="num u-right ${kelas}">${tanda}${fmtNumber(jml)}</td>
        <td><span class="badge ${BADGE_TIPE[row.tipe] || 'badge--neutral'}">${esc(row.tipe || '—')}</span></td>
      </tr>`
  }).join('')
  body.innerHTML = `
    <div class="table-wrap">
      <table class="table">
        <thead><tr><th>Nama Item</th><th>Tanggal</th><th>Sesi Kasir</th><th class="u-right">Jumlah</th><th>Tipe</th></tr></thead>
        <tbody>${trs}</tbody>
      </table>
    </div>`
}
