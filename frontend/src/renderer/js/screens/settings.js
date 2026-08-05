// Layar Pengaturan — koneksi server, info akun, dan info aplikasi.

import { api, firstError } from '../api.js'
import { getState } from '../state.js'
import { icons, toast, confirmDialog } from '../components/ui.js'
import { esc, fmtDateTime, fmtDate } from '../utils/format.js'
import { mulaiPembayaran } from '../langganan-bayar.js'
import { mountProfilUsaha } from './profil-usaha.js'

const DASH = '<span class="u-faint">—</span>'

function defRow(label, valueHTML) {
  return `
    <div class="set-def__row">
      <span class="set-def__label">${label}</span>
      <span class="set-def__value">${valueHTML}</span>
    </div>`
}

function accountCardHTML() {
  const { user, company, branch } = getState()
  const roleBadge = user?.is_admin
    ? '<span class="badge badge--mint">Admin</span>'
    : '<span class="badge badge--info">Kasir</span>'
  return `
    <section class="card">
      <div class="card__header"><h2 class="card__title">Akun</h2></div>
      <div class="card__body">
        <div class="set-def">
          ${defRow('Nama', user?.name ? esc(user.name) : DASH)}
          ${defRow('Email', user?.email ? `<span class="mono">${esc(user.email)}</span>` : DASH)}
          ${defRow('Peran', roleBadge)}
          ${company?.nama ? defRow('Perusahaan', esc(company.nama)) : ''}
          ${branch?.nama ? defRow('Cabang', esc(branch.nama)) : ''}
        </div>
      </div>
    </section>`
}

function keysHTML() {
  const key = (k) => `<span class="kbd">${k}</span>`
  const row = (combo, desc) => `
    <div class="set-keys__row">
      <span class="set-keys__combo">${combo}</span>
      <span class="u-muted">${desc}</span>
    </div>`
  return `
    <div class="set-keys">
      ${row(`${key('Ctrl')} + ${key('1')} … ${key('5')}`, 'Pindah antar layar')}
      ${row(key('F2'), 'Fokus ke pencarian produk (layar Kasir)')}
      ${row(key('F4'), 'Buka panel pembayaran (layar Kasir)')}
      ${row(key('Esc'), 'Tutup dialog / modal')}
    </div>`
}

/** Cari & format waktu server dari respons ping (nama field bisa berbeda-beda). */
function pickServerTime(data) {
  if (!data || typeof data !== 'object') return ''
  const raw = data.server_time || data.waktu_server || data.time || data.timestamp || data.now || ''
  if (!raw) return ''
  const formatted = fmtDateTime(raw)
  return formatted === '—' ? String(raw) : formatted
}

// Hak Akses (§4.4) — peran pemohon (dari pos_role); kelola user tetap di ERP.
function hakAksesCardHTML() {
  const { user, posRole } = getState()
  const label = { OWNER: 'Owner', MANAGER: 'Manager', KASIR: 'Kasir' }[posRole] || (posRole || '—')
  const warna = posRole === 'OWNER' ? 'mint' : (posRole === 'MANAGER' ? 'info' : 'neutral')
  return `
    <section class="card">
      <div class="card__header"><h2 class="card__title">Hak Akses</h2></div>
      <div class="card__body">
        <div class="set-def">
          ${defRow('Pengguna', `<span>${esc(user?.name || '—')}</span>`)}
          ${defRow('Peran (pos_role)', `<span class="badge badge--${warna}">${esc(label)}</span>`)}
        </div>
        <div class="field__hint">Peran menentukan menu yang tampil. Tambah/ubah pengguna &amp; peran dilakukan di tatreport.com (ERP).</div>
      </div>
    </section>`
}

// Kartu Langganan — status + tombol Perpanjang Sekarang (alur Midtrans Snap).
function langgananCardHTML() {
  const l = getState().langganan
  if (!l) return ''
  const status = String(l.status || '').toUpperCase()
  const warna = status === 'AKTIF' ? 'success' : (status === 'GRACE' ? 'warn' : 'danger')
  const labelStatus = { AKTIF: 'Aktif', GRACE: 'Masa tenggang', KEDALUWARSA: 'Kedaluwarsa' }[status] || (status || '—')
  return `
    <section class="card">
      <div class="card__header"><h2 class="card__title">Langganan</h2></div>
      <div class="card__body">
        <div class="set-def">
          ${defRow('Paket', `<span>${esc(l.plan_nama || '—')}</span>`)}
          ${defRow('Status', `<span class="badge badge--${warna}">${esc(labelStatus)}</span>`)}
          ${l.periode_akhir ? defRow('Berlaku sampai', `<span>${esc(fmtDate(l.periode_akhir))}</span>`) : ''}
          ${l.sisa_hari != null ? defRow('Sisa hari', `<span class="num">${esc(String(l.sisa_hari))}</span>`) : ''}
        </div>
        <div class="set-actions">
          <button class="btn btn--primary" id="set-perpanjang" type="button">Perpanjang Sekarang</button>
        </div>
      </div>
    </section>`
}

// Kartu fitur premium (§4.4) — dari manifest.premium_features. enabled:false →
// "Segera Hadir" + Hubungi CS. Menyala kelak hanya lewat perubahan flag server.
function premiumCardHTML() {
  const feats = getState().manifest?.premiumFeatures || []
  if (!feats.length) return ''
  return `
    <section class="card set-premium">
      <div class="card__header"><h2 class="card__title">Fitur Premium</h2></div>
      <div class="card__body">
        <div class="set-premium__grid">
          ${feats.map((f) => `
            <div class="set-premium__item${f.enabled ? ' is-on' : ''}">
              <div class="set-premium__head">
                <span class="set-premium__name">${esc(f.label || '')}</span>
                ${f.enabled ? '<span class="badge badge--success">Aktif</span>' : '<span class="badge badge--warn">Segera Hadir</span>'}
              </div>
              <p class="set-premium__desc">${esc(f.deskripsi || '')}</p>
              ${f.enabled ? '' : '<button type="button" class="btn btn--outline btn--sm" data-cs-contact>Hubungi CS</button>'}
            </div>`).join('')}
        </div>
      </div>
    </section>`
}

export const SettingsScreen = {
  id: 'settings',
  title: 'Pengaturan',
  icon: icons.settings,
  async render(container) {
    container.innerHTML = `
      <div class="screen-page">
        <div class="page-head">
          <div>
            <h1 class="page-head__title">Pengaturan</h1>
            <p class="page-head__desc">Koneksi server, info akun, dan aplikasi.</p>
          </div>
        </div>
        <div class="set-grid">
          <section class="card">
            <div class="card__header"><h2 class="card__title">Server</h2></div>
            <div class="card__body">
              <div class="set-server">
                <span class="set-server__label">URL aktif</span>
                <span class="mono set-server__url" id="set-url-active">…</span>
              </div>
              <div class="field">
                <label class="field__label" for="set-url">Ubah URL server</label>
                <input class="input mono" id="set-url" type="url"
                       placeholder="https://tokosaya.tatreport.com" autocomplete="off" />
                <div class="field__error u-hidden" id="set-url-error"></div>
                <div class="field__hint">
                  Setelah mengganti server, sebaiknya keluar lalu masuk kembali agar token sesuai server baru.
                </div>
              </div>
              <div class="set-actions">
                <button class="btn btn--outline" id="set-ping">Uji Koneksi</button>
                <button class="btn btn--primary" id="set-save">Simpan</button>
              </div>
            </div>
          </section>

          <div id="set-profil-usaha"></div>

          ${accountCardHTML()}

          ${hakAksesCardHTML()}

          ${langgananCardHTML()}

          ${premiumCardHTML()}

          <section class="card">
            <div class="card__header"><h2 class="card__title">Aplikasi</h2></div>
            <div class="card__body">
              <div class="set-def">
                ${defRow('Versi', '<span class="num" id="set-app-version">…</span>')}
                ${defRow('Hostname', '<span class="mono" id="set-app-host">…</span>')}
                ${defRow('Platform', '<span id="set-app-platform">…</span>')}
                ${defRow('Gateway lokal', '<span id="set-app-gateway">…</span>')}
                ${defRow('Lacak pesanan (LAN)', '<span id="set-app-track">…</span>')}
                ${defRow('Akses internet publik', '<span id="set-app-tunnel">…</span>')}
              </div>
              <div class="field__hint u-hidden" id="set-app-error"></div>
              <div class="set-actions">
                <button class="btn btn--outline btn--sm" id="set-tunnel-btn">Aktifkan Akses Internet</button>
              </div>
              <div class="field__hint">
                Membuka URL HTTPS publik (Cloudflare Tunnel) agar pelanggan bisa memesan &
                melacak dari jaringan mana pun — tanpa harus satu WiFi. URL berubah tiap
                kali diaktifkan; QR pada struk & layar selalu memakai URL terbaru.
                Jangan menyala-matikan berulang cepat — layanan gratis ini membatasi
                pembuatan tunnel per beberapa menit.
              </div>
              <hr class="divider" />
              <h3 class="set-keys__title">Pintasan keyboard</h3>
              ${keysHTML()}
            </div>
          </section>
        </div>
      </div>`

    const urlActive = container.querySelector('#set-url-active')
    const urlInput = container.querySelector('#set-url')
    const urlError = container.querySelector('#set-url-error')
    const btnSave = container.querySelector('#set-save')
    const btnPing = container.querySelector('#set-ping')
    const btnTunnel = container.querySelector('#set-tunnel-btn')
    let tunnelAktif = false

    // Profil Usaha & Struk — kartu dimuat & di-wiring secara async.
    mountProfilUsaha(container.querySelector('#set-profil-usaha'))

    // Perpanjang langganan (alur pembayaran Midtrans)
    const perpanjangBtn = container.querySelector('#set-perpanjang')
    if (perpanjangBtn) perpanjangBtn.addEventListener('click', () => mulaiPembayaran())

    // Fitur premium (Segera Hadir) → Hubungi CS via /kontak-cs
    container.querySelectorAll('[data-cs-contact]').forEach((b) => b.addEventListener('click', async () => {
      const r = await api.cs.kontak()
      if (r.ok && r.data && r.data.wa_link) window.open(r.data.wa_link, '_blank')
      else toast(firstError(r) || 'Kontak CS belum tersedia.', 'error')
    }))

    function syncTunnelUI(tr) {
      tunnelAktif = !!(tr && tr.publicUrl)
      const el = container.querySelector('#set-app-tunnel')
      if (el) el.textContent = tunnelAktif ? `Aktif — ${tr.publicUrl}` : 'Nonaktif — hanya jaringan lokal'
      if (btnTunnel) {
        btnTunnel.textContent = tunnelAktif ? 'Matikan Akses Internet' : 'Aktifkan Akses Internet'
        btnTunnel.disabled = !tunnelAktif && !(tr && tr.running)
        btnTunnel.title = tr && tr.running ? '' : 'Masuk Mode Demo dulu agar server pelanggan aktif.'
      }
    }

    btnTunnel.addEventListener('click', async () => {
      const was = tunnelAktif
      btnTunnel.disabled = true
      btnTunnel.textContent = was ? 'Mematikan…' : 'Menyalakan… (±10 dtk)'
      const res = was ? await api.tunnel.stop() : await api.tunnel.start()
      const segar = await api.app.info()
      syncTunnelUI(segar.ok && segar.data ? segar.data.tracking : null)
      if (!res.ok) {
        toast(firstError(res), 'error')
        return
      }
      toast(was ? 'Akses internet publik dimatikan.' : `URL publik aktif — QR baru otomatis memakainya.`, 'success')
    })

    function showUrlError(message) {
      urlError.textContent = message
      urlError.classList.remove('u-hidden')
    }

    function clearUrlError() {
      urlError.textContent = ''
      urlError.classList.add('u-hidden')
    }

    let currentBaseUrl = ''

    async function syncServer() {
      const res = await api.settings.get()
      if (res.ok && res.data && res.data.baseUrl) {
        currentBaseUrl = res.data.baseUrl
        urlActive.textContent = res.data.baseUrl
        if (!urlInput.value) urlInput.value = res.data.baseUrl
      } else {
        urlActive.textContent = 'Tidak diketahui'
        showUrlError(firstError(res) || 'Gagal membaca pengaturan server.')
      }
    }
    syncServer()

    btnSave.addEventListener('click', async () => {
      clearUrlError()
      const value = urlInput.value.trim()
      if (!value) {
        showUrlError('Isi URL server terlebih dahulu.')
        urlInput.focus()
        return
      }
      // Ganti server memutus sesi semua kasir — minta konfirmasi dulu.
      if (currentBaseUrl && value !== currentBaseUrl) {
        const yes = await confirmDialog({
          title: 'Ganti server?',
          message: 'Semua kasir di perangkat ini harus masuk ulang setelah server diganti.',
          confirmText: 'Ya, ganti server',
          danger: true
        })
        if (!yes) return
      }
      btnSave.disabled = true
      btnSave.textContent = 'Menyimpan…'
      const res = await api.settings.setBaseUrl({ baseUrl: value })
      btnSave.disabled = false
      btnSave.textContent = 'Simpan'
      if (!res.ok) {
        showUrlError(firstError(res))
        return
      }
      toast('Server disimpan. Keluar lalu masuk kembali agar sesi mengikuti server baru.', 'success')
      syncServer()
    })

    btnPing.addEventListener('click', async () => {
      btnPing.disabled = true
      btnPing.textContent = 'Menguji…'
      const res = await api.net.ping()
      btnPing.disabled = false
      btnPing.textContent = 'Uji Koneksi'
      if (!res.ok) {
        toast(`Server tidak merespons: ${firstError(res)}`, 'error')
        return
      }
      const serverTime = pickServerTime(res.data)
      toast(
        serverTime ? `Server terhubung. Waktu server: ${serverTime}` : 'Server terhubung dengan baik.',
        'success'
      )
    })

    // Info aplikasi (versi, hostname, platform) dari main process
    const info = await api.app.info()
    const setText = (selector, value) => {
      const el = container.querySelector(selector)
      if (el) el.textContent = value
    }
    if (info.ok && info.data) {
      setText('#set-app-version', info.data.version || info.data.appVersion || '—')
      setText('#set-app-host', info.data.hostname || '—')
      setText('#set-app-platform', info.data.platform || '—')
      const gw = info.data.gateway
      setText('#set-app-gateway', gw && gw.running
        ? `Aktif — port ${gw.port} (cache & proteksi menyala)`
        : 'Tidak aktif — koneksi langsung ke server')
      const tr = info.data.tracking
      setText('#set-app-track', tr && tr.running
        ? `Aktif — ${tr.lanUrl || tr.baseUrl}`
        : 'Tidak aktif')
      syncTunnelUI(tr)
    } else {
      setText('#set-app-version', '—')
      setText('#set-app-host', '—')
      setText('#set-app-platform', '—')
      const appError = container.querySelector('#set-app-error')
      // Bisa null bila pengguna sudah pindah layar sebelum app.info() selesai.
      if (appError) {
        appError.textContent = `Info aplikasi tidak tersedia: ${firstError(info)}`
        appError.classList.remove('u-hidden')
      }
    }
  }
}
