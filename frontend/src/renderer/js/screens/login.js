// Layar Login — juga contoh (exemplar) pola layar:
// render(container) → pasang markup (data API selalu lewat esc()),
// ikat event, kembalikan fungsi cleanup bila perlu.

import { api, firstError } from '../api.js'
import { esc } from '../utils/format.js'
import { toast, showModal, icons } from '../components/ui.js'
import { LOGO_DATA_URI } from '../assets/logo.js'

const eyeIcon = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>`
const eyeOffIcon = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"/><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c6.5 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"/><path d="M6.61 6.61A13.53 13.53 0 0 0 2 12s3.5 7 10 7a9.74 9.74 0 0 0 5.39-1.61"/><line x1="2" x2="22" y1="2" y2="22"/></svg>`

export function renderLogin(container, { onSuccess }) {
  container.innerHTML = `
    <div class="login">
      <aside class="login__brand">
        <div class="login__brand-top">
          <img class="login__logo" src="${LOGO_DATA_URI}" alt="Logo Tuléh" />
          <span class="login__brand-name">Tul<b>éh</b></span>
        </div>
        <div class="login__hero">
          <h1 class="login__hero-title">Kasir modern untuk <em>bisnis yang bergerak cepat</em></h1>
          <p class="login__hero-desc">
            Terhubung langsung dengan backend TATREPORT — stok FIFO, sesi kasir,
            dan laporan penjualan dalam satu aplikasi.
          </p>
        </div>
        <div class="login__features">
          <div class="login__feature">
            <span class="login__feature-icon">${icons.barcode}</span>
            <span>Scan barcode &amp; pencarian produk kilat</span>
          </div>
          <div class="login__feature">
            <span class="login__feature-icon">${icons.session}</span>
            <span>Sesi kasir dengan rekap X/Z otomatis</span>
          </div>
          <div class="login__feature">
            <span class="login__feature-icon">${icons.report}</span>
            <span>Laporan harian, produk, dan stok real-time</span>
          </div>
        </div>
      </aside>

      <section class="login__panel">
        <div class="login__box">
          <div class="login__box-brand">
            <img class="login__box-logo" src="${LOGO_DATA_URI}" alt="" />
            <span class="login__box-name">Tul<b>éh</b></span>
          </div>
          <h2 class="login__title">Selamat datang</h2>
          <p class="login__subtitle">Masuk dengan akun kasir Anda untuk memulai.</p>

          <form class="login__form" id="login-form" novalidate>
            <div class="field">
              <label class="field__label" for="login-user">Email / Username</label>
              <input class="input input--lg" id="login-user" name="login" type="text"
                     placeholder="kasir@toko.com" autocomplete="username" required autofocus />
              <div class="field__error u-hidden" data-error-for="login"></div>
            </div>
            <div class="field">
              <label class="field__label" for="login-pass">Kata sandi</label>
              <div class="password-box">
                <input class="input input--lg" id="login-pass" name="password" type="password"
                       placeholder="••••••••" autocomplete="current-password" required />
                <button type="button" class="password-box__toggle" id="toggle-pass"
                        aria-label="Tampilkan kata sandi">${eyeIcon}</button>
              </div>
              <div class="field__error u-hidden" data-error-for="password"></div>
            </div>
            <div class="field">
              <label class="field__label" for="login-device">Nama perangkat</label>
              <input class="input input--lg" id="login-device" name="device_name" type="text"
                     placeholder="Kasir-01" maxlength="100" />
              <div class="field__hint">Nama untuk membedakan perangkat ini, mis. “Kasir Depan”.</div>
            </div>
            <button class="btn btn--primary btn--lg btn--block" id="btn-login" type="submit">
              Masuk
            </button>
          </form>

          <div class="login__demo">
            <span class="u-muted">Hanya ingin melihat-lihat?</span>
            <button type="button" class="btn btn--outline btn--sm" id="btn-demo">
              Coba Mode Demo
            </button>
          </div>

          <div class="login__server">
            <span>Server: <span class="login__server-host" id="server-host">…</span></span>
            <button type="button" id="btn-change-server">Ubah server</button>
          </div>
        </div>
      </section>
    </div>`

  const form = container.querySelector('#login-form')
  const btnLogin = container.querySelector('#btn-login')
  const serverHost = container.querySelector('#server-host')

  // Prefill nama perangkat dari hostname + tampilkan server aktif
  api.app.info().then((info) => {
    if (info.ok && info.data && !container.querySelector('#login-device').value) {
      container.querySelector('#login-device').value = info.data.hostname || ''
    }
  })

  async function syncServerLabel() {
    const settings = await api.settings.get()
    if (settings.ok && settings.data) {
      serverHost.textContent = settings.data.baseUrl.replace(/^https?:\/\//, '')
    }
  }
  syncServerLabel()

  // Toggle lihat kata sandi
  container.querySelector('#toggle-pass').addEventListener('click', (e) => {
    const btn = e.currentTarget
    const input = container.querySelector('#login-pass')
    const show = input.type === 'password'
    input.type = show ? 'text' : 'password'
    btn.innerHTML = show ? eyeOffIcon : eyeIcon
    btn.setAttribute('aria-label', show ? 'Sembunyikan kata sandi' : 'Tampilkan kata sandi')
    input.focus()
  })

  function setFieldErrors(errors) {
    container.querySelectorAll('[data-error-for]').forEach((el) => {
      el.classList.add('u-hidden')
      el.textContent = ''
    })
    container.querySelectorAll('.input--error').forEach((el) => el.classList.remove('input--error'))
    if (!errors) return
    for (const [field, messages] of Object.entries(errors)) {
      const el = container.querySelector(`[data-error-for="${field}"]`)
      if (el && Array.isArray(messages) && messages[0]) {
        el.textContent = messages[0]
        el.classList.remove('u-hidden')
        const input = container.querySelector(`[name="${field}"]`)
        if (input) input.classList.add('input--error')
      }
    }
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault()
    setFieldErrors(null)

    const login = container.querySelector('#login-user').value.trim()
    const password = container.querySelector('#login-pass').value
    const deviceName = container.querySelector('#login-device').value.trim()

    if (!login || !password) {
      const errors = {}
      if (!login) errors.login = ['Email/username wajib diisi.']
      if (!password) errors.password = ['Kata sandi wajib diisi.']
      setFieldErrors(errors)
      return
    }

    btnLogin.disabled = true
    btnLogin.innerHTML = '<span class="spinner" style="width:18px;height:18px;border-width:2px"></span> Memproses…'

    const result = await api.auth.login({ login, password, deviceName })

    if (result.ok && result.data) {
      toast(`Selamat datang, ${result.data.user?.name || 'Kasir'}!`, 'success')
      onSuccess(result.data)
      return
    }

    btnLogin.disabled = false
    btnLogin.textContent = 'Masuk'
    setFieldErrors(result.errors)
    toast(firstError(result), 'error')
  })

  // Mode Demo — jelajahi aplikasi dengan data dummy, tanpa akun & tanpa jaringan
  container.querySelector('#btn-demo').addEventListener('click', async (e) => {
    const btn = e.currentTarget
    btn.disabled = true
    btn.textContent = 'Menyiapkan data demo…'
    const result = await api.demo.start()
    if (result.ok && result.data) {
      toast('Mode Demo aktif — data simulasi lokal & direset tiap 24 jam.', 'info')
      onSuccess(result.data)
      return
    }
    btn.disabled = false
    btn.textContent = 'Coba Mode Demo'
    toast(firstError(result), 'error')
  })

  // Ganti server (per-domain tenant)
  container.querySelector('#btn-change-server').addEventListener('click', async () => {
    const settings = await api.settings.get()
    const current = settings.ok && settings.data ? settings.data.baseUrl : ''

    const body = document.createElement('div')
    body.innerHTML = `
      <div class="field">
        <label class="field__label" for="server-url">URL server</label>
        <input class="input" id="server-url" type="url" value="${esc(current)}"
               placeholder="https://namadomain.com" />
        <div class="field__hint">
          Wajib HTTPS. Tenant dikenali dari domain — contoh: https://tokosaya.tatreport.com
        </div>
        <div class="field__error u-hidden" id="server-error"></div>
      </div>`

    const footer = document.createElement('div')
    footer.innerHTML = `
      <button class="btn btn--ghost" data-test>Uji koneksi</button>
      <button class="btn btn--primary" data-save>Simpan</button>`
    footer.style.display = 'flex'
    footer.style.gap = 'var(--sp-3)'
    footer.style.justifyContent = 'flex-end'

    const { close } = showModal({ title: 'Ubah server', body, footer })
    const input = body.querySelector('#server-url')
    const errorEl = body.querySelector('#server-error')

    function showError(message) {
      errorEl.textContent = message
      errorEl.classList.remove('u-hidden')
    }

    async function applyUrl() {
      errorEl.classList.add('u-hidden')
      const result = await api.settings.setBaseUrl({ baseUrl: input.value.trim() })
      if (!result.ok) {
        showError(result.message)
        return false
      }
      return true
    }

    footer.querySelector('[data-test]').addEventListener('click', async (event) => {
      const btn = event.currentTarget
      if (!(await applyUrl())) return
      btn.disabled = true
      btn.textContent = 'Menguji…'
      const ping = await api.net.ping()
      btn.disabled = false
      btn.textContent = 'Uji koneksi'
      if (ping.ok) toast('Server merespons dengan baik.', 'success')
      else showError(`Server tidak merespons: ${ping.message}`)
    })

    footer.querySelector('[data-save]').addEventListener('click', async () => {
      if (!(await applyUrl())) return
      toast('Server disimpan.', 'success')
      close()
      syncServerLabel()
    })
  })
}
