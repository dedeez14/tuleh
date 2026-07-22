'use strict'

// Server pelacakan pesanan untuk PELANGGAN (Blueprint Fase 3 — mode lokal/LAN).
// Menyajikan halaman status ber-token di jaringan lokal: pelanggan memindai QR
// pada struk dari HP-nya (WiFi yang sama) tanpa aplikasi tambahan.
//
// Keamanan: read-only; token acak 128-bit; hanya menampilkan data pesanan itu;
// tidak ada API tulis; dimatikan bersama aplikasi.

const http = require('node:http')
const os = require('node:os')

const PORT = Number(process.env.MPOS_TRACK_PORT || 8791)
const REFRESH_SECONDS = 5

let server = null
let publicUrl = null // URL internet publik (tunnel) — bila aktif, diutamakan
let hooks = {
  tracking: null,    // (token) => { order, states, labels, tokoNama } | null
  menu: null,        // (kodeMeja) => { tokoNama, mejaNomor, products } | null
  createOrder: null, // (kodeMeja, {nama, catatan, items}) => { ok, order?, message? }
  queueBoard: null   // () => { tokoNama, states, labels, rows } | null
}

// Throttle sederhana POST pemesanan per IP (anti-spam)
const postHits = new Map()
const POST_LIMIT = 5
const POST_WINDOW_MS = 60000

function allowPost(ip) {
  const now = Date.now()
  const rec = postHits.get(ip)
  if (!rec || now - rec.ts > POST_WINDOW_MS) {
    postHits.set(ip, { count: 1, ts: now })
    return true
  }
  rec.count += 1
  return rec.count <= POST_LIMIT
}

function lanAddress() {
  const nets = os.networkInterfaces()
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === 'IPv4' && !net.internal) return net.address
    }
  }
  return '127.0.0.1'
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
}

function pageShell(title, body) {
  return `<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta http-equiv="refresh" content="${REFRESH_SECONDS}" />
<title>${escapeHtml(title)}</title>
<style>
  * { box-sizing: border-box; margin: 0; }
  body { font-family: system-ui, -apple-system, 'Segoe UI', sans-serif; background: #f2faf7;
         color: #14332c; padding: 20px 16px 40px; }
  .wrap { max-width: 430px; margin: 0 auto; }
  .head { text-align: center; margin-bottom: 18px; }
  .head h1 { font-size: 15px; color: #526e66; font-weight: 600; }
  .head .toko { font-size: 20px; font-weight: 800; margin-top: 2px; }
  .card { background: #fff; border: 1px solid #cde2da; border-radius: 3px; padding: 18px; }
  .antrian { text-align: center; padding: 14px; background: #dff7f1; border: 1px solid #bff0e5;
             border-radius: 3px; margin-bottom: 16px; }
  .antrian .lbl { font-size: 11px; font-weight: 700; letter-spacing: .08em; color: #17695d;
                  text-transform: uppercase; }
  .antrian .no { font-size: 42px; font-weight: 800; font-family: ui-monospace, Consolas, monospace; }
  .timeline { list-style: none; }
  .timeline li { display: flex; align-items: flex-start; gap: 12px; padding: 9px 0;
                 border-bottom: 1px solid #e3efea; font-size: 15px; }
  .timeline li:last-child { border-bottom: none; }
  .dot { width: 18px; height: 18px; border-radius: 50%; border: 2px solid #cde2da;
         background: #fff; flex-shrink: 0; margin-top: 1px; }
  .done .dot { background: #2fae99; border-color: #2fae99; }
  .now .dot { border-color: #2fae99; box-shadow: 0 0 0 4px rgba(122,226,207,.35); }
  .done { color: #526e66; }
  .now { font-weight: 800; }
  .next { color: #64796f; }
  .status-now { text-align: center; margin: 14px 0 4px; font-size: 17px; font-weight: 800;
                color: #17695d; }
  .meta { margin-top: 14px; font-size: 13px; color: #526e66; }
  .meta div { display: flex; justify-content: space-between; padding: 4px 0; }
  .foot { text-align: center; margin-top: 16px; font-size: 12px; color: #64796f; }
  .err { text-align: center; padding: 40px 16px; }
  .err h2 { font-size: 18px; margin-bottom: 8px; }
</style>
</head>
<body><div class="wrap">${body}</div></body>
</html>`
}

function renderTracking(info) {
  const { order, states, labels, tokoNama } = info
  const currentIdx = states.indexOf(order.stage)

  const timeline = states.map((stage, idx) => {
    const cls = idx < currentIdx ? 'done' : idx === currentIdx ? 'now' : 'next'
    return `<li class="${cls}"><span class="dot"></span><span>${escapeHtml(labels[stage] || stage)}</span></li>`
  }).join('')

  const items = (order.items || [])
    .map((i) => `<div><span>${escapeHtml(i.nama)}</span><span>×${escapeHtml(i.kuantitas)}</span></div>`)
    .join('')

  const body = `
    <div class="head">
      <h1>Status Pesanan</h1>
      <div class="toko">${escapeHtml(tokoNama || 'Tuléh')}</div>
    </div>
    <div class="card">
      ${order.no_antrian ? `
        <div class="antrian">
          <div class="lbl">Nomor Antrian</div>
          <div class="no">${escapeHtml(order.no_antrian)}</div>
        </div>` : ''}
      <div class="status-now">${escapeHtml(labels[order.stage] || order.stage)}</div>
      ${order.bayar === 'BON' ? `
        <div style="text-align:center;font-size:13px;color:#0e7490;background:#e0f4f9;
                    border:1px solid #b8e3ee;border-radius:3px;padding:6px;margin:8px 0">
          Pesanan masuk bon meja — bayar di kasir saat selesai
        </div>` : order.bayar === 'BELUM' && order.stage !== 'MENUNGGU_BAYAR' ? `
        <div style="text-align:center;font-size:13px;color:#b45309;background:#fdf1df;
                    border:1px solid #f0d9ac;border-radius:3px;padding:6px;margin:8px 0">
          Pembayaran dilakukan saat pengambilan
        </div>` : ''}
      <ul class="timeline">${timeline}</ul>
      <div class="meta">
        <div style="font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:#17695d">Rincian Pesanan</div>
        ${items}
        <div style="border-top:1px solid #e3efea;padding-top:6px"><span>Nomor pesanan</span><span>${escapeHtml(order.nomor)}</span></div>
      </div>
    </div>
    <div class="foot">Halaman diperbarui otomatis tiap ${REFRESH_SECONDS} detik · Tuléh</div>`

  return pageShell(`Pesanan ${order.no_antrian || order.nomor}`, body)
}

// ---------- Halaman menu & pemesanan dari meja (QR meja) ----------

function renderMenu(kode, info, errorMsg, prefill = {}) {
  // Kelompokkan produk per kategori (urutan asli dalam tiap kelompok dipertahankan)
  const grup = new Map()
  for (const p of info.products) {
    const kat = p.kategori || 'Lainnya'
    if (!grup.has(kat)) grup.set(kat, [])
    grup.get(kat).push(p)
  }
  const rows = [...grup.entries()].map(([kat, produk]) => `
    <div class="mgroup">${escapeHtml(kat)}</div>
    ${produk.map((p) => `
    <div class="mrow">
      <div class="mrow__info">
        <div class="mrow__nama">${escapeHtml(p.nama)}</div>
        <div class="mrow__harga">Rp ${Number(p.harga).toLocaleString('id-ID')}</div>
      </div>
      <input class="mrow__qty" type="number" name="q_${escapeHtml(p.id)}" min="0" max="20"
             value="${escapeHtml(prefill[`q_${p.id}`] || 0)}" inputmode="numeric" />
    </div>`).join('')}`).join('')

  const isiUtama = info.products.length === 0
    ? `<div class="card" style="text-align:center;padding:28px 16px">
      Menu belum tersedia. Silakan pesan langsung di kasir.
    </div>`
    : `<form class="card" method="POST" action="/o/${escapeHtml(kode)}">
      <div style="margin-bottom:12px">
        <label style="font-size:13px;font-weight:700;color:#526e66">Nama Anda</label>
        <input name="nama" required maxlength="60" placeholder="mis. Budi" value="${escapeHtml(prefill.nama || '')}"
               style="width:100%;padding:10px;border:1px solid #cde2da;border-radius:3px;margin-top:4px;font-size:16px" />
      </div>
      <div class="mlist">${rows}</div>
      <div style="margin:12px 0">
        <label style="font-size:13px;font-weight:700;color:#526e66">Catatan (opsional)</label>
        <input name="catatan" maxlength="300" placeholder="mis. tanpa seledri" value="${escapeHtml(prefill.catatan || '')}"
               style="width:100%;padding:10px;border:1px solid #cde2da;border-radius:3px;margin-top:4px;font-size:16px" />
      </div>
      <button type="submit"
              style="width:100%;padding:14px;background:#7ae2cf;border:none;border-radius:3px;font-size:16px;font-weight:800;color:#08332c;position:sticky;bottom:10px">
        Kirim Pesanan
      </button>
      <div class="foot" style="margin-top:10px">Pembayaran dilakukan di kasir. Setelah dikirim,
        Anda mendapat tautan untuk memantau status pesanan.</div>
    </form>`

  const body = `
    <div class="head">
      <h1>Pesan dari Meja ${escapeHtml(info.mejaNomor)}</h1>
      <div class="toko">${escapeHtml(info.tokoNama)}</div>
    </div>
    ${errorMsg ? `<div class="card" style="border-color:#d93a49;color:#b02a37;margin-bottom:12px;padding:12px">${escapeHtml(errorMsg)}</div>` : ''}
    ${isiUtama}
    <style>
      .mlist { border-top: 1px solid #e3efea; }
      .mgroup { font-size: 12px; font-weight: 800; letter-spacing: .06em; text-transform: uppercase;
                color: #17695d; padding: 14px 0 4px; border-bottom: 1px solid #e3efea; }
      .mrow { display: flex; align-items: center; justify-content: space-between; gap: 10px;
              padding: 12px 0; border-bottom: 1px solid #e3efea; }
      .mrow__nama { font-weight: 600; font-size: 15px; }
      .mrow__harga { font-size: 13px; color: #526e66; }
      .mrow__qty { width: 76px; min-height: 48px; padding: 12px 8px; border: 1px solid #cde2da;
                   border-radius: 3px; font-size: 18px; text-align: center; }
    </style>`

  // Halaman menu tidak boleh auto-refresh (form akan tereset) → tanpa meta refresh
  return pageShell(`Menu — ${info.tokoNama}`, body).replace(/<meta http-equiv="refresh"[^>]*>/, '')
}

function renderOrderPlaced(result) {
  const lacak = `/t/${result.order.token_lacak}`
  const body = `
    <div class="head">
      <h1>Pesanan Terkirim</h1>
      <div class="toko">${escapeHtml(result.tokoNama)}</div>
    </div>
    <div class="card" style="text-align:center">
      <p style="font-size:15px;line-height:1.6">Silakan lakukan <b>pembayaran di kasir</b>.
      Setelah dibayar, pesanan Anda masuk antrian dapur dan mendapat nomor antrian.</p>
      <p style="margin-top:14px"><a href="${lacak}"
        style="display:inline-block;padding:12px 22px;background:#7ae2cf;color:#08332c;border-radius:3px;text-decoration:none;font-weight:800">
        Pantau Status Pesanan</a></p>
      <p class="foot" style="margin-top:10px">Anda akan dialihkan otomatis ke halaman status pesanan…</p>
    </div>`
  return pageShell('Pesanan terkirim', body)
    .replace('content="5"', `content="3;url=${lacak}"`)
}

function readBody(req, limit = 10240) {
  return new Promise((resolve, reject) => {
    let data = ''
    req.on('data', (chunk) => {
      data += chunk
      if (data.length > limit) {
        reject(new Error('body terlalu besar'))
        req.destroy()
      }
    })
    req.on('end', () => resolve(data))
    req.on('error', reject)
  })
}

async function handleRequest(req, res) {
  const url = new URL(req.url, 'http://localhost')
  // Di belakang tunnel, IP asli pengunjung ada di header CF-Connecting-IP
  const ip = req.headers['cf-connecting-ip'] || req.socket.remoteAddress || '?'

  res.setHeader('Content-Type', 'text/html; charset=utf-8')
  res.setHeader('Cache-Control', 'no-store')
  res.setHeader('X-Content-Type-Options', 'nosniff')

  const notFound = (judul, pesan) => {
    res.writeHead(404)
    res.end(pageShell('Tidak ditemukan', `
      <div class="card err"><h2>${escapeHtml(judul)}</h2><p>${escapeHtml(pesan)}</p></div>`))
  }

  // Papan antrian publik (buka di TV/browser mana pun di LAN)
  if (url.pathname === '/antrian' && req.method === 'GET') {
    const info = typeof hooks.queueBoard === 'function' ? hooks.queueBoard() : null
    if (!info) return notFound('Papan antrian tidak aktif', 'Toko yang sedang aktif tidak memakai antrian.')
    const kolom = info.states.map((stage, idx) => {
      const isi = info.rows.filter((r) => r.stage === stage)
      // Kolom terakhir (tahap 'Siap') disorot agar terlihat dari kejauhan
      const kelas = idx === info.states.length - 1 ? 'qcol qcol--siap' : 'qcol'
      return `
        <section class="${kelas}">
          <h2>${escapeHtml(info.labels[stage] || stage)}</h2>
          <div class="qnums">
            ${isi.length
              ? isi.map((r) => `<span class="qno${r.meja ? ' qno--meja' : ''}">${escapeHtml(r.label || r.no_antrian)}</span>`).join('')
              : '<span class="qkosong">—</span>'}
          </div>
        </section>`
    }).join('')
    res.writeHead(200)
    res.end(pageShell(`Antrian — ${info.tokoNama}`, `
      <div class="head"><h1>Papan Antrian</h1><div class="toko">${escapeHtml(info.tokoNama)}</div></div>
      <div class="qgrid">${kolom}</div>
      <div class="foot">Diperbarui otomatis · Tuléh</div>
      <style>
        .wrap { max-width: none; padding: 0 2vw; }
        .head .toko { font-size: clamp(28px, 3.5vw, 56px); }
        .qgrid { display: grid; grid-template-columns: repeat(${info.states.length}, 1fr); gap: 14px; }
        .qcol { background: #fff; border: 1px solid #cde2da; border-radius: 3px; padding: 14px; }
        .qcol h2 { font-size: clamp(16px, 1.6vw, 24px); text-transform: uppercase; letter-spacing: .06em;
                   color: #526e66; border-bottom: 1px solid #e3efea; padding-bottom: 8px; }
        .qcol--siap { background: #dff7f1; border-color: #2fae99; border-width: 2px; }
        .qcol--siap h2 { color: #17695d; }
        .qnums { display: flex; flex-wrap: wrap; gap: 10px; padding-top: 12px; }
        .qno { font-family: ui-monospace, Consolas, monospace; font-size: clamp(34px, 4.5vw, 72px);
               font-weight: 800; background: #dff7f1; border: 1px solid #bff0e5; border-radius: 3px;
               padding: 6px 14px; }
        .qno--meja { background: #e0f4f9; border-color: #b8e3ee; font-family: inherit;
                     font-size: clamp(30px, 4vw, 64px); font-weight: 800; }
        .qkosong { color: #64796f; font-size: 24px; padding: 8px; }
        @media (max-width: 700px) { .qgrid { grid-template-columns: 1fr; } }
      </style>`))
    return
  }

  // Halaman lacak pesanan
  const trackMatch = url.pathname.match(/^\/t\/([A-Za-z0-9_-]{16,64})$/)
  if (trackMatch && req.method === 'GET') {
    const info = typeof hooks.tracking === 'function' ? hooks.tracking(trackMatch[1]) : null
    if (!info) return notFound('Pesanan tidak ditemukan', 'Tautan tidak valid atau pesanan sudah tidak aktif.')
    res.writeHead(200)
    res.end(renderTracking(info))
    return
  }

  // Halaman menu QR meja + kirim pesanan
  const mejaMatch = url.pathname.match(/^\/o\/([A-Za-z0-9_-]{4,40})$/)
  if (mejaMatch) {
    const kode = mejaMatch[1]
    const info = typeof hooks.menu === 'function' ? hooks.menu(kode) : null
    if (!info) return notFound('Meja tidak dikenal', 'QR meja tidak valid untuk toko yang sedang aktif.')

    if (req.method === 'GET') {
      res.writeHead(200)
      res.end(renderMenu(kode, info))
      return
    }

    if (req.method === 'POST') {
      if (!allowPost(ip)) {
        res.writeHead(429)
        res.end(pageShell('Terlalu cepat', '<div class="card err"><h2>Terlalu banyak percobaan</h2><p>Tunggu sebentar lalu coba lagi.</p></div>'))
        return
      }
      let params
      try {
        params = new URLSearchParams(await readBody(req))
      } catch {
        res.writeHead(400).end('Bad Request')
        return
      }
      const items = []
      for (const [key, value] of params.entries()) {
        if (key.startsWith('q_')) items.push({ idProduk: key.slice(2), qty: Number(value) })
      }
      const result = typeof hooks.createOrder === 'function'
        ? hooks.createOrder(kode, { nama: params.get('nama'), catatan: params.get('catatan'), items })
        : { ok: false, message: 'Pemesanan tidak tersedia.' }

      if (!result.ok) {
        res.writeHead(422)
        // Isian pelanggan dikembalikan sebagai prefill agar tidak hilang saat gagal
        res.end(renderMenu(kode, info, result.message, Object.fromEntries(params.entries())))
        return
      }
      res.writeHead(200)
      res.end(renderOrderPlaced(result))
      return
    }
  }

  if (req.method !== 'GET' && req.method !== 'POST') {
    res.writeHead(405).end('Method Not Allowed')
    return
  }
  notFound('Halaman tidak ditemukan', 'Alamat tidak dikenal.')
}

function start(lookup) {
  // Terima fungsi tunggal (lacak saja — kompatibel lama) atau objek hook lengkap
  hooks = typeof lookup === 'function'
    ? { tracking: lookup, menu: null, createOrder: null }
    : { ...hooks, ...lookup }
  if (server) return status()
  server = http.createServer(handleRequest)
  server.on('error', () => {
    server = null
  })
  server.listen(PORT, '0.0.0.0')
  return status()
}

function stop() {
  if (server) {
    try { server.close() } catch { /* abaikan */ }
    server = null
  }
}

function setPublicUrl(url) {
  publicUrl = url || null
}

function status() {
  return {
    running: !!server,
    port: PORT,
    baseUrl: server ? (publicUrl || `http://${lanAddress()}:${PORT}`) : null,
    lanUrl: server ? `http://${lanAddress()}:${PORT}` : null,
    publicUrl: server ? publicUrl : null
  }
}

module.exports = { start, stop, status, setPublicUrl }
