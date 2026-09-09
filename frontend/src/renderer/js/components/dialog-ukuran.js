// Dialog barang terukur (per kilo / liter / meter). Dipakai layar Kasir dan
// bon meja: keduanya perlu bertanya "berapa ukurannya?" alih-alih menambah 1.
//
// Dua cara isi yang sama-sama wajar di warung: pelanggan menyebut UKURAN
// ("dua kilo") atau menyebut UANG ("dua puluh ribu"). Nominal diterjemahkan ke
// ukuran lebih dulu — lihat PENJUALAN-TERUKUR.md — sehingga yang ditagih selalu
// `ukuran × harga` dan cocok dengan hitungan server.
//
// Murni tampilan: dialog tidak menyentuh keranjang. Pemanggil yang memutuskan
// apa yang dilakukan dengan hasilnya (mengganti baris, menambah ronde, dll).

import { esc, fmtIDR, fmtNumber, parseAmount } from '../utils/format.js'
import { showModal } from './ui.js'
import {
  bulatkanKuantitas, kuantitasDariNominal, langkahSatuan, minimalNominal, totalBaris
} from '../lib/satuan-terukur.js'

const PINTASAN_UKURAN = [0.25, 0.5, 1, 2, 5]
const PINTASAN_NOMINAL = [5000, 10000, 20000, 50000]

// Terima desimal gaya Indonesia (koma) maupun titik: '4,5' → 4.5
function parseDesimal(v) {
  return Number(String(v).trim().replace(',', '.'))
}

/**
 * Tanya ukuran satu produk.
 *
 * @returns {Promise<{ qty: number, nominalDiminta: number|null }|null>}
 *   null bila kasir menutup dialog.
 */
export function tanyaUkuran(produk, {
  harga = 0,
  qtyAwal = null,
  stok = Infinity,
  kelolaStok = false,
  labelTambah = 'Tambah ke Keranjang'
} = {}) {
  const satuan = String(produk.satuan || '').toLowerCase()
  const hargaSah = harga > 0
  // Baris terukur selalu MENGGANTI isi baris, jadi batas atasnya stok penuh
  // (bukan stok dikurangi isi keranjang).
  const adaBatas = kelolaStok && Number.isFinite(stok)

  const body = document.createElement('div')
  body.innerHTML = `
    <div class="tabs tabs--sm" role="tablist">
      <button class="tabs__item is-active" type="button" data-mode="ukuran">Per ${esc(satuan)}</button>
      <button class="tabs__item" type="button" data-mode="nominal" ${hargaSah ? '' : 'disabled'}>Nominal</button>
    </div>
    <div class="field" id="ukur-field-ukuran">
      <label class="field__label" for="ukur-in">Berat / ukuran hasil timbangan</label>
      <input class="input input--lg num" id="ukur-in" type="text" inputmode="decimal"
             placeholder="mis. 0,74" autocomplete="off" value="${qtyAwal ? esc(String(qtyAwal).replace('.', ',')) : ''}" />
      <div class="u-flex" id="ukur-cepat" style="flex-wrap:wrap">
        ${PINTASAN_UKURAN.map((n) => `
          <button type="button" class="btn btn--outline btn--sm" data-q="${n}">${String(n).replace('.', ',')} ${esc(satuan)}</button>`).join('')}
      </div>
    </div>
    <div class="field u-hidden" id="ukur-field-nominal">
      <label class="field__label" for="ukur-rp">Pelanggan minta berapa rupiah?</label>
      <input class="input input--lg num" id="ukur-rp" type="text" inputmode="numeric"
             placeholder="mis. 20.000" autocomplete="off" />
      <div class="u-flex" id="ukur-cepat-rp" style="flex-wrap:wrap">
        ${PINTASAN_NOMINAL.map((n) => `
          <button type="button" class="btn btn--outline btn--sm" data-rp="${n}">${fmtIDR(n)}</button>`).join('')}
      </div>
    </div>
    <div class="ukur-ringkas num" id="ukur-view">${fmtIDR(harga)} / ${esc(satuan)}</div>
    ${adaBatas ? `<div class="ukur-sisa num">Sisa stok ${fmtNumber(stok)} ${esc(satuan)}</div>` : ''}`

  const footer = document.createElement('div')
  footer.innerHTML = `<button type="button" class="btn btn--primary" id="ukur-ok">${esc(qtyAwal ? 'Simpan perubahan' : labelTambah)}</button>`

  return new Promise((resolve) => {
    let hasil = null
    const { close } = showModal({
      title: produk.nama,
      body,
      footer,
      onClose: () => resolve(hasil)
    })
    const inUkuran = body.querySelector('#ukur-in')
    const inNominal = body.querySelector('#ukur-rp')
    const view = body.querySelector('#ukur-view')
    const tombolOk = footer.querySelector('#ukur-ok')
    let mode = 'ukuran'

    // Ukuran yang sedang diisi (sudah dibulatkan ke langkah satuannya).
    function qtySekarang() {
      if (mode === 'ukuran') return bulatkanKuantitas(parseDesimal(inUkuran.value) || 0, satuan)
      return kuantitasDariNominal(parseAmount(inNominal.value), harga, satuan)
    }

    function render() {
      const qty = qtySekarang()
      const nominal = mode === 'nominal' ? parseAmount(inNominal.value) : 0
      const lebihStok = adaBatas && qty > stok
      // Dulu submit diam-diam memotong ke sisa stok: kasir menimbang 5 kg, yang
      // masuk keranjang 0,8 kg tanpa pemberitahuan. Sekarang ditahan di sini.
      tombolOk.disabled = !(qty > 0) || lebihStok
      if (lebihStok) {
        view.innerHTML = `<span class="ukur-ringkas__galat">Sisa stok hanya ${fmtNumber(stok)} ${esc(satuan)}.</span>`
        return
      }
      if (mode === 'nominal' && nominal > 0 && qty <= 0) {
        view.innerHTML = `<span class="ukur-ringkas__galat">Minimal ${fmtIDR(minimalNominal(harga, satuan))} (${String(langkahSatuan(satuan)).replace('.', ',')} ${esc(satuan)}).</span>`
        return
      }
      if (!(qty > 0)) { view.textContent = `${fmtIDR(harga)} / ${satuan}`; return }
      const diminta = mode === 'nominal' && nominal > 0 ? `Diminta ${fmtIDR(nominal)} → ` : ''
      view.textContent = `${diminta}${fmtNumber(qty)} ${satuan} × ${fmtIDR(harga)} = ${fmtIDR(totalBaris(qty, harga))}`
    }

    body.querySelector('.tabs').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-mode]')
      if (!btn || btn.disabled) return
      mode = btn.dataset.mode
      body.querySelectorAll('.tabs__item').forEach((b) => b.classList.toggle('is-active', b === btn))
      body.querySelector('#ukur-field-ukuran').classList.toggle('u-hidden', mode !== 'ukuran')
      body.querySelector('#ukur-field-nominal').classList.toggle('u-hidden', mode !== 'nominal')
      ;(mode === 'ukuran' ? inUkuran : inNominal).focus()
      render()
    })

    inUkuran.addEventListener('input', render)
    inNominal.addEventListener('input', render)
    body.querySelector('#ukur-cepat').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-q]')
      if (!btn) return
      inUkuran.value = String(btn.dataset.q).replace('.', ',')
      render()
      inUkuran.focus()
    })
    body.querySelector('#ukur-cepat-rp').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-rp]')
      if (!btn) return
      inNominal.value = fmtNumber(Number(btn.dataset.rp))
      render()
      inNominal.focus()
    })

    const submit = () => {
      const qty = qtySekarang()
      if (!(qty > 0) || (adaBatas && qty > stok)) return
      hasil = {
        qty,
        nominalDiminta: mode === 'nominal' ? parseAmount(inNominal.value) || null : null
      }
      close() // onClose meneruskan `hasil` ke pemanggil
    }
    tombolOk.addEventListener('click', submit)
    for (const el of [inUkuran, inNominal]) {
      el.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit() })
    }
    render()
    inUkuran.focus()
  })
}
