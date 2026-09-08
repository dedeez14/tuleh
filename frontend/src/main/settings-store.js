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

// ---- Catatan masa coba Mode Demo ({mulai, serverTerakhir, tanda}) ----
// Disimpan di TIGA tempat agar bertahan saat aplikasi dihapus/dipasang ulang
// (settings.json ikut terhapus bila pengguna membersihkan folder data):
//  1. settings.json (userData)
//  2. %ProgramData%\Tuleh\masa-coba.json
//  3. Registry HKCU\Software\Tuleh, nilai MasaCoba (JSON)
// Pembaca mengambil semua salinan; pemilih (lib/masa-coba pilihCatatan) memakai
// yang sah dengan `mulai` paling awal, lalu semua salinan ditulis ulang.

const { execFileSync } = require('node:child_process')
const REG_KEY = 'HKCU\\Software\\Tuleh'

function programDataPath() {
  const base = process.env.ProgramData || process.env.ALLUSERSPROFILE || ''
  return base ? path.join(base, 'Tuleh', 'masa-coba.json') : ''
}

function bacaProgramData() {
  const p = programDataPath()
  if (!p) return null
  try { return JSON.parse(fs.readFileSync(p, 'utf8')) } catch { return null }
}

function tulisProgramData(catatan) {
  const p = programDataPath()
  if (!p) return
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true })
    fs.writeFileSync(p, JSON.stringify(catatan), 'utf8')
  } catch { /* tanpa hak tulis — salinan lain tetap ada */ }
}

function bacaRegistry() {
  if (process.platform !== 'win32') return null
  try {
    const out = execFileSync('reg', ['query', REG_KEY, '/v', 'MasaCoba'], { encoding: 'utf8', windowsHide: true, timeout: 3000 })
    const m = out.match(/MasaCoba\s+REG_SZ\s+(.+)$/m)
    return m ? JSON.parse(m[1].trim()) : null
  } catch { return null }
}

function tulisRegistry(catatan) {
  if (process.platform !== 'win32') return
  try {
    execFileSync('reg', ['add', REG_KEY, '/v', 'MasaCoba', '/t', 'REG_SZ', '/d', JSON.stringify(catatan), '/f'], { windowsHide: true, timeout: 3000 })
  } catch { /* abaikan */ }
}

/** Semua salinan catatan (bisa berisi null / rusak; pemilih yang menyaring). */
function getDemoTrialSemua() {
  const d = readRaw().demo
  return [d && typeof d === 'object' ? d : null, bacaProgramData(), bacaRegistry()].filter(Boolean)
}

/** Salinan di settings.json saja (kompatibilitas). */
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
  if (catatan) {
    tulisProgramData(catatan)
    tulisRegistry(catatan)
  }
}

/** Token identitas (hasil OTP) untuk /demo/perangkat; disimpan bersama catatan. */
function getDemoIdentitasToken() {
  const t = readRaw().demoIdentitasToken
  return typeof t === 'string' && t ? t : null
}

function setDemoIdentitasToken(token) {
  const next = { ...readRaw(), baseUrl: load().baseUrl }
  if (token) next.demoIdentitasToken = token
  else delete next.demoIdentitasToken
  save(next)
}

function save(settings) {
  fs.mkdirSync(app.getPath('userData'), { recursive: true })
  fs.writeFileSync(settingsPath(), JSON.stringify(settings, null, 2), 'utf8')
}

// ---- Preferensi cetak struk ----
// { printer: nama perangkat | '' (dialog OS), langsung: bool, otomatis: bool }
function getCetak() {
  const raw = readRaw().cetak
  const c = raw && typeof raw === 'object' ? raw : {}
  return {
    printer: typeof c.printer === 'string' ? c.printer.slice(0, 200) : '',
    langsung: !!c.langsung,
    otomatis: !!c.otomatis
  }
}

function setCetak(patch = {}) {
  const raw = readRaw()
  const lama = getCetak()
  const baru = {
    printer: 'printer' in patch ? String(patch.printer || '').slice(0, 200) : lama.printer,
    langsung: 'langsung' in patch ? !!patch.langsung : lama.langsung,
    otomatis: 'otomatis' in patch ? !!patch.otomatis : lama.otomatis
  }
  save({ ...raw, cetak: baru })
  return baru
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

module.exports = { load, setBaseUrl, getCetak, setCetak, getDemoTrial, getDemoTrialSemua, setDemoTrial, getDemoIdentitasToken, setDemoIdentitasToken, DEFAULT_BASE_URL, isAllowedBaseUrl }
