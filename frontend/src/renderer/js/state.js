// Store global sederhana (immutable patch + pub/sub).
// Token TIDAK pernah ada di sini — token hidup di main process.

const state = {
  user: null,          // { id, name, email, is_admin }
  akses: null,         // string[] kunci hak akses dari server (login/me) — baca lewat akses.js
  peran: null,         // { nama } peran pengguna dari server (hanya tampilan)
  company: null,       // { nama, alamat, telepon, npwp, logo }
  branch: null,
  permissions: [],
  paymentMethods: [],  // ['TUNAI','TRANSFER','QRIS']
  modules: {},
  struk: null,         // { logo, footer, tampil_logo } — dari /config (kop & kaki struk)
  pembayaran: null,    // { qr_statis, bank[], midtrans_aktif } — dari /config (layar bayar)
  config: null,        // hasil /config
  tokoList: [],        // daftar toko company (GET /tokos)
  toko: null,          // toko terpilih {id, nama, bidang_usaha}
  manifest: null,      // manifest ternormalisasi toko terpilih (null = default)
  session: null,       // SesiRekap aktif atau null
  sessionId: null,     // id sesi aktif (dari /sesi/aktif — bila API sertakan id)
  langganan: null,     // status langganan tenant {status, sisa_hari, ...} (Sistem Mitra §6.5)
  stokAlerts: [],      // produk stok menipis/habis [{id,produk,stok,min,status}] utk lonceng
  gudang: [],          // [{id, kode, nama}]
  gudangError: null,   // pesan error bila GET /gudang gagal (mis. 500 — known issue server)
  kategori: [],
  online: true,
  demo: false,
  demoSisaHari: null, // sisa hari masa coba Mode Demo (null = bukan demo)
  screen: 'pos'
}

const listeners = new Set()

export function getState() {
  return state
}

export function setState(patch) {
  Object.assign(state, patch)
  for (const listener of listeners) {
    try {
      listener(state, patch)
    } catch (err) {
      console.error('Listener state gagal:', err)
    }
  }
}

export function subscribe(listener) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function resetAuthState() {
  setState({
    user: null,
    akses: null,
    peran: null,
    company: null,
    branch: null,
    permissions: [],
    paymentMethods: [],
    modules: {},
    struk: null,
    pembayaran: null,
    config: null,
    tokoList: [],
    toko: null,
    manifest: null,
    session: null,
    sessionId: null,
    langganan: null,
    stokAlerts: [],
    gudang: [],
    gudangError: null,
    kategori: [],
    demo: false
  })
}
