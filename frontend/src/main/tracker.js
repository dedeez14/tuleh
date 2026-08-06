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
let customerState = null // state Display Pelanggan LIVE (di-relay dari window kasir)
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

// Halaman Display Pelanggan (LAN) — mandiri: poll /display/data lalu render
// keranjang/total/bayar; saat idle tampilkan video promosi bila diset. Tak pakai
// pageShell (tanpa meta-refresh) supaya update mulus tanpa reload penuh.
function displayPage() {
  return `<!DOCTYPE html>
<html lang="id"><head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Display Pelanggan — Tuléh</title>
<style>
  *{box-sizing:border-box;margin:0} html,body{height:100%}
  body{font-family:'Segoe UI',system-ui,-apple-system,sans-serif;overflow:hidden;color:#eafff9;
       background:radial-gradient(1200px 600px at 80% -10%,rgba(122,226,207,.16),transparent 60%),linear-gradient(160deg,#0a2723,#06201c 60%,#041613)}
  #cd{position:absolute;inset:0;display:flex;flex-direction:column;padding:clamp(20px,3vw,48px)}
  .brand{display:flex;align-items:center;gap:14px}
  .brand img{width:clamp(38px,3.4vw,56px);height:clamp(38px,3.4vw,56px);border-radius:10px;object-fit:contain;background:rgba(255,255,255,.06);padding:4px}
  .store{font-weight:800;font-size:clamp(20px,2vw,32px)}
  #cd.welcome{align-items:center;justify-content:center;text-align:center;gap:10px}
  #cd.welcome .brand{flex-direction:column;gap:18px;margin-bottom:10px}
  #cd.welcome img{width:clamp(80px,9vw,132px);height:clamp(80px,9vw,132px);border-radius:22px}
  .w-title{font-size:clamp(40px,6vw,92px);font-weight:800;letter-spacing:-.02em;line-height:1.05}
  .w-sub{font-size:clamp(18px,1.8vw,28px);color:rgba(234,255,249,.66)}
  .promo{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;background:#041613}
  .top{display:flex;align-items:center;justify-content:space-between;gap:16px;padding-bottom:18px;border-bottom:1px solid rgba(122,226,207,.18);flex-shrink:0}
  .count{font-size:clamp(15px,1.4vw,22px);color:rgba(234,255,249,.66);font-weight:600}
  .items{flex:1 1 auto;overflow-y:auto;padding:10px 0;display:flex;flex-direction:column;gap:2px}
  .row{display:grid;grid-template-columns:1fr auto auto;align-items:baseline;gap:10px 22px;padding:clamp(9px,1vw,15px) 4px;border-bottom:1px solid rgba(255,255,255,.06)}
  .r-name{font-size:clamp(19px,1.8vw,30px);font-weight:700}
  .r-meta{display:flex;gap:12px;color:rgba(234,255,249,.66);font-size:clamp(14px,1.2vw,20px);white-space:nowrap}
  .r-qty{color:#7ae2cf;font-weight:800}
  .r-sub{font-size:clamp(18px,1.6vw,28px);font-weight:700;text-align:right;white-space:nowrap}
  .foot{flex-shrink:0;padding-top:16px;border-top:1px solid rgba(122,226,207,.18)}
  .line{display:flex;justify-content:space-between;font-size:clamp(16px,1.4vw,24px);color:rgba(234,255,249,.66);padding:4px 0}
  .total{display:flex;align-items:baseline;justify-content:space-between;gap:16px;margin-top:6px}
  .total b{font-size:clamp(20px,2vw,34px);font-weight:700}
  .total .v{font-size:clamp(40px,5.4vw,92px);font-weight:800;letter-spacing:-.02em;color:#fff;line-height:1}
  .pay{margin-top:14px;padding-top:12px;border-top:1px dashed rgba(122,226,207,.28)}
  .pay .change{color:#7ae2cf;font-weight:800;font-size:clamp(18px,1.8vw,30px)}
  #cd.thanks{align-items:center;justify-content:center;text-align:center;gap:10px}
  .ic{width:clamp(90px,10vw,150px);height:clamp(90px,10vw,150px);display:flex;align-items:center;justify-content:center;border-radius:50%;background:rgba(122,226,207,.16);border:3px solid #7ae2cf;color:#7ae2cf;font-size:clamp(48px,6vw,88px);font-weight:800;margin-bottom:8px}
  .t-title{font-size:clamp(40px,6vw,84px);font-weight:800}
  .t-grid{display:flex;gap:clamp(24px,5vw,72px);margin-top:22px}
  .t-grid>div{display:flex;flex-direction:column;gap:4px}
  .k{font-size:clamp(14px,1.3vw,20px);color:rgba(234,255,249,.66);text-transform:uppercase;letter-spacing:.05em}
  .vv{font-size:clamp(30px,3.6vw,60px);font-weight:800;color:#fff}.vv.change{color:#7ae2cf}
  .off{position:absolute;bottom:12px;left:0;right:0;text-align:center;font-size:12px;color:rgba(234,255,249,.4)}
</style></head>
<body>
<div id="cd" class="welcome"><div class="brand"><span class="store">Tuléh</span></div><div class="w-title">Selamat datang</div></div>
<div class="off" id="off" style="display:none">Menyambung ke kasir…</div>
<script>
  var root=document.getElementById('cd'), off=document.getElementById('off'), lastVideo='';
  function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
  function rp(n){return 'Rp '+(Number(n)||0).toLocaleString('id-ID')}
  function render(s){
    s=s||{}; var store=s.store||{}, items=s.items||[], t=s.totals||{}, pay=s.payment||null, grand=Number(t.grandTotal)||0;
    var logo=store.logo?'<img src="'+esc(store.logo)+'" alt="">':'';
    var brand='<div class="brand">'+logo+'<span class="store">'+esc(store.nama||'Tuléh')+'</span></div>';
    if(s.done){
      lastVideo='';
      root.className='thanks';
      root.innerHTML=brand+'<div class="ic">\\u2713</div><div class="t-title">Terima kasih!</div><div class="w-sub">Pembayaran diterima</div><div class="t-grid"><div><span class="k">Total</span><span class="vv">'+rp(grand)+'</span></div>'+(pay&&Number(pay.kembalian)>0?'<div><span class="k">Kembalian</span><span class="vv change">'+rp(pay.kembalian)+'</span></div>':'')+'</div>';
      return;
    }
    if(!items.length){
      // Video promosi hanya diganti bila URL berubah → tak restart tiap poll.
      if(s.promoVideo){
        if(lastVideo!==s.promoVideo){ lastVideo=s.promoVideo; root.className='welcome'; root.innerHTML='<video class="promo" src="'+esc(s.promoVideo)+'" autoplay muted loop playsinline></video>'; }
        return;
      }
      lastVideo=''; root.className='welcome';
      root.innerHTML=brand+'<div class="w-title">Selamat datang</div><div class="w-sub">Silakan, kami siap melayani Anda \\ud83d\\ude4f</div>';
      return;
    }
    lastVideo=''; root.className='order';
    var rows=items.map(function(it){return '<div class="row"><div class="r-name">'+esc(it.nama)+'</div><div class="r-meta"><span class="r-qty">'+(Number(it.qty)||0)+'\\u00d7</span><span>'+rp(it.harga)+'</span></div><div class="r-sub">'+rp(it.subtotal)+'</div></div>'}).join('');
    var disc=Number(t.totalDiskon)>0?'<div class="line"><span>Diskon</span><span>\\u2212'+rp(t.totalDiskon)+'</span></div>':'';
    var tax=Number(t.totalPajak)>0?'<div class="line"><span>Pajak</span><span>'+rp(t.totalPajak)+'</span></div>':'';
    var paybox=pay?'<div class="pay"><div class="line"><span>Dibayar'+(pay.metode?' \\u00b7 '+esc(pay.metode):'')+'</span><span>'+rp(pay.dibayar)+'</span></div><div class="line"><span>Kembalian</span><span class="change">'+rp(pay.kembalian)+'</span></div></div>':'';
    root.innerHTML='<div class="top">'+brand+'<div class="count">'+(items.reduce(function(a,i){return a+(Number(i.qty)||0)},0))+' item</div></div><div class="items">'+rows+'</div><div class="foot">'+disc+tax+'<div class="total"><b>Total</b><span class="v">'+rp(grand)+'</span></div>'+paybox+'</div>';
  }
  function poll(){ fetch('/display/data',{cache:'no-store'}).then(function(r){return r.json()}).then(function(s){off.style.display='none';render(s)}).catch(function(){off.style.display='block'}); }
  poll(); setInterval(poll, 1400);
</script>
</body></html>`
}

function renderTracking(info) {
  const { order, states, labels, tokoNama } = info
  const currentIdx = states.indexOf(order.stage)
  // "Selesai": pesanan mencapai tahap TERAKHIR (mis. Siap / Siap Diambil) atau
  // stage terminal eksplisit (SELESAI/diambil). Saat kasir klik "Selesai" di papan
  // antrian, order pindah ke tahap terakhir → tracking pelanggan tampil "Selesai".
  const selesai = (states.length > 0 && currentIdx === states.length - 1) ||
    /^(SELESAI|DIAMBIL|SERAH|DONE|SELESAI_)/i.test(String(order.stage || ''))

  const timeline = states.map((stage, idx) => {
    const cls = (selesai || idx < currentIdx) ? 'done' : idx === currentIdx ? 'now' : 'next'
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
      ${selesai ? `
        <div style="text-align:center;padding:22px 14px;background:#dff7f1;border:2px solid #2fae99;border-radius:10px;margin-bottom:14px">
          <div style="width:66px;height:66px;margin:0 auto 10px;border-radius:50%;background:#2fae99;color:#fff;font-size:40px;font-weight:800;display:flex;align-items:center;justify-content:center">&#10003;</div>
          <div style="font-size:23px;font-weight:800;color:#17695d">Pesanan Selesai</div>
          <div style="font-size:14px;color:#526e66;margin-top:4px;line-height:1.5">Pesanan Anda telah selesai${order.no_antrian ? ` &mdash; antrian <b>${escapeHtml(order.no_antrian)}</b>` : ''}. Silakan diambil. Terima kasih! &#128522;</div>
        </div>` : ''}
      ${order.no_antrian && !selesai ? `
        <div class="antrian">
          <div class="lbl">Nomor Antrian</div>
          <div class="no">${escapeHtml(order.no_antrian)}</div>
        </div>` : ''}
      ${!selesai ? `<div class="status-now">${escapeHtml(labels[order.stage] || order.stage)}</div>` : ''}
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
  const seksi = [...grup.entries()].map(([kat, produk]) => `
    <div class="mgroup">${escapeHtml(kat)}</div>
    ${produk.map((p) => {
      const q0 = Number(prefill[`q_${p.id}`]) || 0
      return `
      <div class="mitem${q0 > 0 ? ' is-on' : ''}" data-harga="${Number(p.harga) || 0}">
        <div class="mitem__info">
          <div class="mitem__nama">${escapeHtml(p.nama)}</div>
          <div class="mitem__harga">Rp ${Number(p.harga).toLocaleString('id-ID')}</div>
        </div>
        <div class="stepper">
          <button type="button" class="stepper__btn" data-act="dec" aria-label="Kurangi">&minus;</button>
          <span class="stepper__val">${q0}</span>
          <button type="button" class="stepper__btn" data-act="inc" aria-label="Tambah">+</button>
        </div>
        <input type="hidden" name="q_${escapeHtml(p.id)}" value="${q0}" />
      </div>`
    }).join('')}`).join('')

  const isiUtama = info.products.length === 0
    ? `<div class="card empty">Menu belum tersedia. Silakan pesan langsung di kasir.</div>`
    : `<form method="POST" action="/o/${escapeHtml(kode)}" id="ordform">
        <div class="card fieldcard">
          <label class="flabel" for="nama">Nama Anda</label>
          <input class="finput" id="nama" name="nama" required maxlength="60" placeholder="mis. Budi" value="${escapeHtml(prefill.nama || '')}" />
        </div>
        <div class="card menucard">${seksi}</div>
        <div class="card fieldcard">
          <label class="flabel" for="catatan">Catatan (opsional)</label>
          <input class="finput" id="catatan" name="catatan" maxlength="300" placeholder="mis. tanpa seledri, level pedas 2" value="${escapeHtml(prefill.catatan || '')}" />
        </div>
        <div class="foot">Pembayaran di kasir. Setelah dikirim, Anda dapat tautan untuk memantau status pesanan.</div>
        <div class="orderbar">
          <div class="orderbar__sum"><span id="ob-count">0 item</span><b id="ob-total">Rp 0</b></div>
          <button type="submit" class="orderbar__btn" id="ob-submit" disabled>Kirim Pesanan &rarr;</button>
        </div>
      </form>`

  const body = `
    <div class="mhead">
      <div class="mhead__toko">${escapeHtml(info.tokoNama)}</div>
      <div class="mhead__meja">Meja ${escapeHtml(info.mejaNomor)}</div>
    </div>
    ${errorMsg ? `<div class="card errbox">${escapeHtml(errorMsg)}</div>` : ''}
    ${isiUtama}
    <style>
      .wrap { max-width: 480px; padding-bottom: 96px; }
      .mhead { text-align: center; margin-bottom: 14px; }
      .mhead__toko { font-size: 22px; font-weight: 800; color: #14332c; letter-spacing: -.01em; }
      .mhead__meja { display: inline-block; margin-top: 7px; font-size: 13px; font-weight: 700; color: #17695d;
                     background: #dff7f1; border: 1px solid #bff0e5; border-radius: 999px; padding: 4px 15px; }
      .card { background: #fff; border: 1px solid #cde2da; border-radius: 12px; padding: 14px; margin-bottom: 12px; }
      .errbox { border-color: #d93a49; color: #b02a37; }
      .empty { text-align: center; padding: 28px 16px; color: #526e66; }
      .flabel { font-size: 13px; font-weight: 700; color: #526e66; }
      .finput { width: 100%; padding: 12px; border: 1px solid #cde2da; border-radius: 9px; margin-top: 6px; font-size: 16px; }
      .finput:focus { outline: none; border-color: #2fae99; box-shadow: 0 0 0 3px rgba(122,226,207,.35); }
      .menucard { padding: 2px 14px; }
      .mgroup { font-size: 12px; font-weight: 800; letter-spacing: .06em; text-transform: uppercase; color: #17695d; padding: 15px 0 6px; }
      .mitem { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 0; border-top: 1px solid #eef5f2; }
      .mgroup + .mitem { border-top: none; }
      .mitem__nama { font-weight: 700; font-size: 15px; color: #14332c; line-height: 1.3; }
      .mitem__harga { font-size: 14px; color: #526e66; margin-top: 2px; }
      .mitem.is-on .mitem__nama { color: #0e6b5c; }
      .stepper { display: flex; align-items: center; gap: 2px; flex-shrink: 0; }
      .stepper__btn { width: 42px; height: 42px; border: 1px solid #cde2da; background: #f7fcfa; color: #0e6b5c;
                      font-size: 22px; font-weight: 800; line-height: 1; border-radius: 10px; cursor: pointer;
                      display: flex; align-items: center; justify-content: center; -webkit-tap-highlight-color: transparent; }
      .stepper__btn:active { background: #dff7f1; transform: scale(.93); }
      .stepper__val { min-width: 30px; text-align: center; font-size: 17px; font-weight: 800; color: #14332c; font-variant-numeric: tabular-nums; }
      .mitem:not(.is-on) .stepper__btn[data-act="dec"] { opacity: .3; }
      .orderbar { position: fixed; left: 0; right: 0; bottom: 0; max-width: 480px; margin: 0 auto; z-index: 20;
                  display: flex; align-items: center; gap: 12px; padding: 12px 14px calc(12px + env(safe-area-inset-bottom));
                  background: #fff; border-top: 1px solid #cde2da; box-shadow: 0 -8px 24px -14px rgba(0,0,0,.28); }
      .orderbar__sum { display: flex; flex-direction: column; line-height: 1.2; }
      .orderbar__sum span { font-size: 12px; color: #526e66; }
      .orderbar__sum b { font-size: 19px; color: #14332c; font-variant-numeric: tabular-nums; }
      .orderbar__btn { flex: 1; padding: 15px; background: #7ae2cf; border: none; border-radius: 10px; font-size: 16px;
                       font-weight: 800; color: #08332c; cursor: pointer; }
      .orderbar__btn:disabled { background: #e6efec; color: #9db3ab; }
      .foot { text-align: center; margin-bottom: 6px; }
    </style>
    <script>
      (function () {
        var form = document.getElementById('ordform'); if (!form) return;
        var countEl = document.getElementById('ob-count'), totalEl = document.getElementById('ob-total'), subBtn = document.getElementById('ob-submit');
        function fmt(n){ return 'Rp ' + (Number(n) || 0).toLocaleString('id-ID'); }
        function recompute(){
          var count = 0, total = 0;
          form.querySelectorAll('.mitem').forEach(function (it) {
            var q = Number(it.querySelector('input[type=hidden]').value) || 0;
            count += q; total += q * (Number(it.getAttribute('data-harga')) || 0);
          });
          countEl.textContent = count + ' item'; totalEl.textContent = fmt(total); subBtn.disabled = count === 0;
        }
        form.addEventListener('click', function (e) {
          var btn = e.target.closest('.stepper__btn'); if (!btn) return;
          var it = btn.closest('.mitem'), hid = it.querySelector('input[type=hidden]'), v = Number(hid.value) || 0;
          v += btn.getAttribute('data-act') === 'inc' ? 1 : -1; if (v < 0) v = 0; if (v > 20) v = 20;
          hid.value = v; it.querySelector('.stepper__val').textContent = v; it.classList.toggle('is-on', v > 0);
          recompute();
        });
        form.addEventListener('submit', function (e) { if (subBtn.disabled) e.preventDefault(); });
        recompute();
      })();
    </script>`

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
      const isSiap = idx === info.states.length - 1 // kolom terakhir (Siap) disorot
      return `
        <section class="qcol${isSiap ? ' qcol--siap' : ''}">
          <h2>${escapeHtml(info.labels[stage] || stage)}<span class="qcount">${isi.length}</span></h2>
          <div class="qnums">
            ${isi.length
              ? isi.map((r) => `<span class="qno${r.meja ? ' qno--meja' : ''}">${escapeHtml(r.label || r.no_antrian)}</span>`).join('')
              : '<span class="qkosong">—</span>'}
          </div>
        </section>`
    }).join('')
    res.writeHead(200)
    res.end(pageShell(`Antrian — ${info.tokoNama}`, `
      <div class="head">
        <div class="kicker">Papan Antrian</div>
        <h1 class="toko">${escapeHtml(info.tokoNama)}</h1>
      </div>
      <div class="qgrid">${kolom}</div>
      <div class="foot">Diperbarui otomatis tiap ${REFRESH_SECONDS} detik · Tuléh</div>
      <style>
        html, body { height: 100%; }
        body { margin: 0; padding: 0; overflow: hidden; color: #eafff9;
               background: radial-gradient(1200px 700px at 85% -10%, rgba(122,226,207,.14), transparent 60%),
                           linear-gradient(160deg,#0a2723,#06201c 60%,#041613); }
        .wrap { max-width: none; width: 100%; height: 100vh; margin: 0;
                padding: clamp(16px,2.4vw,42px); display: flex; flex-direction: column; }
        .head { text-align: center; margin-bottom: clamp(10px,2vh,26px); flex-shrink: 0; }
        .head .kicker { font-size: clamp(12px,1.2vw,18px); font-weight: 700; letter-spacing:.14em;
                        text-transform: uppercase; color: #7ae2cf; }
        .head .toko { font-size: clamp(26px,3.4vw,52px); font-weight: 800; letter-spacing:-.01em;
                      margin-top: 4px; color:#fff; }
        .qgrid { flex: 1 1 auto; min-height: 0; display: grid;
                 grid-template-columns: repeat(${info.states.length}, 1fr); gap: clamp(12px,1.4vw,20px); }
        .qcol { display: flex; flex-direction: column; min-height: 0; border-radius: 16px;
                padding: clamp(14px,1.4vw,22px); background: rgba(255,255,255,.04);
                border: 1px solid rgba(122,226,207,.16); }
        .qcol h2 { display:flex; align-items:center; justify-content:space-between; gap:10px; flex-shrink:0;
                   font-size: clamp(15px,1.5vw,24px); text-transform: uppercase; letter-spacing:.06em;
                   color:#9fe9d8; padding-bottom: 12px; border-bottom: 1px solid rgba(122,226,207,.16); }
        .qcount { font-size:.72em; color:#06201c; background:#7ae2cf; border-radius:999px; min-width:1.9em;
                  text-align:center; padding: 2px 9px; font-weight:800; }
        .qcol--siap { background: rgba(122,226,207,.12); border-color:#2fae99; }
        .qcol--siap h2 { color:#7ae2cf; }
        .qnums { flex:1 1 auto; min-height:0; overflow-y:auto; display:flex; flex-wrap:wrap;
                 align-content:flex-start; gap: clamp(8px,1vw,14px); padding-top: 14px; }
        .qno { font-family: ui-monospace, Consolas, monospace; font-weight:800; line-height:1;
               font-size: clamp(30px,4vw,66px); color:#eafff9; background: rgba(122,226,207,.1);
               border:1px solid rgba(122,226,207,.22); border-radius: 12px; padding: .18em .32em; }
        .qcol--siap .qno { background: rgba(122,226,207,.2); border-color:#7ae2cf; color:#fff; }
        .qno--meja { font-family: inherit; }
        .qkosong { color: rgba(234,255,249,.4); font-size: clamp(24px,2.4vw,40px); padding: 10px; }
        .foot { flex-shrink:0; text-align:center; margin-top: clamp(8px,1.6vh,20px);
                font-size: clamp(11px,1vw,15px); color: rgba(234,255,249,.55); }
        @media (max-width: 700px) { .qgrid { grid-template-columns: 1fr; overflow-y:auto; } }
      </style>`))
    return
  }

  // Data Display Pelanggan (JSON) — di-poll oleh halaman /display
  if (url.pathname === '/display/data' && req.method === 'GET') {
    res.setHeader('Content-Type', 'application/json; charset=utf-8')
    res.writeHead(200)
    res.end(JSON.stringify(customerState || {}))
    return
  }

  // Halaman Display Pelanggan (LAN) — buka di monitor/TV pelanggan di jaringan
  if (url.pathname === '/display' && req.method === 'GET') {
    res.writeHead(200)
    res.end(displayPage())
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
  customerState = null
}

// Relay state Display Pelanggan dari window kasir (dipanggil ipc customer:update)
// supaya halaman LAN /display bisa menampilkan keranjang live.
function setCustomerState(state) {
  customerState = state || null
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

module.exports = { start, stop, status, setPublicUrl, setCustomerState }
