// Pengaturan → Profil Usaha & Struk (O/M). Muat GET /pengaturan/usaha, edit
// partial (PUT hanya field berubah), unggah Logo Usaha & Logo Struk (multipart),
// toggle "tampilkan logo di struk" + footer struk, dan Satuan bawaan produk (master
// /satuan; dipakai server saat item baru tanpa satuan — kosong = item baru wajib memilih).
// Setelah simpan → refresh /config agar header dashboard & kop struk ikut terbarui.

import { api, firstError } from '../api.js'
import { refreshConfig } from '../app.js'
import { toast } from '../components/ui.js'
import { esc } from '../utils/format.js'
import { bisa } from '../akses.js'
import { jadikanBacaSaja } from '../components/baca-saja.js'
import { galatKolom } from '../lib/galat-form.js'
import { cocokkanSatuanBawaan } from '../lib/satuan-bawaan.js'

const ACCEPT = 'image/png,image/jpeg,image/webp'
const MAKS_BYTE = 2 * 1024 * 1024

export async function mountProfilUsaha(host) {
  host.innerHTML = `
    <section class="card">
      <div class="card__header"><h2 class="card__title">Profil Usaha</h2></div>
      <div class="card__body" id="pu-body"><div class="field__hint">Memuat profil usaha…</div></div>
    </section>`
  const body = host.querySelector('#pu-body')
  const res = await api.pengaturan.usahaGet()
  if (!res.ok) {
    body.innerHTML = `<div class="field__hint">${esc(firstError(res) || 'Gagal memuat profil usaha.')}</div>
      <div class="set-actions"><button class="btn btn--outline btn--sm" id="pu-retry">Coba lagi</button></div>`
    body.querySelector('#pu-retry').addEventListener('click', () => mountProfilUsaha(host))
    return
  }
  render(host, res.data || {})
}

function render(host, data) {
  const body = host.querySelector('#pu-body')
  const struk = data.struk || {}
  const tampil = struk.tampil_logo !== false
  body.innerHTML = `
    <div class="pu-logo-row">
      <div class="pu-logo">${data.logo ? `<img src="${esc(data.logo)}" alt="Logo usaha" />` : '<span class="pu-logo__ph">Belum ada logo</span>'}</div>
      <div class="pu-logo-info">
        <button type="button" class="btn btn--outline btn--sm" id="pu-upload-logo">Unggah Logo Usaha</button>
        <div class="field__hint">PNG / JPG / WEBP, maks 2 MB. Tampil di header dashboard & kop struk.</div>
      </div>
    </div>

    <div class="field"><label class="field__label" for="pu-nama">Nama Usaha</label>
      <input class="input" id="pu-nama" maxlength="150" autocomplete="off" value="${esc(data.nama || '')}" /></div>
    <div class="field"><label class="field__label" for="pu-alamat">Alamat</label>
      <textarea class="input" id="pu-alamat" rows="2" maxlength="500">${esc(data.alamat || '')}</textarea></div>
    <div class="pu-2col">
      <div class="field"><label class="field__label" for="pu-telp">No. Telepon</label>
        <input class="input" id="pu-telp" maxlength="30" autocomplete="off" value="${esc(data.telepon || '')}" /></div>
      <div class="field"><label class="field__label" for="pu-email">Email</label>
        <input class="input" id="pu-email" type="email" maxlength="150" autocomplete="off" value="${esc(data.email || '')}" /></div>
    </div>
    <div class="field"><label class="field__label" for="pu-satuan">Satuan bawaan produk</label>
      <select class="select" id="pu-satuan" disabled><option value="">Memuat satuan…</option></select>
      <div class="field__error u-hidden" id="pu-satuan-error" role="alert"></div>
      <div class="field__hint">Dipakai untuk item baru yang tidak memilih satuan. Bila belum diatur, setiap item baru wajib memilih satuan.</div>
    </div>

    <hr class="divider" />
    <h3 class="set-keys__title">Struk</h3>
    <div class="pu-logo-row">
      <div class="pu-logo">${struk.logo ? `<img src="${esc(struk.logo)}" alt="Logo struk" />` : '<span class="pu-logo__ph">Pakai logo usaha</span>'}</div>
      <div class="pu-logo-info">
        <button type="button" class="btn btn--outline btn--sm" id="pu-upload-struk">Unggah Logo Struk</button>
        <div class="field__hint">Disarankan monokrom / kontras tinggi (printer thermal). Kosong → pakai logo usaha.</div>
      </div>
    </div>
    <label class="pu-check"><input type="checkbox" id="pu-tampil" ${tampil ? 'checked' : ''} /> <span>Tampilkan logo di struk</span></label>
    <div class="field"><label class="field__label" for="pu-footer">Catatan / Footer struk</label>
      <textarea class="input" id="pu-footer" rows="2" maxlength="300" placeholder="Terima kasih telah berbelanja.">${esc(struk.footer || '')}</textarea></div>

    <div class="set-actions"><button type="button" class="btn btn--primary" id="pu-save">Simpan Profil</button></div>`

  const awal = {
    nama: data.nama || '', alamat: data.alamat || '', telepon: data.telepon || '',
    email: data.email || '', struk_footer: struk.footer || '', struk_tampil_logo: tampil,
    satuan_bawaan_id: '' // diisi setelah daftar /satuan termuat (id terenkripsi berubah tiap jawaban)
  }
  const satuanEl = body.querySelector('#pu-satuan')
  api.master.satuan().then((rs) => {
    if (!satuanEl.isConnected) return
    const daftar = rs.ok && Array.isArray(rs.data) ? rs.data : []
    const terpilih = cocokkanSatuanBawaan(daftar, data.satuan_bawaan)
    satuanEl.innerHTML = '<option value="">— Belum diatur —</option>' + daftar.map((x) =>
      `<option value="${esc(x.id)}" ${terpilih && terpilih.id === x.id ? 'selected' : ''}>${esc(x.nama)}${x.kode && x.kode !== x.nama ? ` (${esc(x.kode)})` : ''}</option>`).join('')
    awal.satuan_bawaan_id = terpilih ? terpilih.id : ''
    satuanEl.disabled = daftar.length === 0 || !bisa('pengaturan.usaha')
    if (!rs.ok) satuanEl.innerHTML = `<option value="">${esc(firstError(rs) || 'Gagal memuat satuan')}</option>`
  })
  satuanEl.addEventListener('change', () => { const e = body.querySelector('#pu-satuan-error'); e.textContent = ''; e.classList.add('u-hidden') })
  body.querySelector('#pu-upload-logo').addEventListener('click', () => unggah(api.pengaturan.uploadLogo, host))
  body.querySelector('#pu-upload-struk').addEventListener('click', () => unggah(api.pengaturan.uploadLogoStruk, host))
  body.querySelector('#pu-save').addEventListener('click', () => simpan(host, awal, body))
  if (!bisa('pengaturan.usaha')) jadikanBacaSaja(body)
}

/** Pilih file lalu unggah (field `logo`). Batas 2 MB, tipe png/jpg/webp. */
function unggah(uploadFn, host) {
  const input = document.createElement('input')
  input.type = 'file'
  input.accept = ACCEPT
  input.addEventListener('change', async () => {
    const file = input.files && input.files[0]
    if (!file) return
    if (file.size > MAKS_BYTE) { toast('Ukuran file maksimal 2 MB.', 'error'); return }
    let bytes
    try { bytes = await file.arrayBuffer() } catch { toast('Gagal membaca file.', 'error'); return }
    toast('Mengunggah logo…', 'info')
    const r = await uploadFn({ bytes, filename: file.name, mime: file.type })
    if (!r.ok) { toast(firstError(r) || 'Gagal mengunggah logo.', 'error'); return }
    toast('Logo tersimpan.', 'success')
    await refreshConfig()
    render(host, r.data || {})
  })
  input.click()
}

/** Simpan hanya field yang berubah (partial update). */
async function simpan(host, awal, body) {
  const val = (id) => (body.querySelector(id).value || '').trim()
  const kini = {
    nama: val('#pu-nama'), alamat: val('#pu-alamat'), telepon: val('#pu-telp'),
    email: val('#pu-email'), struk_footer: val('#pu-footer'),
    struk_tampil_logo: body.querySelector('#pu-tampil').checked
  }
  const satuanEl = body.querySelector('#pu-satuan')
  if (satuanEl && !satuanEl.disabled) kini.satuan_bawaan_id = satuanEl.value || ''
  else kini.satuan_bawaan_id = awal.satuan_bawaan_id
  if (!kini.nama) { toast('Nama usaha wajib diisi.', 'error'); return }
  const ubah = {}
  for (const k of Object.keys(kini)) if (kini[k] !== awal[k]) ubah[k] = kini[k]
  if (Object.keys(ubah).length === 0) { toast('Tidak ada perubahan untuk disimpan.', 'info'); return }

  const btn = body.querySelector('#pu-save')
  btn.disabled = true
  const r = await api.pengaturan.usahaSimpan(ubah)
  btn.disabled = false
  if (!r.ok) {
    const galatSatuan = galatKolom(r, 'satuan_bawaan_id')
    if (galatSatuan) {
      const e = body.querySelector('#pu-satuan-error')
      e.textContent = galatSatuan
      e.classList.remove('u-hidden')
    }
    toast(firstError(r) || 'Gagal menyimpan profil.', 'error')
    return
  }
  toast('Profil usaha disimpan.', 'success')
  await refreshConfig()
  render(host, r.data || {})
}
