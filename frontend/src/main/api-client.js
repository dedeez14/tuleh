'use strict'

const { net } = require('electron')

const API_PREFIX = '/api/pos/v1'
const TIMEOUT_MS = 15000
const MAX_BODY_BYTES = 5 * 1024 * 1024

let baseUrl = 'https://tatreport.com'
let gatewayUrl = null // bila di-set, transport lewat gateway lokal (mpos-backend)
let token = null
let activeTokoId = null // "toko aktif" utk disambiguasi multi-toko (MOVERA §1.3)

function setBaseUrl(url) {
  baseUrl = url
}

/** Alirkan permintaan lewat gateway lokal (null = koneksi langsung). */
function setGateway(url) {
  gatewayUrl = url || null
}

function setToken(value) {
  token = typeof value === 'string' && value.length > 0 ? value : null
}

function hasToken() {
  return token !== null
}

/** Set/hapus "toko aktif" — otomatis disisipkan sebagai ?toko_id pada tiap
 *  permintaan terautentikasi (MOVERA §1.3: cara paling pasti, tanpa rebuild). */
function setActiveTokoId(id) {
  activeTokoId = typeof id === 'string' && id.length > 0 ? id : null
}

function getActiveTokoId() {
  return activeTokoId
}

function statusMessage(status) {
  const messages = {
    0: 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
    401: 'Sesi Anda telah berakhir. Silakan masuk kembali.',
    403: 'Anda tidak memiliki akses untuk aksi ini.',
    404: 'Data tidak ditemukan.',
    409: 'Aksi bentrok dengan kondisi saat ini.',
    422: 'Data yang dikirim tidak valid.',
    429: 'Terlalu banyak permintaan. Coba lagi sebentar.',
    500: 'Terjadi kesalahan pada server.'
  }
  return messages[status] || `Terjadi kesalahan (HTTP ${status}).`
}

function buildUrl(endpoint, query) {
  const url = new URL((gatewayUrl || baseUrl) + API_PREFIX + endpoint)
  if (query && typeof query === 'object') {
    for (const [key, value] of Object.entries(query)) {
      if (value === undefined || value === null || value === '') continue
      url.searchParams.set(key, String(value))
    }
  }
  return url.toString()
}

async function readJsonSafe(response) {
  const text = await response.text()
  if (text.length > MAX_BODY_BYTES) return null
  try {
    return text ? JSON.parse(text) : null
  } catch {
    return null
  }
}

/**
 * Semua respons dinormalisasi ke:
 *   sukses → { ok: true,  status, data, meta, message }
 *   gagal  → { ok: false, status, message, errors }
 */
async function request(method, endpoint, { query, body, auth = true } = {}) {
  // Sisipkan toko aktif untuk permintaan terautentikasi (MOVERA §1.3),
  // kecuali pemanggil sudah menentukan toko_id sendiri.
  if (auth && activeTokoId && !(query && Object.prototype.hasOwnProperty.call(query, 'toko_id'))) {
    query = { ...(query || {}), toko_id: activeTokoId }
  }
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS)

  const headers = { Accept: 'application/json' }
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  if (auth && token) headers.Authorization = `Bearer ${token}`

  let response
  try {
    response = await net.fetch(buildUrl(endpoint, query), {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: controller.signal
    })
  } catch (err) {
    const timedOut = err && err.name === 'AbortError'
    return {
      ok: false,
      status: 0,
      message: timedOut ? 'Server tidak merespons (timeout).' : statusMessage(0),
      errors: null
    }
  } finally {
    clearTimeout(timer)
  }

  const payload = await readJsonSafe(response)

  if (!response.ok || !payload || payload.success === false) {
    return {
      ok: false,
      status: response.status,
      message: (payload && payload.message) || statusMessage(response.status),
      errors: (payload && payload.errors) || null
    }
  }

  return {
    ok: true,
    status: response.status,
    data: payload.data !== undefined ? payload.data : null,
    meta: payload.meta !== undefined ? payload.meta : null,
    message: payload.message || ''
  }
}

const get = (endpoint, options) => request('GET', endpoint, options)
const post = (endpoint, options) => request('POST', endpoint, options)

/**
 * Unggah file multipart (field selalu `logo`). `file` = { bytes, filename, mime }.
 * Content-Type TIDAK di-set manual — fetch mengisi boundary multipart otomatis.
 */
async function upload(endpoint, { query, file, auth = true } = {}) {
  if (auth && activeTokoId && !(query && Object.prototype.hasOwnProperty.call(query, 'toko_id'))) {
    query = { ...(query || {}), toko_id: activeTokoId }
  }
  if (!file || !file.bytes) return { ok: false, status: 0, message: 'File tidak ada.', errors: null }
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS * 2) // unggah bisa lebih lama

  const bytes = file.bytes instanceof ArrayBuffer ? new Uint8Array(file.bytes) : file.bytes
  const form = new FormData()
  form.append(file.field || 'logo', new Blob([bytes], { type: file.mime || 'application/octet-stream' }), file.filename || 'upload.png')

  const headers = { Accept: 'application/json' }
  if (auth && token) headers.Authorization = `Bearer ${token}`

  let response
  try {
    response = await net.fetch(buildUrl(endpoint, query), {
      method: 'POST', headers, body: form, signal: controller.signal
    })
  } catch (err) {
    const timedOut = err && err.name === 'AbortError'
    return { ok: false, status: 0, message: timedOut ? 'Server tidak merespons (timeout).' : statusMessage(0), errors: null }
  } finally {
    clearTimeout(timer)
  }

  const payload = await readJsonSafe(response)
  if (!response.ok || !payload || payload.success === false) {
    return {
      ok: false,
      status: response.status,
      message: (payload && payload.message) || statusMessage(response.status),
      errors: (payload && payload.errors) || null
    }
  }
  return {
    ok: true,
    status: response.status,
    data: payload.data !== undefined ? payload.data : null,
    meta: payload.meta !== undefined ? payload.meta : null,
    message: payload.message || ''
  }
}

module.exports = { request, get, post, upload, setBaseUrl, setGateway, setToken, hasToken, setActiveTokoId, getActiveTokoId }
