# mpos-backend

Gateway Go lokal antara aplikasi **MPos** (Electron) dan **MOVERA POS API**
(`tatreport.com`). Bukan proxy terbuka — hanya endpoint MOVERA yang dikenal
yang diteruskan.

```
MPos (Electron) ──HTTP──▶ mpos-backend (127.0.0.1:8787) ──HTTPS──▶ tatreport.com
```

## Kenapa ada gateway?

| Aspek | Yang dilakukan |
|---|---|
| **Cepat** | Cache TTL di memori per token (produk 15 dtk, master/config 5 mnt, laporan 30 dtk) — di-purge otomatis saat checkout/void/buka-tutup sesi; koneksi HTTPS di-pool (ping: ~5 dtk dingin → ~140 ms berikutnya); retry 1× untuk GET yang gagal jaringan |
| **Aman** | Bind default hanya `127.0.0.1`; allowlist 29 endpoint (di luar itu 404); rate limit 20 rps/IP + khusus login 5/menit (anti brute force); body maks 1 MB; token tidak pernah disimpan atau ditulis ke log (cache di-key dengan SHA-256 token); zero dependency — murni stdlib Go |

## Menjalankan

**Otomatis (default).** Aplikasi MPos menyalakan gateway ini sendiri saat dibuka
(binary dibundel installer di `resources/backend/`), memakai URL server tenant
sebagai upstream, dan mematikannya saat aplikasi ditutup. Bila sudah ada
instance berjalan dengan upstream sama, instance itu dipakai ulang. Status
terlihat di **Pengaturan → Aplikasi → Gateway lokal**. Biarkan URL server tetap
domain tenant — JANGAN menunjuk `http://localhost:8787` secara manual (nilai
lama seperti itu dimigrasikan otomatis kembali ke domain tenant).

**Manual (opsional, untuk pengembangan):**

```powershell
cd frontend
powershell -ExecutionPolicy Bypass -File tools\run-backend.ps1
```

Konfigurasi via environment:

| Variabel | Default | Keterangan |
|---|---|---|
| `MPOS_LISTEN` | `127.0.0.1:8787` | Alamat dengar |
| `MPOS_UPSTREAM` | `https://tatreport.com` | Domain tenant MOVERA (wajib HTTPS) |
| `MPOS_LOG` | `info` | `debug` untuk log rinci |

## Pengembangan

```powershell
cd backend
go test ./... -count=1   # unit test: cache, rate limit, proxy end-to-end
go vet ./...
```

Catatan CFA: `go build`/`gofmt -w` tidak bisa menulis ke folder proyek ini —
build selalu diarahkan ke `%LOCALAPPDATA%\ipos-build\backend\` (sudah ditangani
`run-backend.ps1`).

## Struktur

| File | Isi |
|---|---|
| `main.go` | Konfigurasi, rakit middleware, server + graceful shutdown |
| `routes.go` | Tabel allowlist endpoint + TTL cache + aturan purge |
| `proxy.go` | Penerusan ke upstream, retry GET, kunci cache per token |
| `cache.go` | Cache TTL thread-safe + purge per prefix |
| `ratelimit.go` | Token bucket per IP (jam bisa disuntik untuk test) |
| `middleware.go` | Recover, request-id, header keamanan, batas body, log |
