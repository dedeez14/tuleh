// Manajemen tema aplikasi (light / dark / system).
// Sumber kebenaran: localStorage 'mpos.theme'. applyTheme() menstempel
// atribut data-theme di <html>; mode 'system' menghapus atribut agar
// media-query prefers-color-scheme yang menentukan.

const STORAGE_KEY = 'mpos.theme'
const VALID = ['light', 'dark', 'system']
const MEDIA = '(prefers-color-scheme: dark)'

/** Mode tema tersimpan ('light' | 'dark' | 'system'), default 'system'. */
export function getTheme() {
  try {
    const value = localStorage.getItem(STORAGE_KEY)
    return VALID.includes(value) ? value : 'system'
  } catch {
    return 'system'
  }
}

/** Apakah sistem operasi meminta tampilan gelap. */
function prefersDark() {
  return typeof matchMedia === 'function' && matchMedia(MEDIA).matches
}

/** Tema efektif yang sedang tampil ('light' | 'dark'), meresolusi 'system'. */
export function getEffectiveTheme() {
  const mode = getTheme()
  if (mode === 'light' || mode === 'dark') return mode
  return prefersDark() ? 'dark' : 'light'
}

/** Simpan mode tema lalu terapkan segera. */
export function setTheme(mode) {
  const next = VALID.includes(mode) ? mode : 'system'
  try {
    localStorage.setItem(STORAGE_KEY, next)
  } catch {
    /* penyimpanan tak tersedia — tetap terapkan untuk sesi ini */
  }
  applyTheme()
  return next
}

/** Terapkan tema ke documentElement sesuai mode tersimpan. */
export function applyTheme() {
  const mode = getTheme()
  const root = document.documentElement
  if (mode === 'system') root.removeAttribute('data-theme')
  else root.setAttribute('data-theme', mode)
}

/** Toggle light ↔ dark berdasarkan tema yang sedang efektif. */
export function cycleTheme() {
  const next = getEffectiveTheme() === 'dark' ? 'light' : 'dark'
  return setTheme(next)
}

// Ikuti perubahan preferensi sistem selama mode masih 'system'.
if (typeof matchMedia === 'function') {
  const mq = matchMedia(MEDIA)
  const onChange = () => {
    if (getTheme() === 'system') applyTheme()
  }
  if (typeof mq.addEventListener === 'function') mq.addEventListener('change', onChange)
  else if (typeof mq.addListener === 'function') mq.addListener(onChange)
}

// Terapkan sekali saat modul dimuat (boot) agar tema aktif sedini mungkin.
applyTheme()
