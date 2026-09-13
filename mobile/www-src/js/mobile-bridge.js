/* ============================================================================
 * Tuléh Android — jembatan window.iposAPI (pengganti preload/main Electron).
 * Memanggil MOVERA POS API langsung. CapacitorHttp mem-patch fetch → native
 * (bypass CORS). Token & pengaturan disimpan via Capacitor Preferences.
 * Mode Demo: demo.js (di-load via shim CJS → window.__demo) meng-intersep
 * channel data — mirror perilaku handle() di ipc.js desktop.
 *
 * Kanal DATA (produk, sesi, transaksi, meja, …) TIDAK ditulis di sini: dibentuk
 * dari kontrak bersama window.TulehKontrak (frontend/src/shared/kontrak-kanal.js,
 * disalin CI ke www/js). Berkas ini hanya adaptor platform: HTTP, penyimpanan,
 * pembaruan APK, cetak. Permukaan & amplop PERSIS seperti preload.js + ipc.js —
 * dijaga tes frontend/tests/paritas-jembatan.test.js.
 * ========================================================================== */
(function () {
  'use strict'

  var API_PREFIX = '/api/pos/v1'
  var TIMEOUT_MS = 15000
  var DEFAULT_BASE = 'https://tatreport.com'
  // Diganti otomatis saat build (CI: workflow release, lokal: build-android.ps1)
  // dengan versi di frontend/package.json. Angka di sini hanya cadangan bila
  // seseorang membuka www-src langsung.
  var APP_VERSION = '0.9.25'

  var baseUrl = DEFAULT_BASE
  var token = null
  var activeTokoId = null
  var expiredCb = null
  var updateReqCb = null // Auto-Update: dipanggil saat HTTP 426 (update wajib)
  // Auto-Update Tahap 4 (Android in-app installer via plugin native ApkUpdater)
  var apkProgressCb = null
  var apkDownloadedCb = null
  var apkErrorCb = null
  var apkLastPath = null
  var apkProgressBound = false

  /** Plugin native ApkUpdater bila tersedia (build APK), else null (peramban). */
  function apkPlugin () {
    return (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.ApkUpdater) || null
  }
  /** Pasang listener progres native sekali → teruskan ke apkProgressCb. */
  function ensureApkProgress (plugin) {
    if (apkProgressBound || !plugin || typeof plugin.addListener !== 'function') return
    apkProgressBound = true
    try { plugin.addListener('progress', function (e) { if (apkProgressCb) { try { apkProgressCb({ percent: (e && e.percent) || 0 }) } catch (x) {} } }) } catch (x) {}
  }

  // ---- Penyimpanan (Capacitor Preferences; async, akses lazy) ----
  function getPrefs () {
    return (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Preferences) || null
  }
  function prefGet (key) {
    var P = getPrefs()
    if (!P) return Promise.resolve(null)
    return P.get({ key: key }).then(function (r) { return r && r.value != null ? r.value : null }).catch(function () { return null })
  }
  function prefSet (key, value) {
    var P = getPrefs()
    if (!P) return Promise.resolve()
    if (value == null || value === '') return P.remove({ key: key }).catch(function () {})
    return P.set({ key: key, value: String(value) }).catch(function () {})
  }

  var ready = Promise.all([prefGet('baseUrl'), prefGet('token'), prefGet('activeTokoId')])
    .then(function (v) { if (v[0]) baseUrl = v[0]; if (v[1]) token = v[1]; if (v[2]) activeTokoId = v[2] })
    .catch(function () {})

  // ---- Klien API (port api-client.js) ----
  function normalizeBase (u) {
    u = String(u || '').trim().replace(/\/+$/, '')
    if (!/^https?:\/\//i.test(u)) u = 'https://' + u
    return u
  }
  function buildUrl (endpoint, query) {
    var url = new URL(baseUrl + API_PREFIX + endpoint)
    if (query) {
      Object.keys(query).forEach(function (k) {
        var val = query[k]
        if (val === undefined || val === null || val === '') return
        url.searchParams.set(k, String(val))
      })
    }
    return url.toString()
  }
  function statusMessage (s) {
    return ({
      0: 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
      401: 'Sesi Anda telah berakhir. Silakan masuk kembali.',
      403: 'Anda tidak memiliki akses untuk aksi ini.',
      404: 'Data tidak ditemukan.',
      409: 'Aksi bentrok dengan kondisi saat ini.',
      422: 'Data yang dikirim tidak valid.',
      429: 'Terlalu banyak permintaan. Coba lagi sebentar.',
      500: 'Terjadi kesalahan pada server.'
    })[s] || ('Terjadi kesalahan (HTTP ' + s + ').')
  }
  // Amplop {ok,status,data,meta,message} dari respons fetch — sama dengan api-client.js desktop.
  function amplop (res) {
    return res.text().then(function (text) {
      var payload = null
      try { payload = text ? JSON.parse(text) : null } catch (e) { payload = null }
      if (!res.ok || !payload || payload.success === false) {
        if (res.status === 401) { token = null; prefSet('token', null); if (expiredCb) { try { expiredCb() } catch (e) {} } }
        // 426 dari endpoint mana pun = wajib update → beri sinyal ke renderer.
        if (res.status === 426 && updateReqCb) { try { updateReqCb({ message: (payload && payload.message) || 'Aplikasi Anda perlu diperbarui.' }) } catch (e) {} }
        return { ok: false, status: res.status, message: (payload && payload.message) || statusMessage(res.status), errors: (payload && payload.errors) || null }
      }
      return { ok: true, status: res.status, data: payload.data !== undefined ? payload.data : null, meta: payload.meta !== undefined ? payload.meta : null, message: payload.message || '' }
    })
  }
  // Toko aktif disisipkan SETELAH preferensi termuat — permintaan pertama saat app dibuka
  // tidak boleh kehilangan ?toko_id (Owner/Manager multi-toko).
  function denganToko (query) {
    if (!activeTokoId || (query && Object.prototype.hasOwnProperty.call(query, 'toko_id'))) return query
    return Object.assign({}, query || {}, { toko_id: activeTokoId })
  }
  function request (method, endpoint, opts) {
    opts = opts || {}
    var auth = opts.auth !== false
    var hasBody = opts.body !== undefined
    var ctrl = new AbortController()
    var timer = setTimeout(function () { ctrl.abort() }, TIMEOUT_MS)
    return ready
      .then(function () {
        var headers = { Accept: 'application/json', 'X-Tuleh-Version': APP_VERSION }
        if (hasBody) headers['Content-Type'] = 'application/json'
        if (auth && token) headers.Authorization = 'Bearer ' + token
        var query = auth ? denganToko(opts.query) : opts.query
        return fetch(buildUrl(endpoint, query), { method: method, headers: headers, body: hasBody ? JSON.stringify(opts.body) : undefined, signal: ctrl.signal })
      })
      .then(function (res) { clearTimeout(timer); return amplop(res) })
      .catch(function (err) {
        clearTimeout(timer)
        var timedOut = err && err.name === 'AbortError'
        return { ok: false, status: 0, message: timedOut ? 'Server tidak merespons (timeout).' : statusMessage(0), errors: null }
      })
  }
  function apiGet (e, o) { return request('GET', e, o) }
  function apiPost (e, o) { o = o || {}; if (o.body === undefined) o.body = {}; return request('POST', e, o) }

  // Unggah multipart (berkas dari kontrak: {bytes, filename, mime, field}). CapacitorHttp
  // mem-patch fetch → FormData dikirim sebagai multipart native (bypass CORS).
  function unggah (jalur, berkas) {
    berkas = berkas || {}
    if (!berkas.bytes) return notAvailable('File tidak ada.')
    var bytes = berkas.bytes instanceof ArrayBuffer ? new Uint8Array(berkas.bytes) : berkas.bytes
    var form = new FormData()
    form.append(berkas.field || 'logo', new Blob([bytes], { type: berkas.mime || 'application/octet-stream' }), berkas.filename || 'upload.png')
    return ready
      .then(function () {
        var headers = { Accept: 'application/json', 'X-Tuleh-Version': APP_VERSION }
        if (token) headers.Authorization = 'Bearer ' + token
        return fetch(buildUrl(jalur, denganToko({})), { method: 'POST', headers: headers, body: form })
      })
      .then(amplop)
      .catch(function () { return { ok: false, status: 0, message: statusMessage(0), errors: null } })
  }

  // ---- QR (window.qrcode) → data URI SVG (port qr.js) ----
  function qrSvgDataUri (text) {
    if (typeof window.qrcode !== 'function') return null
    var qr = window.qrcode(0, 'M'); qr.addData(String(text), 'Byte'); qr.make()
    return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(qr.createSvgTag({ cellSize: 4, margin: 8 }))
  }
  // Sisip URL+QR lacak ke struk mana pun (data / nota / struk / order). Berlaku
  // untuk hasil DEMO & PRODUKSI agar QR lacak muncul di struk (spt aplikasi
  // desktop yang membungkus demo+produksi dengan enrichTracking).
  function enrich (promise) {
    return promise.then(function (result) {
      if (!result || !result.ok || !result.data) return result
      var d = result.data
      ;[d, d.nota, d.struk, d.order].forEach(function (t) {
        if (t && t.token_lacak && !t.lacak_qr) {
          t.lacak_url = baseUrl + API_PREFIX + '/public/track/' + t.token_lacak
          try { var qr = qrSvgDataUri(t.lacak_url); if (qr) t.lacak_qr = qr } catch (e) {}
        }
      })
      return result
    })
  }
  function printStruk () { try { window.print(); return Promise.resolve({ ok: true, data: null }) } catch (e) { return Promise.resolve({ ok: false, status: 0, message: 'Cetak tidak tersedia.', errors: null }) } }
  function ok (data) { return Promise.resolve({ ok: true, status: 200, data: data === undefined ? null : data, meta: null, message: '' }) }
  function notAvailable (msg) { return Promise.resolve({ ok: false, status: 0, message: msg, errors: null }) }

  // ---- Mode Demo (demo.js via shim CJS → window.__demo) ----
  var demo = window.__demo || null
  var demoActive = false
  function dispatch (channel, payload, prodThunk) {
    var dh = demo && demo.handlers
    if (demoActive && dh && dh[channel]) {
      if (typeof demo.isActive === 'function') demo.isActive() // picu reset TTL 24 jam
      try { return Promise.resolve(dh[channel](payload || {})) }
      catch (e) { return Promise.resolve({ ok: false, status: 0, message: (e && e.message) || 'Kesalahan Mode Demo.', errors: null }) }
    }
    return prodThunk()
  }

  // ---- Kanal data dari kontrak bersama (sama persis dengan ipc.js desktop) ----
  var Kontrak = window.TulehKontrak
  function kirimKontrak (kanal, payload) {
    return ready.then(function () {
      var minta
      try { minta = Kontrak.bentuk(kanal, payload || {}, { tokoAktif: activeTokoId, versiApp: APP_VERSION }) }
      catch (e) { return notAvailable((e && e.message) || 'Permintaan tidak valid.') }
      if (minta.metode === 'UPLOAD') return unggah(minta.jalur, minta.berkas)
      return request(minta.metode, minta.jalur, { query: minta.query, body: minta.body, auth: minta.auth !== false })
    })
  }
  var permukaanData = Kontrak.susunPermukaan({}, function (kanal, entri) {
    return function (payload) {
      var jalan = dispatch(kanal, payload, function () { return kirimKontrak(kanal, payload) })
      return entri.struk ? enrich(jalan) : jalan
    }
  })

  // ---- Preferensi cetak (padanan settings-store.js desktop, disimpan di Preferences) ----
  function bacaCetak () {
    return prefGet('cetak').then(function (raw) {
      var c = {}
      try { c = raw ? JSON.parse(raw) : {} } catch (e) { c = {} }
      return { printer: typeof c.printer === 'string' ? c.printer.slice(0, 200) : '', langsung: !!c.langsung, otomatis: !!c.otomatis }
    })
  }

  // ---- Permukaan khusus platform (cermin preload.js; demo-first dispatch spt ipc.js) ----
  var permukaanPlatform = {
    app: {
      // kemampuan: fitur yang bergantung perangkat — renderer menyembunyikan yang tak didukung
      // (antrean offline & gateway lokal, printer sistem/cetak senyap hanya di desktop).
      info: function () { return ok({ version: APP_VERSION, platform: 'android', kemampuan: { antreanOffline: false, printerSistem: false }, gateway: { ok: false, running: false, external: false }, tracking: { running: false, baseUrl: baseUrl }, smokeDemo: false, smokeTokoIndex: null, smokeScreen: null, smokeTheme: null, smokeOpenBill: false, smokeFlow: null }) },
      print: function () { return printStruk() },
      printers: function () { return ok([]) },
      onUpdateRequired: function (cb) { updateReqCb = cb; return function () { if (updateReqCb === cb) updateReqCb = null } },

      // ---- Auto-Update Tahap 4: unduh+pasang APK di dalam app (plugin native) ----
      // Kontrak dicerminkan dari desktop (electron-updater): downloadUpdate → event
      // 'downloaded' → installUpdate. Bila plugin tak ada (peramban) → supported:false
      // sehingga update.js jatuh ke unduhan peramban (openExternal).
      updateSupported: function () { return ok({ supported: !!apkPlugin() }) },
      downloadUpdate: function (opts) {
        var plugin = apkPlugin()
        if (!plugin) return Promise.resolve({ ok: false, supported: false })
        opts = opts || {}
        var url = opts.url
        if (!url || !/^https:\/\//i.test(url)) return Promise.resolve({ ok: false, message: 'URL unduhan tidak valid.' })
        var filename = opts.filename || 'tuleh-update.apk'
        return Promise.resolve(plugin.canInstall()).then(function (res) {
          if (res && res.granted === false) {
            try { plugin.openInstallPermission() } catch (e) {}
            return { ok: false, needPermission: true, message: 'Izinkan "Instal aplikasi tak dikenal" untuk Tuléh, lalu tekan Update lagi.' }
          }
          ensureApkProgress(plugin)
          return Promise.resolve(plugin.download({ url: url, filename: filename })).then(function (r) {
            apkLastPath = (r && r.path) || null
            if (apkDownloadedCb) { try { apkDownloadedCb({}) } catch (e) {} }
            return { ok: true }
          })
        }).catch(function (err) {
          var msg = (err && (err.message || err.errorMessage)) || 'Gagal mengunduh pembaruan.'
          if (apkErrorCb) { try { apkErrorCb({ message: msg }) } catch (e) {} }
          return { ok: false, message: msg }
        })
      },
      installUpdate: function () {
        var plugin = apkPlugin()
        if (!plugin || !apkLastPath) return { ok: false, message: 'Berkas pembaruan belum siap.' }
        try { plugin.install({ path: apkLastPath }) } catch (e) { return { ok: false, message: 'Gagal membuka pemasang.' } }
        return { ok: true }
      },
      onUpdateProgress: function (cb) { apkProgressCb = cb; return function () { if (apkProgressCb === cb) apkProgressCb = null } },
      onUpdateDownloaded: function (cb) { apkDownloadedCb = cb; return function () { if (apkDownloadedCb === cb) apkDownloadedCb = null } },
      onUpdateError: function (cb) { apkErrorCb = cb; return function () { if (apkErrorCb === cb) apkErrorCb = null } },
      // Buka URL di browser sistem (halaman bayar Midtrans). Capacitor membuka URL
      // lintas-origin (https) di peramban perangkat, bukan di webview app.
      openExternal: function (p) {
        var u = (p && p.url) || ''
        if (!/^https:\/\//i.test(u)) return notAvailable('Hanya URL https yang boleh dibuka.')
        try { window.open(u, '_system') } catch (e) { try { window.open(u, '_blank') } catch (e2) {} }
        return ok(null)
      },
      // Papan antrian butuh server LAN (hanya ada di desktop/EXE).
      openQueueDisplay: function () { return notAvailable('Display Antrian (TV LAN) hanya tersedia di aplikasi desktop.') },
      ensureLanAccess: function () { return notAvailable('Akses LAN (firewall) hanya relevan di aplikasi desktop.') }
    },
    settings: {
      get: function () { return ready.then(function () { return { ok: true, status: 200, data: { baseUrl: baseUrl, hasToken: token != null }, meta: null, message: '' } }) },
      setBaseUrl: function (p) { baseUrl = normalizeBase(p && p.baseUrl); return prefSet('baseUrl', baseUrl).then(function () { return { ok: true, status: 200, data: { baseUrl: baseUrl }, meta: null, message: '' } }) },
      getCetak: function () { return bacaCetak().then(function (c) { return { ok: true, status: 200, data: c, meta: null, message: '' } }) },
      setCetak: function (patch) {
        patch = patch || {}
        return bacaCetak().then(function (lama) {
          var baru = {
            printer: 'printer' in patch ? String(patch.printer || '').slice(0, 200) : lama.printer,
            langsung: 'langsung' in patch ? !!patch.langsung : lama.langsung,
            otomatis: 'otomatis' in patch ? !!patch.otomatis : lama.otomatis
          }
          return prefSet('cetak', JSON.stringify(baru)).then(function () { return { ok: true, status: 200, data: baru, meta: null, message: '' } })
        })
      }
    },
    demo: {
      start: function () {
        if (!demo) return notAvailable('Mode Demo tidak tersedia (modul demo gagal dimuat).')
        var r = demo.start()
        if (r && r.ok) demoActive = true
        return Promise.resolve(r)
      },
      // Masa coba 7 hari ber-HMAC & verifikasi identitas memakai penyimpanan mesin desktop;
      // Mode Demo Android memakai reset 24 jam di demo.js.
      status: function () { return notAvailable('Masa coba Mode Demo dicatat di aplikasi desktop.') },
      otpKirim: function () { return notAvailable('Verifikasi masa coba hanya tersedia di aplikasi desktop.') },
      otpVerifikasi: function () { return notAvailable('Verifikasi masa coba hanya tersedia di aplikasi desktop.') }
    },
    // Antrean offline butuh gateway lokal desktop. Android selalu mengirim langsung → antrean kosong.
    offline: {
      status: function () { return ok({ online: true, total: 0, menunggu: 0, tinjau: 0, ditarikPada: null }) },
      daftar: function () { return ok([]) },
      sinkron: function () { return ok({ terkirim: 0, online: true, total: 0, menunggu: 0, tinjau: 0 }) },
      kirimUlang: function () { return notAvailable('Antrean offline hanya tersedia di aplikasi desktop.') },
      batalkan: function () { return notAvailable('Antrean offline hanya tersedia di aplikasi desktop.') },
      onStatus: function () { return function () {} }
    },
    auth: {
      hasToken: function (p) { return dispatch('auth:hasToken', p, function () { return ready.then(function () { return { ok: true, status: 200, data: { hasToken: token != null }, meta: null, message: '' } }) }) },
      login: function (p) { p = p || {}; return request('POST', '/auth/login', { auth: false, body: { login: p.login, password: p.password, device_name: p.deviceName || 'Android' } }).then(function (r) { if (r.ok && r.data && r.data.token) { token = r.data.token; return prefSet('token', token).then(function () { return r }) } return r }) },
      logout: function (p) {
        return dispatch('auth:logout', p, function () {
          return apiPost('/auth/logout').then(function (r) { token = null; activeTokoId = null; return Promise.all([prefSet('token', null), prefSet('activeTokoId', null)]).then(function () { return r.ok ? r : { ok: true, status: 200, data: null, meta: null, message: '' } }) })
        }).then(function (r) { if (demoActive) { demoActive = false; if (demo && demo.stop) demo.stop() } return r })
      },
      onExpired: function (cb) { expiredCb = cb; return function () { if (expiredCb === cb) expiredCb = null } }
    },
    langganan: {
      // Android tak punya BrowserWindow → buka di peramban perangkat + tandai 'external'
      // (renderer lanjut ke alur poll + "Saya sudah bayar").
      jendelaBayar: function (p) {
        var dh = demo && demo.handlers
        if (demoActive && dh && dh['langganan:jendelaBayar']) { try { return Promise.resolve(dh['langganan:jendelaBayar'](p || {})) } catch (e) {} }
        var u = (p && p.url) || ''
        if (!/^https:\/\//i.test(u)) return notAvailable('URL pembayaran tidak valid.')
        try { window.open(u, '_system') } catch (e) { try { window.open(u, '_blank') } catch (e2) {} }
        return ok({ result: 'external' })
      }
    },
    toko: {
      select: function (p) { return dispatch('toko:select', p, function () { activeTokoId = (p && p.id) || null; return prefSet('activeTokoId', activeTokoId).then(function () { return { ok: true, status: 200, data: { selected: activeTokoId }, meta: null, message: '' } }) }) }
    },
    qr: { make: function (p) { var uri = qrSvgDataUri((p && p.text) || ''); return uri ? ok({ uri: uri, svg: uri }) : notAvailable('QR gagal dibuat.') } },
    // Display Pelanggan: Android tak punya jendela kedua → supported:false, kasir
    // memakai overlay layar-penuh dalam-app (ditangani renderer pos.js).
    customerDisplay: {
      status: function () { return ok({ supported: false, open: false }) },
      open: function () { return ok({ opened: false, supported: false }) },
      close: function () { return ok({ closed: true }) },
      update: function () { return ok(null) },
      onState: function () { return function () {} }
    },
    tunnel: { start: function () { return notAvailable('Akses internet publik (tunnel) tidak tersedia di Android.') }, stop: function () { return ok(null) } }
  }

  // Gabung: kanal data kontrak + metode platform (platform menang bila nama sama).
  var iposAPI = permukaanData
  Object.keys(permukaanPlatform).forEach(function (grup) {
    iposAPI[grup] = Object.assign(iposAPI[grup] || {}, permukaanPlatform[grup])
  })
  window.iposAPI = iposAPI
})()
