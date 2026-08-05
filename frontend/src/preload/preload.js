'use strict'

const { contextBridge, ipcRenderer } = require('electron')

const invoke = (channel) => (payload) => ipcRenderer.invoke(channel, payload)

// Permukaan API yang sempit dan eksplisit — renderer tidak pernah menyentuh
// Node.js, filesystem, maupun token autentikasi.
contextBridge.exposeInMainWorld('iposAPI', {
  app: {
    info: invoke('app:info'),
    print: invoke('app:print'),
    openExternal: invoke('app:openExternal'),
    openQueueDisplay: invoke('display:antrian')
  },
  // Display Pelanggan — window kasir memanggil open/close/update/status;
  // window pelanggan (index.html?display=customer) berlangganan onState.
  customerDisplay: {
    status: invoke('customer:status'),
    open: invoke('customer:open'),
    close: invoke('customer:close'),
    update: invoke('customer:update'),
    onState(callback) {
      const listener = (_event, state) => callback(state)
      ipcRenderer.on('customer:state', listener)
      return () => ipcRenderer.removeListener('customer:state', listener)
    }
  },
  settings: {
    get: invoke('settings:get'),
    setBaseUrl: invoke('settings:setBaseUrl')
  },
  demo: {
    start: invoke('demo:start')
  },
  net: {
    ping: invoke('net:ping')
  },
  auth: {
    hasToken: invoke('auth:hasToken'),
    login: invoke('auth:login'),
    me: invoke('auth:me'),
    logout: invoke('auth:logout'),
    onExpired(callback) {
      const listener = () => callback()
      ipcRenderer.on('auth:expired', listener)
      return () => ipcRenderer.removeListener('auth:expired', listener)
    }
  },
  config: {
    get: invoke('config:get')
  },
  pengaturan: {
    usahaGet: invoke('pengaturan:usahaGet'),
    usahaSimpan: invoke('pengaturan:usahaSimpan'),
    uploadLogo: invoke('pengaturan:uploadLogo'),
    uploadLogoStruk: invoke('pengaturan:uploadLogoStruk')
  },
  pembayaran: {
    get: invoke('pembayaran:get'),
    simpan: invoke('pembayaran:simpan'),
    uploadQr: invoke('pembayaran:uploadQr'),
    midtransSimpan: invoke('pembayaran:midtransSimpan'),
    midtransHapus: invoke('pembayaran:midtransHapus')
  },
  qris: {
    buatTagihan: invoke('qris:buatTagihan'),
    statusTagihan: invoke('qris:statusTagihan')
  },
  langganan: {
    status: invoke('langganan:status'),
    bayar: invoke('langganan:bayar'),
    jendelaBayar: invoke('langganan:jendelaBayar')
  },
  cs: {
    kontak: invoke('cs:kontak')
  },
  toko: {
    list: invoke('toko:list'),
    manifest: invoke('toko:manifest'),
    select: invoke('toko:select')
  },
  order: {
    list: invoke('order:list'),
    transition: invoke('order:transition'),
    konfirmasiBayar: invoke('order:konfirmasiBayar'),
    simpanNota: invoke('order:simpanNota'),
    lunasi: invoke('order:lunasi')
  },
  table: {
    list: invoke('table:list')
  },
  bill: {
    peta: invoke('bill:peta'),
    buka: invoke('bill:buka'),
    detail: invoke('bill:detail'),
    tambahRonde: invoke('bill:tambahRonde'),
    setPax: invoke('bill:setPax'),
    cetak: invoke('bill:cetak'),
    bayar: invoke('bill:bayar'),
    gabung: invoke('bill:gabung'),
    batal: invoke('bill:batal')
  },
  qr: {
    make: invoke('qr:make')
  },
  tunnel: {
    start: invoke('tunnel:start'),
    stop: invoke('tunnel:stop')
  },
  station: {
    list: invoke('station:list'),
    create: invoke('station:create'),
    update: invoke('station:update'),
    remove: invoke('station:delete')
  },
  produk: {
    list: invoke('produk:list'),
    byBarcode: invoke('produk:barcode'),
    detail: invoke('produk:detail'),
    create: invoke('produk:create'),
    update: invoke('produk:update'),
    remove: invoke('produk:remove')
  },
  master: {
    kategori: invoke('master:kategori'),
    gudang: invoke('master:gudang'),
    satuan: invoke('master:satuan')
  },
  pelanggan: {
    list: invoke('pelanggan:list'),
    create: invoke('pelanggan:create'),
    quick: invoke('pelanggan:quick'),
    detail: invoke('pelanggan:detail')
  },
  inventory: {
    stokMasuk: invoke('inventory:stokMasuk'),
    opname: invoke('inventory:opname'),
    riwayat: invoke('inventory:riwayat')
  },
  pengeluaran: {
    list: invoke('pengeluaran:list'),
    create: invoke('pengeluaran:create'),
    remove: invoke('pengeluaran:remove')
  },
  sesi: {
    aktif: invoke('sesi:aktif'),
    list: invoke('sesi:list'),
    buka: invoke('sesi:buka'),
    tutup: invoke('sesi:tutup'),
    rekap: invoke('sesi:rekap')
  },
  trx: {
    checkout: invoke('trx:checkout'),
    list: invoke('trx:list'),
    detail: invoke('trx:detail'),
    batal: invoke('trx:batal')
  },
  laporan: {
    penjualanHarian: invoke('laporan:penjualanHarian'),
    penjualanProduk: invoke('laporan:penjualanProduk'),
    stok: invoke('laporan:stok'),
    rekapKasir: invoke('laporan:rekapKasir'),
    keuangan: invoke('laporan:keuangan')
  }
})
