/*
 * Kontrak kanal API Tuléh — SATU sumber pemetaan "kanal aplikasi → permintaan HTTP" untuk
 * DESKTOP (src/main/ipc.js, proses utama Electron) dan ANDROID (mobile/www-src/js/mobile-bridge.js,
 * WebView Capacitor).
 *
 * Mengapa ada: dulu kedua platform menulis pemetaannya sendiri-sendiri dan menyimpang —
 * Android tak punya kelola meja, mengirim parameter laporan stok yang salah, dan tidak menyisipkan
 * toko aktif sehingga Owner/Manager di perusahaan multi-toko mendapat "Pilih toko aktif terlebih
 * dahulu" pada pesanan/meja/bon. Kanal baru cukup ditulis DI SINI; kedua platform memakainya.
 *
 * Bentuk entri:
 *   'grup:aksi': {
 *     permukaan: 'grup.metode',           // nama di window.iposAPI (renderer memanggil ini)
 *     buat: (payload, konteks) => ({       // validasi + bentuk permintaan (melempar Error bila tak sah)
 *       metode: 'GET'|'POST'|'PUT'|'PATCH'|'DELETE'|'UPLOAD',
 *       jalur: '/produk', query?, body?, auth?: false, berkas?: { bytes, filename, mime, field }
 *     }),
 *     struk?: true,                        // hasil bisa membawa token_lacak → platform menyisipkan QR lacak
 *     antrean?: { jenis, deltaStok? }      // desktop boleh mengantrekan saat offline (Android: kirim langsung)
 *   }
 * konteks = { tokoAktif: string|null, versiApp: string }
 *
 * Kode sengaja kompatibel WebView lama (ditranspilasi es2017 saat build Android) dan tanpa
 * dependensi Node/DOM.
 */
;(function (akar, pabrik) {
  var modul = pabrik()
  if (typeof module === 'object' && module && module.exports) module.exports = modul
  else akar.TulehKontrak = modul
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict'

  // ---------- Validasi masukan dari renderer (jangan percaya begitu saja) ----------

  function str (value, opsi) {
    const max = (opsi && opsi.max) || 500
    const required = !!(opsi && opsi.required)
    if (value === undefined || value === null || value === '') {
      if (required) throw new Error('Field wajib diisi.')
      return undefined
    }
    // Id API berupa string terenkripsi, tetapi beberapa deployment mengirim angka mentah.
    if (typeof value === 'number' && Number.isFinite(value)) value = String(value)
    if (typeof value !== 'string') throw new Error('Tipe data tidak valid.')
    return value.slice(0, max)
  }

  function num (value, opsi) {
    const required = !!(opsi && opsi.required)
    if (value === undefined || value === null || value === '') {
      if (required) throw new Error('Field wajib diisi.')
      return undefined
    }
    const n = Number(value)
    if (!Number.isFinite(n)) throw new Error('Angka tidak valid.')
    return n
  }

  function intBetween (value, min, max, fallback) {
    const n = Number(value)
    if (!Number.isInteger(n)) return fallback
    return Math.min(max, Math.max(min, n))
  }

  /** Segmen jalur dari id wajib (di-escape). */
  function id (value) {
    return encodeURIComponent(str(value, { required: true }))
  }

  function tanggalRentang (p) {
    return { tanggal_dari: str(p.tanggalDari, { max: 10 }), tanggal_sampai: str(p.tanggalSampai, { max: 10 }) }
  }

  // ---------- Pembentuk body yang dipakai ulang ----------

  // PUT /pengaturan/usaha — hanya kunci yang dikirim renderer (partial). Teks kosong → null.
  function usahaBody (f) {
    const b = {}
    const teksNull = function (v, max) { return v === null || v === undefined || String(v).trim() === '' ? null : String(v).trim().slice(0, max) }
    if ('nama' in f) b.nama = str(f.nama, { required: true, max: 150 })
    if ('alamat' in f) b.alamat = teksNull(f.alamat, 500)
    if ('telepon' in f) b.telepon = teksNull(f.telepon, 30)
    if ('email' in f) b.email = teksNull(f.email, 150)
    if ('struk_footer' in f) b.struk_footer = teksNull(f.struk_footer, 300)
    if ('struk_tampil_logo' in f) b.struk_tampil_logo = !!f.struk_tampil_logo
    return b
  }

  // PUT /pengaturan/pembayaran — daftar bank (maks 5) menggantikan seluruh daftar; hapus_qr menghapus QR statis.
  function pembayaranBody (f) {
    const b = {}
    if (Array.isArray(f.bank)) {
      b.bank = f.bank.slice(0, 5).map(function (r) {
        return {
          bank: (str(r && r.bank, { max: 40 }) || '').trim(),
          rekening: (str(r && r.rekening, { max: 40 }) || '').trim(),
          atas_nama: (str(r && r.atas_nama, { max: 80 }) || '').trim()
        }
      }).filter(function (r) { return r.bank || r.rekening || r.atas_nama })
    }
    if (f.hapusQr) b.hapus_qr = true
    return b
  }

  // PUT /pengaturan/pembayaran/midtrans — kunci {merchant_id, client_key, server_key} ATAU saklar {aktif}.
  function midtransBody (f) {
    const b = {}
    if ('merchant_id' in f) b.merchant_id = str(f.merchant_id, { max: 100 })
    if ('client_key' in f) b.client_key = str(f.client_key, { max: 200 })
    if ('server_key' in f) b.server_key = str(f.server_key, { max: 200 })
    if ('aktif' in f) b.aktif = !!f.aktif
    return b
  }

  function berkas (p, field) {
    return { bytes: p.bytes, filename: p.filename, mime: p.mime, field: field }
  }

  function itemCheckout (items) {
    if (!Array.isArray(items) || items.length === 0) throw new Error('Keranjang masih kosong.')
    if (items.length > 200) throw new Error('Terlalu banyak item dalam satu transaksi.')
    return items.map(function (i) {
      return {
        id_produk: str(i.idProduk, { required: true }),
        harga: num(i.harga, { required: true }),
        kuantitas: num(i.kuantitas, { required: true }),
        diskon_persen: num(i.diskonPersen) === undefined ? 0 : num(i.diskonPersen),
        pajak_persen: num(i.pajakPersen) === undefined ? 0 : num(i.pajakPersen)
      }
    })
  }

  const GET = function (jalur, query) { return { metode: 'GET', jalur: jalur, query: query } }
  const POST = function (jalur, body, query) { return { metode: 'POST', jalur: jalur, body: body, query: query } }

  // ---------- Daftar kanal ----------

  const KANAL = {
    // Aplikasi & koneksi
    'app:checkUpdate': { permukaan: 'app.checkUpdate', buat: function (p, k) { return { metode: 'GET', jalur: '/app/versi', auth: false, query: { versi: k.versiApp } } } },
    'net:ping': { permukaan: 'net.ping', buat: function () { return { metode: 'GET', jalur: '/ping', auth: false } } },
    'auth:me': { permukaan: 'auth.me', buat: function () { return GET('/auth/me') } },
    'config:get': { permukaan: 'config.get', buat: function () { return GET('/config') } },

    // Pengaturan usaha & struk
    'pengaturan:usahaGet': { permukaan: 'pengaturan.usahaGet', buat: function () { return GET('/pengaturan/usaha') } },
    'pengaturan:usahaSimpan': { permukaan: 'pengaturan.usahaSimpan', buat: function (p) { return { metode: 'PUT', jalur: '/pengaturan/usaha', body: usahaBody(p) } } },
    'pengaturan:uploadLogo': { permukaan: 'pengaturan.uploadLogo', buat: function (p) { return { metode: 'UPLOAD', jalur: '/pengaturan/usaha/logo', berkas: berkas(p) } } },
    'pengaturan:uploadLogoStruk': { permukaan: 'pengaturan.uploadLogoStruk', buat: function (p) { return { metode: 'UPLOAD', jalur: '/pengaturan/usaha/logo-struk', berkas: berkas(p) } } },

    // Pembayaran (QR statis + bank, Midtrans)
    'pembayaran:get': { permukaan: 'pembayaran.get', buat: function () { return GET('/pengaturan/pembayaran') } },
    'pembayaran:simpan': { permukaan: 'pembayaran.simpan', buat: function (p) { return { metode: 'PUT', jalur: '/pengaturan/pembayaran', body: pembayaranBody(p) } } },
    'pembayaran:uploadQr': { permukaan: 'pembayaran.uploadQr', buat: function (p) { return { metode: 'UPLOAD', jalur: '/pengaturan/pembayaran/qr', berkas: berkas(p, 'qr') } } },
    'pembayaran:midtransSimpan': { permukaan: 'pembayaran.midtransSimpan', buat: function (p) { return { metode: 'PUT', jalur: '/pengaturan/pembayaran/midtrans', body: midtransBody(p) } } },
    'pembayaran:midtransHapus': { permukaan: 'pembayaran.midtransHapus', buat: function () { return { metode: 'DELETE', jalur: '/pengaturan/pembayaran/midtrans' } } },
    'qris:buatTagihan': { permukaan: 'qris.buatTagihan', buat: function (p) { return POST('/qris/tagihan', { jumlah: num(p.jumlah, { required: true }), keterangan: str(p.keterangan, { max: 190 }) }) } },
    'qris:statusTagihan': { permukaan: 'qris.statusTagihan', buat: function (p) { return GET('/qris/tagihan/' + id(p.id)) } },

    // Langganan & CS
    'langganan:status': { permukaan: 'langganan.status', buat: function () { return GET('/langganan/status') } },
    'langganan:bayar': { permukaan: 'langganan.bayar', buat: function () { return POST('/langganan/bayar', {}) } },
    'cs:kontak': { permukaan: 'cs.kontak', buat: function () { return GET('/kontak-cs') } },

    // Toko & manifest
    'toko:list': { permukaan: 'toko.list', buat: function () { return GET('/tokos') } },
    'toko:manifest': { permukaan: 'toko.manifest', buat: function (p) { return GET('/tokos/' + id(p.id) + '/manifest') } },

    // Stasiun kerja
    'station:list': { permukaan: 'station.list', buat: function () { return GET('/stations') } },
    'station:create': { permukaan: 'station.create', buat: function (p) { return POST('/stations', { type: str(p.type, { required: true, max: 40 }), nama: str(p.nama, { required: true, max: 100 }), kapasitas: num(p.kapasitas) }) } },
    'station:update': { permukaan: 'station.update', buat: function (p) { return { metode: 'PATCH', jalur: '/stations/' + id(p.id), body: { nama: str(p.nama, { max: 100 }), status: str(p.status, { max: 20 }), kapasitas: num(p.kapasitas) } } } },
    'station:delete': { permukaan: 'station.remove', buat: function (p) { return { metode: 'DELETE', jalur: '/stations/' + id(p.id) } } },

    // Pesanan hidup (KDS / papan proses / nota bayar-nanti)
    'order:list': { permukaan: 'order.list', buat: function (p) { return GET('/orders', { stage: str(p.stage, { max: 40 }) }) } },
    'order:transition': { permukaan: 'order.transition', buat: function (p) { return POST('/orders/' + id(p.id) + '/transition', { to: str(p.to, { required: true, max: 40 }) }) } },
    'order:konfirmasiBayar': { permukaan: 'order.konfirmasiBayar', struk: true, buat: function (p) { return POST('/orders/' + id(p.id) + '/transition', { to: 'ANTRIAN', tipe_pembayaran: str(p.tipePembayaran, { max: 20 }) }) } },
    'order:simpanNota': {
      permukaan: 'order.simpanNota',
      struk: true,
      buat: function (p) {
        if (!Array.isArray(p.items) || p.items.length === 0) throw new Error('Keranjang masih kosong.')
        return POST('/orders', {
          bayar: 'NANTI',
          items: p.items.map(function (i) { return { id_produk: str(i.idProduk, { required: true }), harga: num(i.harga, { required: true }), kuantitas: num(i.kuantitas, { required: true }) } }),
          id_pelanggan: str(p.idPelanggan) || null,
          catatan: str(p.catatan, { max: 500 }) || null
        })
      }
    },
    'order:lunasi': { permukaan: 'order.lunasi', struk: true, buat: function (p) { return POST('/orders/' + id(p.id) + '/transition', { to: 'SELESAI', tipe_pembayaran: str(p.tipePembayaran, { max: 20 }) }) } },

    // Meja (server memiliki daftar + kode QR; `semua` menyertakan meja nonaktif)
    'table:list': { permukaan: 'table.list', buat: function (p) { return GET('/tables', p.semua ? { semua: 1 } : {}) } },
    'table:tambah': { permukaan: 'table.tambah', buat: function (p) { return POST('/tables', { nomor: str(p.nomor, { required: true, max: 30 }), kode: str(p.kode, { max: 60 }) || undefined }) } },
    // `kode` tak dikirim bila kosong: QR yang sudah tertempel harus tetap berlaku setelah ganti nomor.
    'table:ubah': {
      permukaan: 'table.ubah',
      buat: function (p) {
        const body = { nomor: str(p.nomor, { required: true, max: 30 }) }
        if (p.kode) body.kode = str(p.kode, { max: 60 })
        return { metode: 'PUT', jalur: '/tables/' + id(p.id), body: body }
      }
    },
    'table:nonaktifkan': { permukaan: 'table.nonaktifkan', buat: function (p) { return { metode: 'DELETE', jalur: '/tables/' + id(p.id) } } },

    // Bon meja (open bill dine-in)
    'bill:peta': { permukaan: 'bill.peta', buat: function () { return GET('/bills', { status: 'BUKA' }) } },
    'bill:buka': { permukaan: 'bill.buka', buat: function (p) { return POST('/bills', { meja_id: str(p.mejaId, { required: true }), pax: num(p.pax) === undefined ? 1 : num(p.pax) }) } },
    'bill:detail': { permukaan: 'bill.detail', buat: function (p) { return GET('/bills/' + id(p.id)) } },
    'bill:tambahRonde': {
      permukaan: 'bill.tambahRonde',
      buat: function (p) {
        if (!Array.isArray(p.items) || p.items.length === 0) throw new Error('Belum ada item pesanan.')
        return POST('/bills/' + id(p.id) + '/rounds', {
          items: p.items.map(function (i) { return { id_produk: str(i.idProduk, { required: true }), kuantitas: num(i.kuantitas, { required: true }), catatan: str(i.catatan, { max: 120 }) || null } }),
          catatan: str(p.catatan, { max: 300 }) || null
        })
      }
    },
    'bill:setPax': { permukaan: 'bill.setPax', buat: function (p) { return { metode: 'PATCH', jalur: '/bills/' + id(p.id), body: { pax: num(p.pax, { required: true }) } } } },
    'bill:cetak': { permukaan: 'bill.cetak', buat: function (p) { return GET('/bills/' + id(p.id) + '/prebill') } },
    'bill:bayar': { permukaan: 'bill.bayar', struk: true, buat: function (p) { return POST('/bills/' + id(p.id) + '/settle', { tipe_pembayaran: str(p.tipePembayaran, { max: 20 }), dibayar: num(p.dibayar) === undefined ? null : num(p.dibayar) }) } },
    'bill:gabung': { permukaan: 'bill.gabung', buat: function (p) { return POST('/bills/' + id(p.idUtama) + '/merge', { bill_id: str(p.idGabung, { required: true }) }) } },
    'bill:batal': { permukaan: 'bill.batal', buat: function (p) { return POST('/bills/' + id(p.id) + '/void', {}) } },

    // Produk & master
    'produk:list': {
      permukaan: 'produk.list',
      buat: function (p) {
        return GET('/produk', {
          q: str(p.q, { max: 190 }),
          kategori_id: str(p.kategoriId),
          gudang_id: str(p.gudangId),
          tipe: str(p.tipe, { max: 10 }), // PRODUK | JASA | SEMUA
          include_habis: p.includeHabis ? 1 : undefined,
          per_page: intBetween(p.perPage, 1, 100, 50),
          page: intBetween(p.page, 1, 100000, 1)
        })
      }
    },
    'produk:barcode': { permukaan: 'produk.byBarcode', buat: function (p) { return GET('/produk/barcode/' + encodeURIComponent(str(p.barcode, { required: true, max: 190 })), { gudang_id: str(p.gudangId) }) } },
    'produk:detail': { permukaan: 'produk.detail', buat: function (p) { return GET('/produk/' + id(p.id), { gudang_id: str(p.gudangId) }) } },
    'produk:create': {
      permukaan: 'produk.create',
      buat: function (p) {
        return POST('/produk', {
          nama: str(p.nama, { required: true, max: 190 }),
          tipe: str(p.tipe, { max: 10 }) || 'PRODUK',
          harga_beli: num(p.hargaBeli),
          harga_jual: num(p.hargaJual, { required: true }),
          barcode: str(p.barcode, { max: 60 }),
          kelola_stok: p.kelolaStok === undefined ? undefined : !!p.kelolaStok
        })
      }
    },
    // PATCH: hanya field yang berubah (renderer mengisi yang berubah saja)
    'produk:update': {
      permukaan: 'produk.update',
      buat: function (p) {
        return {
          metode: 'PATCH',
          jalur: '/produk/' + id(p.id),
          body: {
            nama: str(p.nama, { max: 190 }),
            harga_beli: num(p.hargaBeli),
            harga_jual: num(p.hargaJual),
            barcode: str(p.barcode, { max: 60 }),
            kelola_stok: p.kelolaStok === undefined ? undefined : !!p.kelolaStok
          }
        }
      }
    },
    'produk:remove': { permukaan: 'produk.remove', buat: function (p) { return { metode: 'DELETE', jalur: '/produk/' + id(p.id) } } },
    'master:kategori': { permukaan: 'master.kategori', buat: function () { return GET('/kategori') } },
    'master:gudang': { permukaan: 'master.gudang', buat: function () { return GET('/gudang') } },
    'master:satuan': { permukaan: 'master.satuan', buat: function () { return GET('/satuan') } },

    // Pelanggan
    'pelanggan:list': { permukaan: 'pelanggan.list', buat: function (p) { return GET('/pelanggan', { q: str(p.q, { max: 190 }) }) } },
    'pelanggan:create': { permukaan: 'pelanggan.create', buat: function (p) { return POST('/pelanggan', { nama: str(p.nama, { required: true, max: 190 }), telepon: str(p.telepon, { max: 30 }), alamat: str(p.alamat, { max: 500 }) }) } },
    'pelanggan:detail': { permukaan: 'pelanggan.detail', buat: function (p) { return GET('/pelanggan/' + id(p.id)) } },
    'pelanggan:quick': { permukaan: 'pelanggan.quick', buat: function (p) { return POST('/pelanggan/quick', { nama: str(p.nama, { required: true, max: 190 }), no_whatsapp: str(p.noWhatsapp, { max: 30 }) }) } },

    // Inventory
    'inventory:stokMasuk': {
      permukaan: 'inventory.stokMasuk',
      antrean: {
        jenis: 'STOK_MASUK',
        deltaStok: function (p) { const d = {}; d[str(p.idProduk, { required: true })] = num(p.jumlah, { required: true }); return d }
      },
      buat: function (p) { return POST('/inventory/stok-masuk', { id_produk: str(p.idProduk, { required: true }), jumlah: num(p.jumlah, { required: true }), keterangan: str(p.keterangan, { max: 300 }) }) }
    },
    'inventory:opname': { permukaan: 'inventory.opname', buat: function (p) { return POST('/inventory/opname', { id_produk: str(p.idProduk, { required: true }), jumlah: num(p.jumlah, { required: true }), keterangan: str(p.keterangan, { max: 300 }) }) } },
    'inventory:riwayat': { permukaan: 'inventory.riwayat', buat: function (p) { return GET('/inventory/riwayat', { page: intBetween(p.page, 1, 100000, 1), per_page: intBetween(p.perPage, 1, 100, 25) }) } },

    // Pengeluaran
    'pengeluaran:list': { permukaan: 'pengeluaran.list', buat: function (p) { return GET('/pengeluaran', { bulan: str(p.bulan, { max: 7 }) }) } },
    'pengeluaran:create': {
      permukaan: 'pengeluaran.create',
      antrean: { jenis: 'PENGELUARAN' },
      buat: function (p) { return POST('/pengeluaran', { keterangan: str(p.keterangan, { required: true, max: 190 }), nominal: num(p.nominal, { required: true }), tanggal: str(p.tanggal, { max: 10 }) }) }
    },
    'pengeluaran:remove': { permukaan: 'pengeluaran.remove', buat: function (p) { return { metode: 'DELETE', jalur: '/pengeluaran/' + id(p.id) } } },

    // Sesi kasir
    'sesi:aktif': { permukaan: 'sesi.aktif', buat: function () { return GET('/sesi/aktif') } },
    'sesi:list': { permukaan: 'sesi.list', buat: function (p) { return GET('/sesi', tanggalRentang(p)) } },
    // Sesi diikat ke toko aktif; undefined → hilang dari JSON.
    'sesi:buka': { permukaan: 'sesi.buka', buat: function (p, k) { return POST('/sesi/buka', { gudang_id: str(p.gudangId, { required: true }), kas_awal: num(p.kasAwal, { required: true }), catatan: str(p.catatan, { max: 500 }), toko_id: k.tokoAktif || undefined }) } },
    'sesi:tutup': { permukaan: 'sesi.tutup', buat: function (p) { return POST('/sesi/' + id(p.id) + '/tutup', { kas_akhir_fisik: num(p.kasAkhirFisik, { required: true }), catatan: str(p.catatan, { max: 500 }) }) } },
    'sesi:rekap': { permukaan: 'sesi.rekap', buat: function (p) { return GET('/sesi/' + id(p.id) + '/rekap') } },

    // Transaksi
    'trx:checkout': {
      permukaan: 'trx.checkout',
      struk: true,
      buat: function (p) {
        return POST('/transaksi/checkout', {
          items: itemCheckout(p.items),
          tipe_pembayaran: str(p.tipePembayaran, { required: true, max: 20 }),
          dibayar: num(p.dibayar, { required: true }),
          id_pelanggan: str(p.idPelanggan) || null,
          catatan: str(p.catatan, { max: 500 }) || null,
          // QRIS terverifikasi (Midtrans): id tagihan LUNAS — hanya bila ada.
          qris_tagihan_id: str(p.qrisTagihanId) || undefined
        })
      }
    },
    'trx:list': {
      permukaan: 'trx.list',
      buat: function (p) {
        const r = tanggalRentang(p)
        // Dua gaya nama parameter sekaligus (OpenAPI tanggal_dari/sampai, Docs-API dari/sampai).
        return GET('/transaksi', { status: str(p.status, { max: 20 }), sesi_id: str(p.sesiId), tanggal_dari: r.tanggal_dari, tanggal_sampai: r.tanggal_sampai, dari: r.tanggal_dari, sampai: r.tanggal_sampai })
      }
    },
    'trx:detail': { permukaan: 'trx.detail', buat: function (p) { return GET('/transaksi/' + id(p.id)) } },
    'trx:batal': { permukaan: 'trx.batal', buat: function (p) { return POST('/transaksi/' + id(p.id) + '/batal') } },

    // Laporan
    'laporan:penjualanHarian': { permukaan: 'laporan.penjualanHarian', buat: function (p) { return GET('/laporan/penjualan-harian', tanggalRentang(p)) } },
    'laporan:penjualanProduk': { permukaan: 'laporan.penjualanProduk', buat: function (p) { return GET('/laporan/penjualan-produk', tanggalRentang(p)) } },
    'laporan:stok': { permukaan: 'laporan.stok', buat: function (p) { return GET('/laporan/stok', { gudang_id: str(p.gudangId) }) } },
    'laporan:rekapKasir': { permukaan: 'laporan.rekapKasir', buat: function (p) { return GET('/laporan/rekap-kasir', tanggalRentang(p)) } },
    'laporan:keuangan': { permukaan: 'laporan.keuangan', buat: function (p) { return GET('/laporan/keuangan', { bulan: str(p.bulan, { max: 7 }) }) } }
  }

  /** Bentuk permintaan untuk satu kanal. Melempar Error berpesan manusiawi bila masukan tak sah. */
  function bentuk (kanal, payload, konteks) {
    const entri = KANAL[kanal]
    if (!entri) throw new Error('Kanal tidak dikenal: ' + kanal)
    return entri.buat(payload || {}, konteks || { tokoAktif: null, versiApp: '' })
  }

  /** Pasang fungsi `pembuat(kanal, entri)` ke objek permukaan bertingkat {grup: {metode: fn}}. */
  function susunPermukaan (target, pembuat) {
    Object.keys(KANAL).forEach(function (kanal) {
      const bagian = KANAL[kanal].permukaan.split('.')
      const grup = bagian[0]
      const metode = bagian[1]
      target[grup] = target[grup] || {}
      target[grup][metode] = pembuat(kanal, KANAL[kanal])
    })
    return target
  }

  return { KANAL, bentuk, susunPermukaan, str, num, intBetween, usahaBody, pembayaranBody, midtransBody }
})
