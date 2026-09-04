'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { app } = require('electron')

const DEFAULT_BASE_URL = 'https://tatreport.com'

function settingsPath() {
  return path.join(app.getPath('userData'), 'settings.json')
}

function isAllowedBaseUrl(value) {
  let url
  try {
    url = new URL(value)
  } catch {
    return false
  }
  if (url.protocol === 'https:') return true
  // HTTP hanya untuk pengembangan lokal (mis. backend Go di mesin sendiri)
  const isLocalhost = url.hostname === 'localhost' || url.hostname === '127.0.0.1'
  return url.protocol === 'http:' && isLocalhost
}

function normalizeBaseUrl(value) {
  const url = new URL(value)
  return `${url.protocol}//${url.host}`
}

// Port yang dipakai gateway lokal mpos-backend (lihat main/gateway.js)
const GATEWAY_PORTS = new Set(['8787', '8788', '8789', '8790'])

// Migrasi konfigurasi lama: dulu pengguna diarahkan menunjuk gateway secara
// manual (http://localhost:8787). Kini gateway dinyalakan otomatis oleh
// aplikasi, jadi baseUrl harus kembali ke domain tenant — bukan ke gateway.
function migrateLegacyGatewayUrl(baseUrl) {
  try {
    const url = new URL(baseUrl)
    const isLocal = url.hostname === 'localhost' || url.hostname === '127.0.0.1'
    if (isLocal && GATEWAY_PORTS.has(url.port)) return DEFAULT_BASE_URL
  } catch {
    // biarkan — validasi dilakukan pemanggil
  }
  return baseUrl
}

function readRaw() {
  try {
    const parsed = JSON.parse(fs.readFileSync(settingsPath(), 'utf8'))
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {} // File belum ada atau korup
  }
}

function load() {
  const parsed = readRaw()
  if (typeof parsed.baseUrl === 'string' && isAllowedBaseUrl(parsed.baseUrl)) {
    const migrated = migrateLegacyGatewayUrl(normalizeBaseUrl(parsed.baseUrl))
    if (migrated !== parsed.baseUrl) save({ ...parsed, baseUrl: migrated })
    return { baseUrl: migrated }
  }
  return { baseUrl: DEFAULT_BASE_URL }
}

/** Catatan masa coba Mode Demo ({mulai, serverTerakhir, tanda}) atau null. */
function getDemoTrial() {
  const d = readRaw().demo
  return d && typeof d === 'object' ? d : null
}

function setDemoTrial(catatan) {
  const cur = readRaw()
  const next = { ...cur, baseUrl: load().baseUrl }
  if (catatan) next.demo = catatan
  else delete next.demo
  save(next)
}

function save(settings) {
  fs.mkdirSync(app.getPath('userData'), { recursive: true })
  fs.writeFileSync(settingsPath(), JSON.stringify(settings, null, 2), 'utf8')
}

function setBaseUrl(value) {
  if (typeof value !== 'string' || !isAllowedBaseUrl(value)) {
    return { ok: false, message: 'URL server harus HTTPS (atau http://localhost untuk pengembangan).' }
  }
  // Pertahankan kunci lain (mis. catatan masa coba demo) saat mengganti server.
  const next = { ...readRaw(), baseUrl: normalizeBaseUrl(value) }
  save(next)
  return { ok: true, baseUrl: next.baseUrl }
}

module.exports = { load, setBaseUrl, getDemoTrial, setDemoTrial, DEFAULT_BASE_URL, isAllowedBaseUrl }
