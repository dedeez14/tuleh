'use strict'

const fs = require('node:fs')
const path = require('node:path')
const { app, safeStorage } = require('electron')

// Token TIDAK pernah dikirim ke renderer. Disimpan terenkripsi (DPAPI di
// Windows) di userData, dan dipegang di memori main process saja.

function tokenPath() {
  return path.join(app.getPath('userData'), 'auth.enc')
}

function persist(token) {
  try {
    if (!safeStorage.isEncryptionAvailable()) return false
    fs.mkdirSync(app.getPath('userData'), { recursive: true })
    fs.writeFileSync(tokenPath(), safeStorage.encryptString(token))
    return true
  } catch {
    return false
  }
}

function restore() {
  try {
    if (!safeStorage.isEncryptionAvailable()) return null
    const encrypted = fs.readFileSync(tokenPath())
    const token = safeStorage.decryptString(encrypted)
    return token && token.length > 0 ? token : null
  } catch {
    return null
  }
}

function clear() {
  try {
    fs.rmSync(tokenPath(), { force: true })
  } catch {
    // Abaikan — file mungkin tidak ada
  }
}

module.exports = { persist, restore, clear }
