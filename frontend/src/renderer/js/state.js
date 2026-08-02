// Store global sederhana (immutable patch + pub/sub).
// Token TIDAK pernah ada di sini — token hidup di main process.

const state = {
  user: null,          // { id, name, email, is_admin }
  posRole: null,       // 'OWNER' | 'MANAGER' | 'KASIR' — dari data.pos_role login/me (kontrak peran)
  company: null,       // { nama, alamat, telepon, npwp, logo }
  branch: null,
  permissions: [],
  paymentMethods: [],  // ['TUNAI','TRANSFER','QRIS']
  modules: {},
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
    posRole: null,
    company: null,
    branch: null,
    permissions: [],
    paymentMethods: [],
    modules: {},
    config: null,
    tokoList: [],
    toko: null,
    manifest: null,
    session: null,
    sessionId: null,
    langganan: null,
    gudang: [],
    gudangError: null,
    kategori: [],
    demo: false
  })
}
