'use strict'

// Pembuat QR code sebagai data-URI SVG (untuk struk & halaman lacak).

const qrcode = require('./lib/qrcode-generator')

/** Buat data URI SVG dari teks (URL pelacakan dsb.). */
function svgDataUri(text) {
  const qr = qrcode(0, 'M') // typeNumber 0 = pilih otomatis
  qr.addData(String(text), 'Byte')
  qr.make()
  const svg = qr.createSvgTag({ cellSize: 4, margin: 8 })
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)
}

/** Tag SVG mentah (dipakai halaman HTML pelacakan). */
function svgTag(text, cellSize = 4) {
  const qr = qrcode(0, 'M')
  qr.addData(String(text), 'Byte')
  qr.make()
  return qr.createSvgTag({ cellSize, margin: 6 })
}

module.exports = { svgDataUri, svgTag }
