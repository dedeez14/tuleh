// Pengaturan → Printer struk: pilih printer, cetak langsung tanpa dialog,
// cetak otomatis setelah bayar, dan uji cetak. Preferensi disimpan di
// settings.json (main), dibaca receipt.js saat mencetak.

import { api } from '../api.js'
import { esc } from '../utils/format.js'
import { toast } from '../components/ui.js'
import { printReceipt, preferensiCetak } from '../components/receipt.js'

const STRUK_UJI = {
  nomor: 'UJI-CETAK',
  tanggal: new Date().toISOString(),
  kasir: 'Uji cetak',
  tipe_pembayaran: 'TUNAI',
  items: [
    { nama: 'Contoh item A', kuantitas: 2, harga: 10000, subtotal: 20000, satuan: 'pcs' },
    { nama: 'Contoh item B', kuantitas: 1, harga: 15000, subtotal: 15000, satuan: 'pcs' }
  ],
  subtotal: 35000, total_diskon: 0, total_pajak: 0, grand_total: 35000, dibayar: 50000, kembalian: 15000
}

export async function mountPrinterSetelan(container) {
  if (!container) return
  container.innerHTML = `
    <section class="card">
      <div class="card__header"><h2 class="card__title">Printer struk</h2></div>
      <div class="card__body">
        <div class="field">
          <label class="field__label" for="pr-printer">Printer</label>
          <select class="input" id="pr-printer"><option value="">Memuat daftar printer…</option></select>
          <div class="field__hint">Pilih printer thermal/kasir. Kosongkan untuk selalu memakai dialog cetak Windows.</div>
        </div>
        <label class="pu-check"><input type="checkbox" id="pr-langsung" /> <span>Cetak langsung tanpa dialog ke printer di atas</span></label>
        <label class="pu-check"><input type="checkbox" id="pr-otomatis" /> <span>Cetak struk otomatis setelah pembayaran berhasil</span></label>
        <div class="set-actions">
          <button class="btn btn--outline btn--sm" id="pr-uji">Uji cetak</button>
          <button class="btn btn--ghost btn--sm" id="pr-uji-dialog">Uji lewat dialog</button>
          <button class="btn btn--primary btn--sm" id="pr-simpan">Simpan</button>
        </div>
      </div>
    </section>`

  const sel = container.querySelector('#pr-printer')
  const langsung = container.querySelector('#pr-langsung')
  const otomatis = container.querySelector('#pr-otomatis')

  const [pref, printers] = await Promise.all([preferensiCetak(true), api.app.printers()])
  const daftar = printers.ok && Array.isArray(printers.data) ? printers.data : []
  sel.innerHTML = `<option value="">— Dialog cetak Windows —</option>` + daftar.map((p) =>
    `<option value="${esc(p.nama)}">${esc(p.nama)}${p.bawaan ? ' (bawaan)' : ''}</option>`).join('')
  if (pref.printer && !daftar.some((p) => p.nama === pref.printer)) {
    sel.insertAdjacentHTML('beforeend', `<option value="${esc(pref.printer)}">${esc(pref.printer)} (tidak ditemukan)</option>`)
  }
  sel.value = pref.printer || ''
  langsung.checked = !!pref.langsung
  otomatis.checked = !!pref.otomatis

  container.querySelector('#pr-simpan').addEventListener('click', async () => {
    const r = await api.settings.setCetak({ printer: sel.value, langsung: langsung.checked, otomatis: otomatis.checked })
    if (!r.ok) { toast(r.message || 'Gagal menyimpan.', 'error'); return }
    await preferensiCetak(true)
    toast('Pengaturan printer disimpan.', 'success')
  })
  // Uji cetak memakai setelan yang sedang tampil TANPA menyimpannya — dulu
  // mencentang "cetak otomatis" lalu menekan Uji cetak sudah menyalakannya
  // meski pengguna tidak pernah menekan Simpan.
  container.querySelector('#pr-uji').addEventListener('click', async () => {
    const ok = await printReceipt(STRUK_UJI, {
      coba: { printer: sel.value, langsung: langsung.checked },
    })
    if (ok) toast('Struk uji dikirim ke printer. Tekan Simpan bila setelan ini mau dipakai.', 'success', 5000)
  })
  container.querySelector('#pr-uji-dialog').addEventListener('click', () => printReceipt(STRUK_UJI, { paksaDialog: true }))
}
