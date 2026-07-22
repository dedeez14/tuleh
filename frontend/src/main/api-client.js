'use strict'

const { net } = require('electron')

const API_PREFIX = '/api/pos/v1'
const TIMEOUT_MS = 15000
const MAX_BODY_BYTES = 5 * 1024 * 1024

let baseUrl = 'https://tatreport.com'
let gatewayUrl = null // bila di-set, transport lewat gateway lokal (mpos-backend)
let token = null

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

module.exports = { request, get, post, setBaseUrl, setGateway, setToken, hasToken }
