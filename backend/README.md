# mpos-backend

Gateway Go lokal antara aplikasi desktop (Electron) dan **POS API** server tenant.
Bukan proxy terbuka — hanya endpoint yang dikenal (tabel `routes.go`) yang diteruskan.

```
Aplikasi (Electron) ──HTTP──▶ mpos-backend (127.0.0.1:8787) ──HTTPS──▶ server tenant (MPOS_UPSTREAM)
```

## Kenapa ada gateway?

| Aspek | Yang dilakukan |
|---|---|
| **Cepat** | Cache TTL di memori per token (produk 15 dtk, master/config 5 mnt, laporan 30 dtk) — di-purge otomatis saat checkout/void/buka-tutup sesi; koneksi HTTPS di-pool (ping: ~5 dtk dingin → ~140 ms berikutnya); retry 1× untuk GET yang gagal jaringan |
| **Aman** | Bind default hanya `127.0.0.1`; allowlist endpoint ketat (di luar itu 404); rate limit 20 rps/IP + khusus login 5/menit (anti brute force); body maks 1 MB; token tidak pernah disimpan atau ditulis ke log (cache di-key dengan SHA-256 token); zero dependency — murni stdlib Go |

## Menjalankan

**Otomatis (default).** Aplikasi menyalakan gateway ini sendiri saat dibuka
(binary dibundel installer di `resources/backend/`), memakai URL server tenant
sebagai upstream, dan mematikannya saat aplikasi ditutup. Instance yang sudah
berjalan dipakai ulang HANYA bila upstream **dan versinya** sama dengan aplikasi.
Bila proses gateway keluar, aplikasi langsung kembali ke koneksi langsung lalu
mencoba menyalakannya lagi dengan jeda bertahap (1 dtk → 5 mnt). Log gateway
(stdout/stderr) masuk ke `logs/gateway.log` aplikasi. Status
terlihat di **Pengaturan → Aplikasi → Gateway lokal**. Biarkan URL server tetap
domain tenant — JANGAN menunjuk `http://localhost:8787` secara manual (nilai
lama seperti itu dimigrasikan otomatis kembali ke domain tenant).

**Manual (opsional, untuk pengembangan):**

```powershell
cd frontend
powershell -ExecutionPolicy Bypass -File tools\run-backend.ps1 -Upstream https://domain-server-anda
```

Konfigurasi via environment:

| Variabel | Default | Keterangan |
|---|---|---|
| `MPOS_LISTEN` | `127.0.0.1:8787` | Alamat dengar |
| `MPOS_UPSTREAM` | — (**wajib**) | Domain server tenant (wajib HTTPS; http hanya localhost). Tidak ada server bawaan tertanam |
| `MPOS_VERSION` | — | Versi yang dilaporkan `/healthz` bila build tanpa `-ldflags "-X main.appVersion=…"` (CI selalu memakai ldflags = versi `frontend/package.json`) |
| `MPOS_LOG` | `info` | `debug` untuk log rinci |

## Galat buatan gateway

Galat yang DIBUAT gateway (bukan jawaban server) diberi header `X-Tuleh-Gateway` agar
aplikasi membedakan "server tak terjangkau" dari "server menolak":

| Status | `X-Tuleh-Gateway` | Arti bagi aplikasi |
|---|---|---|
| 502 | `upstream-unreachable` | Gangguan jaringan → GET dari salinan offline, tulis diantrekan |
| 429 | `rate-limited` | Gangguan sementara |
| 500 | `internal` | Gangguan sementara (panic gateway) |
| 404 | `route-unknown` | Rute tidak ada di allowlist → bug aplikasi (dijaga tes `frontend/tests/rute-gateway.test.js`) |
| 413 | `body-too-large` | Penolakan (badan > batas) |

Jawaban server (termasuk 5xx) diteruskan apa adanya tanpa header ini. Header permintaan
yang diteruskan: `Authorization`, `Content-Type`, `Accept`, `Accept-Language`,
`X-Tuleh-Version`, `X-Tuleh-Platform`.

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
