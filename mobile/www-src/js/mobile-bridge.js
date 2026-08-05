/* ============================================================================
 * Tuléh Android — jembatan window.iposAPI (pengganti preload/main Electron).
 * Memanggil MOVERA POS API langsung. CapacitorHttp mem-patch fetch → native
 * (bypass CORS). Token & pengaturan disimpan via Capacitor Preferences.
 * Mode Demo: demo.js (di-load via shim CJS → window.__demo) meng-intersep
 * channel data — mirror perilaku handle() di ipc.js desktop.
 * Permukaan & envelope PERSIS seperti preload.js + ipc.js.
 * ========================================================================== */
(function () {
  'use strict'

  var API_PREFIX = '/api/pos/v1'
  var TIMEOUT_MS = 15000
  var DEFAULT_BASE = 'https://tatreport.com'
  var APP_VERSION = '0.9.1'

  var baseUrl = DEFAULT_BASE
  var token = null
  var activeTokoId = null
  var expiredCb = null

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
  function request (method, endpoint, opts) {
    opts = opts || {}
    var auth = opts.auth !== false
    var query = opts.query
    if (auth && activeTokoId && !(query && Object.prototype.hasOwnProperty.call(query, 'toko_id'))) {
      query = Object.assign({}, query || {}, { toko_id: activeTokoId })
    }
    var headers = { Accept: 'application/json' }
    var hasBody = opts.body !== undefined
    if (hasBody) headers['Content-Type'] = 'application/json'
    if (auth && token) headers.Authorization = 'Bearer ' + token
    var ctrl = new AbortController()
    var timer = setTimeout(function () { ctrl.abort() }, TIMEOUT_MS)
    return ready
      .then(function () {
        return fetch(buildUrl(endpoint, query), { method: method, headers: headers, body: hasBody ? JSON.stringify(opts.body) : undefined, signal: ctrl.signal })
      })
      .then(function (res) {
        clearTimeout(timer)
        return res.text().then(function (text) {
          var payload = null
          try { payload = text ? JSON.parse(text) : null } catch (e) { payload = null }
          if (!res.ok || !payload || payload.success === false) {
            if (res.status === 401) { token = null; prefSet('token', null); if (expiredCb) { try { expiredCb() } catch (e) {} } }
            return { ok: false, status: res.status, message: (payload && payload.message) || statusMessage(res.status), errors: (payload && payload.errors) || null }
          }
          return { ok: true, status: res.status, data: payload.data !== undefined ? payload.data : null, meta: payload.meta !== undefined ? payload.meta : null, message: payload.message || '' }
        })
      })
      .catch(function (err) {
        clearTimeout(timer)
        var timedOut = err && err.name === 'AbortError'
        return { ok: false, status: 0, message: timedOut ? 'Server tidak merespons (timeout).' : statusMessage(0), errors: null }
      })
  }
  function apiGet (e, o) { return request('GET', e, o) }
  function apiPost (e, o) { o = o || {}; if (o.body === undefined) o.body = {}; return request('POST', e, o) }
  function enc (v) { return encodeURIComponent(String(v == null ? '' : v)) }

  // Body PUT /pengaturan/usaha (partial). Teks kosong pada field boleh-null → null.
  function usahaBody (p) {
    p = p || {}
    var b = {}
    var tn = function (v, max) { return (v === null || v === undefined || String(v).trim() === '') ? null : String(v).trim().slice(0, max) }
    if ('nama' in p) b.nama = String(p.nama || '').trim().slice(0, 150)
    if ('alamat' in p) b.alamat = tn(p.alamat, 500)
    if ('telepon' in p) b.telepon = tn(p.telepon, 30)
    if ('email' in p) b.email = tn(p.email, 150)
    if ('struk_footer' in p) b.struk_footer = tn(p.struk_footer, 300)
    if ('struk_tampil_logo' in p) b.struk_tampil_logo = !!p.struk_tampil_logo
    return b
  }
  // Body PUT /pengaturan/pembayaran — daftar bank (maks 5) + hapus_qr.
  function pembayaranBody (p) {
    p = p || {}
    var b = {}
    if (Array.isArray(p.bank)) {
      b.bank = p.bank.slice(0, 5).map(function (r) {
        return {
          bank: String((r && r.bank) || '').trim().slice(0, 40),
          rekening: String((r && r.rekening) || '').trim().slice(0, 40),
          atas_nama: String((r && r.atas_nama) || '').trim().slice(0, 80)
        }
      }).filter(function (r) { return r.bank || r.rekening || r.atas_nama })
    }
    if (p.hapusQr) b.hapus_qr = true
    return b
  }
  // Body PUT /pengaturan/pembayaran/midtrans — pasang key ATAU saklar aktif.
  function midtransBody (p) {
    p = p || {}
    var b = {}
    if ('merchant_id' in p) b.merchant_id = String(p.merchant_id || '').slice(0, 100)
    if ('client_key' in p) b.client_key = String(p.client_key || '').slice(0, 200)
    if ('server_key' in p) b.server_key = String(p.server_key || '').slice(0, 200)
    if ('aktif' in p) b.aktif = !!p.aktif
    return b
  }
  // Unggah logo multipart (field `logo`). CapacitorHttp mem-patch fetch → FormData
  // dikirim sebagai multipart native (bypass CORS).
  function uploadLogo (endpoint, p, field) {
    p = p || {}
    if (!p.bytes) return notAvailable('File tidak ada.')
    var bytes = p.bytes instanceof ArrayBuffer ? new Uint8Array(p.bytes) : p.bytes
    var form = new FormData()
    form.append(field || 'logo', new Blob([bytes], { type: p.mime || 'application/octet-stream' }), p.filename || 'upload.png')
    var headers = { Accept: 'application/json' }
    if (token) headers.Authorization = 'Bearer ' + token
    var url = buildUrl(endpoint, activeTokoId ? { toko_id: activeTokoId } : {})
    return ready
      .then(function () { return fetch(url, { method: 'POST', headers: headers, body: form }) })
      .then(function (res) {
        return res.text().then(function (text) {
          var payload = null
          try { payload = text ? JSON.parse(text) : null } catch (e) { payload = null }
          if (!res.ok || !payload || payload.success === false) {
            if (res.status === 401) { token = null; prefSet('token', null); if (expiredCb) { try { expiredCb() } catch (e) {} } }
            return { ok: false, status: res.status, message: (payload && payload.message) || statusMessage(res.status), errors: (payload && payload.errors) || null }
          }
          return { ok: true, status: res.status, data: payload.data !== undefined ? payload.data : null, meta: payload.meta !== undefined ? payload.meta : null, message: payload.message || '' }
        })
      })
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

  // ---- Permukaan iposAPI (cermin preload.js; demo-first dispatch spt ipc.js) ----
  window.iposAPI = {
    app: {
      info: function () { return ok({ version: APP_VERSION, platform: 'android', gateway: { ok: false, running: false, external: false }, tracking: { running: false, baseUrl: baseUrl }, smokeDemo: false, smokeTokoIndex: null, smokeScreen: null, smokeTheme: null, smokeOpenBill: false, smokeFlow: null }) },
      print: function () { return printStruk() },
      // Buka URL di browser sistem (halaman bayar Midtrans). Capacitor membuka URL
      // lintas-origin (https) di peramban perangkat, bukan di webview app.
      openExternal: function (p) {
        var u = (p && p.url) || ''
        if (!/^https:\/\//i.test(u)) return notAvailable('Hanya URL https yang boleh dibuka.')
        try { window.open(u, '_system') } catch (e) { try { window.open(u, '_blank') } catch (e2) {} }
        return ok(null)
      }
    },
    settings: {
      get: function () { return ready.then(function () { return { ok: true, status: 200, data: { baseUrl: baseUrl, hasToken: token != null }, meta: null, message: '' } }) },
      setBaseUrl: function (p) { baseUrl = normalizeBase(p && p.baseUrl); return prefSet('baseUrl', baseUrl).then(function () { return { ok: true, status: 200, data: { baseUrl: baseUrl }, meta: null, message: '' } }) }
    },
    demo: {
      start: function () {
        if (!demo) return notAvailable('Mode Demo tidak tersedia (modul demo gagal dimuat).')
        var r = demo.start()
        if (r && r.ok) demoActive = true
        return Promise.resolve(r)
      }
    },
    net: { ping: function (p) { return dispatch('net:ping', p, function () { return apiGet('/ping', { auth: false }) }) } },
    auth: {
      hasToken: function (p) { return dispatch('auth:hasToken', p, function () { return ready.then(function () { return { ok: true, status: 200, data: { hasToken: token != null }, meta: null, message: '' } }) }) },
      login: function (p) { p = p || {}; return request('POST', '/auth/login', { auth: false, body: { login: p.login, password: p.password, device_name: p.deviceName || 'Android' } }).then(function (r) { if (r.ok && r.data && r.data.token) { token = r.data.token; return prefSet('token', token).then(function () { return r }) } return r }) },
      me: function (p) { return dispatch('auth:me', p, function () { return apiGet('/auth/me') }) },
      logout: function (p) {
        return dispatch('auth:logout', p, function () {
          return apiPost('/auth/logout').then(function (r) { token = null; activeTokoId = null; return Promise.all([prefSet('token', null), prefSet('activeTokoId', null)]).then(function () { return r.ok ? r : { ok: true, status: 200, data: null, meta: null, message: '' } }) })
        }).then(function (r) { if (demoActive) { demoActive = false; if (demo && demo.stop) demo.stop() } return r })
      },
      onExpired: function (cb) { expiredCb = cb; return function () { if (expiredCb === cb) expiredCb = null } }
    },
    config: { get: function (p) { return dispatch('config:get', p, function () { return apiGet('/config') }) } },
    pengaturan: {
      usahaGet: function (p) { return dispatch('pengaturan:usahaGet', p, function () { return apiGet('/pengaturan/usaha') }) },
      usahaSimpan: function (p) { return dispatch('pengaturan:usahaSimpan', p, function () { return request('PUT', '/pengaturan/usaha', { body: usahaBody(p) }) }) },
      uploadLogo: function (p) { return dispatch('pengaturan:uploadLogo', p, function () { return uploadLogo('/pengaturan/usaha/logo', p) }) },
      uploadLogoStruk: function (p) { return dispatch('pengaturan:uploadLogoStruk', p, function () { return uploadLogo('/pengaturan/usaha/logo-struk', p) }) }
    },
    pembayaran: {
      get: function (p) { return dispatch('pembayaran:get', p, function () { return apiGet('/pengaturan/pembayaran') }) },
      simpan: function (p) { return dispatch('pembayaran:simpan', p, function () { return request('PUT', '/pengaturan/pembayaran', { body: pembayaranBody(p) }) }) },
      uploadQr: function (p) { return dispatch('pembayaran:uploadQr', p, function () { return uploadLogo('/pengaturan/pembayaran/qr', p, 'qr') }) },
      midtransSimpan: function (p) { return dispatch('pembayaran:midtransSimpan', p, function () { return request('PUT', '/pengaturan/pembayaran/midtrans', { body: midtransBody(p) }) }) },
      midtransHapus: function (p) { return dispatch('pembayaran:midtransHapus', p, function () { return request('DELETE', '/pengaturan/pembayaran/midtrans') }) }
    },
    qris: {
      buatTagihan: function (p) { p = p || {}; return dispatch('qris:buatTagihan', p, function () { return apiPost('/qris/tagihan', { body: { jumlah: p.jumlah, keterangan: p.keterangan } }) }) },
      statusTagihan: function (p) { p = p || {}; return dispatch('qris:statusTagihan', p, function () { return apiGet('/qris/tagihan/' + enc(p.id)) }) }
    },
    langganan: {
      status: function (p) { return dispatch('langganan:status', p, function () { return apiGet('/langganan/status') }) },
      bayar: function (p) { return dispatch('langganan:bayar', p, function () { return apiPost('/langganan/bayar', { body: {} }) }) },
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
    cs: { kontak: function (p) { return dispatch('cs:kontak', p, function () { return apiGet('/kontak-cs') }) } },
    toko: {
      list: function (p) { return dispatch('toko:list', p, function () { return apiGet('/tokos') }) },
      manifest: function (p) { return dispatch('toko:manifest', p, function () { return apiGet('/tokos/' + enc(p && p.id) + '/manifest') }) },
      select: function (p) { return dispatch('toko:select', p, function () { activeTokoId = (p && p.id) || null; return prefSet('activeTokoId', activeTokoId).then(function () { return { ok: true, status: 200, data: { selected: activeTokoId }, meta: null, message: '' } }) }) }
    },
    order: {
      list: function (p) { return dispatch('order:list', p, function () { return apiGet('/orders', { query: { stage: (p && p.stage) || undefined } }) }) },
      transition: function (p) { return dispatch('order:transition', p, function () { return apiPost('/orders/' + enc(p && p.id) + '/transition', { body: { to: p && p.to } }) }) },
      konfirmasiBayar: function (p) { return enrich(dispatch('order:konfirmasiBayar', p, function () { return apiPost('/orders/' + enc(p && p.id) + '/transition', { body: { to: 'ANTRIAN', tipe_pembayaran: p && p.tipePembayaran } }) })) },
      simpanNota: function (p) { p = p || {}; return enrich(dispatch('order:simpanNota', p, function () { return apiPost('/orders', { body: { bayar: 'NANTI', items: (p.items || []).map(function (i) { return { id_produk: i.idProduk, harga: i.harga, kuantitas: i.kuantitas } }), id_pelanggan: p.idPelanggan || null, catatan: p.catatan || null } }) })) },
      lunasi: function (p) { return enrich(dispatch('order:lunasi', p, function () { return apiPost('/orders/' + enc(p && p.id) + '/transition', { body: { to: 'SELESAI', tipe_pembayaran: p && p.tipePembayaran } }) })) }
    },
    table: { list: function (p) { return dispatch('table:list', p, function () { return apiGet('/tables') }) } },
    bill: {
      peta: function (p) { return dispatch('bill:peta', p, function () { return apiGet('/bills', { query: { status: 'BUKA' } }) }) },
      buka: function (p) { return dispatch('bill:buka', p, function () { return apiPost('/bills', { body: { meja_id: p && p.mejaId, pax: (p && p.pax) || 1 } }) }) },
      detail: function (p) { return dispatch('bill:detail', p, function () { return apiGet('/bills/' + enc(p && p.id)) }) },
      tambahRonde: function (p) { p = p || {}; return dispatch('bill:tambahRonde', p, function () { return apiPost('/bills/' + enc(p.id) + '/rounds', { body: { items: (p.items || []).map(function (i) { return { id_produk: i.idProduk, kuantitas: i.kuantitas, catatan: i.catatan || null } }), catatan: p.catatan || null } }) }) },
      setPax: function (p) { return dispatch('bill:setPax', p, function () { return request('PATCH', '/bills/' + enc(p && p.id), { body: { pax: p && p.pax } }) }) },
      cetak: function (p) { return dispatch('bill:cetak', p, function () { return apiGet('/bills/' + enc(p && p.id) + '/prebill') }) },
      bayar: function (p) { return enrich(dispatch('bill:bayar', p, function () { return apiPost('/bills/' + enc(p && p.id) + '/settle', { body: { tipe_pembayaran: p && p.tipePembayaran, dibayar: (p && p.dibayar != null) ? p.dibayar : null } }) })) },
      gabung: function (p) { return dispatch('bill:gabung', p, function () { return apiPost('/bills/' + enc(p && p.idUtama) + '/merge', { body: { bill_id: p && p.idGabung } }) }) },
      batal: function (p) { return dispatch('bill:batal', p, function () { return apiPost('/bills/' + enc(p && p.id) + '/void', { body: {} }) }) }
    },
    qr: { make: function (p) { var uri = qrSvgDataUri((p && p.text) || ''); return uri ? ok({ svg: uri }) : notAvailable('QR gagal dibuat.') } },
    tunnel: { start: function () { return notAvailable('Akses internet publik (tunnel) tidak tersedia di Android.') }, stop: function () { return ok(null) } },
    station: {
      list: function (p) { return dispatch('station:list', p, function () { return apiGet('/stations') }) },
      create: function (p) { return dispatch('station:create', p, function () { return apiPost('/stations', { body: { type: p && p.type, nama: p && p.nama, kapasitas: p && p.kapasitas } }) }) },
      update: function (p) { p = p || {}; return dispatch('station:update', p, function () { return request('PATCH', '/stations/' + enc(p.id), { body: { nama: p.nama, status: p.status, kapasitas: p.kapasitas } }) }) },
      remove: function (p) { return dispatch('station:delete', p, function () { return request('DELETE', '/stations/' + enc(p && p.id)) }) }
    },
    produk: {
      list: function (p) { p = p || {}; return dispatch('produk:list', p, function () { return apiGet('/produk', { query: { q: p.q, kategori_id: p.kategoriId, gudang_id: p.gudangId, tipe: p.tipe, include_habis: p.includeHabis ? 1 : undefined, per_page: p.perPage || 50, page: p.page || 1 } }) }) },
      byBarcode: function (p) { p = p || {}; return dispatch('produk:barcode', p, function () { return apiGet('/produk/barcode/' + enc(p.barcode), { query: { gudang_id: p.gudangId } }) }) },
      detail: function (p) { p = p || {}; return dispatch('produk:detail', p, function () { return apiGet('/produk/' + enc(p.id), { query: { gudang_id: p.gudangId } }) }) },
      create: function (p) { p = p || {}; return dispatch('produk:create', p, function () { return apiPost('/produk', { body: { nama: p.nama, tipe: p.tipe || 'PRODUK', harga_beli: p.hargaBeli, harga_jual: p.hargaJual, barcode: p.barcode, kelola_stok: p.kelolaStok } }) }) },
      update: function (p) { p = p || {}; return dispatch('produk:update', p, function () { return request('PATCH', '/produk/' + enc(p.id), { body: { nama: p.nama, harga_beli: p.hargaBeli, harga_jual: p.hargaJual, barcode: p.barcode, kelola_stok: p.kelolaStok } }) }) },
      remove: function (p) { p = p || {}; return dispatch('produk:remove', p, function () { return request('DELETE', '/produk/' + enc(p.id)) }) }
    },
    master: {
      kategori: function (p) { return dispatch('master:kategori', p, function () { return apiGet('/kategori') }) },
      gudang: function (p) { return dispatch('master:gudang', p, function () { return apiGet('/gudang') }) },
      satuan: function (p) { return dispatch('master:satuan', p, function () { return apiGet('/satuan') }) }
    },
    pelanggan: {
      list: function (p) { return dispatch('pelanggan:list', p, function () { return apiGet('/pelanggan', { query: { q: p && p.q } }) }) },
      create: function (p) { p = p || {}; return dispatch('pelanggan:create', p, function () { return apiPost('/pelanggan', { body: { nama: p.nama, telepon: p.telepon, alamat: p.alamat } }) }) },
      quick: function (p) { p = p || {}; return dispatch('pelanggan:quick', p, function () { return apiPost('/pelanggan/quick', { body: { nama: p.nama, no_whatsapp: p.noWhatsapp } }) }) },
      detail: function (p) { return dispatch('pelanggan:detail', p, function () { return apiGet('/pelanggan/' + enc(p && p.id)) }) }
    },
    inventory: {
      stokMasuk: function (p) { p = p || {}; return dispatch('inventory:stokMasuk', p, function () { return apiPost('/inventory/stok-masuk', { body: { id_produk: p.idProduk, jumlah: p.jumlah, keterangan: p.keterangan } }) }) },
      opname: function (p) { p = p || {}; return dispatch('inventory:opname', p, function () { return apiPost('/inventory/opname', { body: { id_produk: p.idProduk, jumlah: p.jumlah, keterangan: p.keterangan } }) }) },
      riwayat: function (p) { p = p || {}; return dispatch('inventory:riwayat', p, function () { return apiGet('/inventory/riwayat', { query: { page: p.page || 1, per_page: p.perPage || 25 } }) }) }
    },
    pengeluaran: {
      list: function (p) { p = p || {}; return dispatch('pengeluaran:list', p, function () { return apiGet('/pengeluaran', { query: { bulan: p.bulan } }) }) },
      create: function (p) { p = p || {}; return dispatch('pengeluaran:create', p, function () { return apiPost('/pengeluaran', { body: { keterangan: p.keterangan, nominal: p.nominal, tanggal: p.tanggal } }) }) },
      remove: function (p) { p = p || {}; return dispatch('pengeluaran:remove', p, function () { return request('DELETE', '/pengeluaran/' + enc(p.id)) }) }
    },
    sesi: {
      aktif: function (p) { return dispatch('sesi:aktif', p, function () { return apiGet('/sesi/aktif') }) },
      list: function (p) { p = p || {}; return dispatch('sesi:list', p, function () { return apiGet('/sesi', { query: { tanggal_dari: p.tanggalDari, tanggal_sampai: p.tanggalSampai } }) }) },
      buka: function (p) { p = p || {}; return dispatch('sesi:buka', p, function () { return apiPost('/sesi/buka', { body: { gudang_id: p.gudangId, kas_awal: p.kasAwal, catatan: p.catatan, toko_id: activeTokoId || undefined } }) }) },
      tutup: function (p) { p = p || {}; return dispatch('sesi:tutup', p, function () { return apiPost('/sesi/' + enc(p.id) + '/tutup', { body: { kas_akhir_fisik: p.kasAkhirFisik, catatan: p.catatan } }) }) },
      rekap: function (p) { return dispatch('sesi:rekap', p, function () { return apiGet('/sesi/' + enc(p && p.id) + '/rekap') }) }
    },
    trx: {
      checkout: function (p) { p = p || {}; return enrich(dispatch('trx:checkout', p, function () { return apiPost('/transaksi/checkout', { body: { items: (p.items || []).map(function (i) { return { id_produk: i.idProduk, harga: i.harga, kuantitas: i.kuantitas, diskon_persen: i.diskonPersen || 0, pajak_persen: i.pajakPersen || 0 } }), tipe_pembayaran: p.tipePembayaran, dibayar: p.dibayar, id_pelanggan: p.idPelanggan || null, catatan: p.catatan || null } }) })) },
      list: function (p) { p = p || {}; return dispatch('trx:list', p, function () { return apiGet('/transaksi', { query: { status: p.status, sesi_id: p.sesiId, tanggal_dari: p.tanggalDari, tanggal_sampai: p.tanggalSampai, dari: p.tanggalDari, sampai: p.tanggalSampai } }) }) },
      detail: function (p) { return dispatch('trx:detail', p, function () { return apiGet('/transaksi/' + enc(p && p.id)) }) },
      batal: function (p) { return dispatch('trx:batal', p, function () { return apiPost('/transaksi/' + enc(p && p.id) + '/batal', { body: {} }) }) }
    },
    laporan: {
      penjualanHarian: function (p) { p = p || {}; return dispatch('laporan:penjualanHarian', p, function () { return apiGet('/laporan/penjualan-harian', { query: { tanggal_dari: p.tanggalDari, tanggal_sampai: p.tanggalSampai } }) }) },
      penjualanProduk: function (p) { p = p || {}; return dispatch('laporan:penjualanProduk', p, function () { return apiGet('/laporan/penjualan-produk', { query: { tanggal_dari: p.tanggalDari, tanggal_sampai: p.tanggalSampai } }) }) },
      stok: function (p) { p = p || {}; return dispatch('laporan:stok', p, function () { return apiGet('/laporan/stok', { query: { tanggal_dari: p.tanggalDari, tanggal_sampai: p.tanggalSampai } }) }) },
      rekapKasir: function (p) { p = p || {}; return dispatch('laporan:rekapKasir', p, function () { return apiGet('/laporan/rekap-kasir', { query: { tanggal_dari: p.tanggalDari, tanggal_sampai: p.tanggalSampai } }) }) },
      keuangan: function (p) { p = p || {}; return dispatch('laporan:keuangan', p, function () { return apiGet('/laporan/keuangan', { query: { bulan: p.bulan } }) }) }
    }
  }
})()
