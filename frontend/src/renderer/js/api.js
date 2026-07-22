// Jembatan tipis ke main process (window.iposAPI dari preload).
// Semua metode mengembalikan envelope ternormalisasi:
//   { ok: true, data, meta } | { ok: false, status, message, errors }

const bridge = window.iposAPI

if (!bridge) {
  throw new Error('Bridge iposAPI tidak tersedia — preload gagal dimuat.')
}

export const api = bridge

/** Ambil pesan error pertama dari envelope gagal (termasuk error validasi 422). */
export function firstError(result) {
  if (!result || result.ok) return ''
  if (result.errors && typeof result.errors === 'object') {
    const firstKey = Object.keys(result.errors)[0]
    const messages = firstKey ? result.errors[firstKey] : null
    if (Array.isArray(messages) && messages.length > 0) return messages[0]
  }
  return result.message || 'Terjadi kesalahan.'
}
