---
name: pahami-context-tuleh
description: 'Pahami konteks aplikasi Tuleh end-to-end (Electron desktop, gateway Go, Android Capacitor, dan Flutter) dengan workflow terstruktur. Use when: onboarding developer baru, audit arsitektur, handover fitur, debugging lintas platform, memahami alur POS manifest-driven, mengecek run/test/build command repo ini.'
argument-hint: 'Fokuskan konteks ke area tertentu: desktop|backend|android|flutter|semua + level detail singkat|lengkap'
---

# Pahami Context Tuleh

## Outcome
Skill ini menghasilkan paket pemahaman yang bisa langsung dipakai tim:
1. Ringkasan arsitektur end-to-end dan batas keamanan antar lapisan.
2. Peta file penting per platform (entry point, alur data, titik integrasi API).
3. Ringkasan alur bisnis POS universal (manifest-driven, order lifecycle, open bill, QR).
4. Daftar command run, test, dan build yang relevan.
5. Daftar gap/pertanyaan terbuka yang perlu konfirmasi dari owner produk.

## When to Use
Gunakan skill ini saat:
- Baru masuk ke codebase Tuleh dan perlu memahami sistem cepat.
- Ingin audit dampak perubahan sebelum implementasi fitur.
- Menangani bug lintas platform (desktop, backend gateway, Android).
- Menyiapkan dokumentasi handover internal.
- Perlu validasi bahwa pemahaman arsitektur sudah lengkap sebelum coding.

## Inputs
Minta atau infer input berikut:
- Fokus area: `semua` (default), `desktop`, `backend`, `android`, atau `flutter`.
- Kedalaman: `singkat` (high-level) atau `lengkap` (dengan alur file detail).
- Mode verifikasi: `dokumen-saja` atau `plus-test`.

Default operasional saat argumen kosong:
- Fokus: `semua`
- Kedalaman: `lengkap`
- Verifikasi: `dokumen-saja`

## Procedure

### 1) Scope and Alignment
1. Tetapkan output yang diinginkan user (ringkasan, checklist, atau peta file detail).
2. Jika user tidak memberi fokus, pakai mode `semua`.
3. Jika user tidak memberi kedalaman, pakai `lengkap`.
4. Jika user tidak meminta eksekusi command, mulai dari `dokumen-saja`.

Decision point:
- Jika user butuh jawaban cepat, berikan mode `singkat` dulu lalu tawarkan pendalaman.
- Jika user ingin siap coding/debugging, wajib pakai mode `lengkap`.

### 2) Build Architectural Baseline
Baca dokumen inti berurutan:
1. `README.md`
2. `Docs-API.md`
3. `Blueprint-Universal-POS.md`
4. `backend/README.md`
5. `mobile/README.md`
6. `AUTO-UPDATE.md` dan `SERVER-AUTO-UPDATE.md` (untuk alur update)

Output minimal tahap ini:
- Diagram mental alur request: renderer -> bridge -> backend gateway (opsional) -> MOVERA API.
- Daftar tanggung jawab tiap lapisan.

### 3) Platform Deep Dive (Branching)
Masuk ke cabang berdasarkan fokus user.

#### A. Desktop Electron (`desktop` atau `semua`)
Urutan baca file:
1. `frontend/src/main/main.js`
2. `frontend/src/main/ipc.js`
3. `frontend/src/main/api-client.js`
4. `frontend/src/main/auth-store.js`
5. `frontend/src/preload/preload.js`
6. `frontend/src/renderer/js/app.js`
7. `frontend/src/renderer/js/update.js`
8. `frontend/package.json`

Yang harus dipetakan:
- Boundary keamanan: renderer sandbox vs main process.
- Surface API `window.iposAPI` dari preload ke renderer.
- Flow update desktop (electron-updater) dan fallback.

#### B. Backend Gateway Go (`backend` atau `semua`)
Urutan baca file:
1. `backend/main.go`
2. `backend/routes.go`
3. `backend/proxy.go`
4. `backend/cache.go`
5. `backend/ratelimit.go`
6. `backend/middleware.go`
7. `backend/proxy_test.go`, `backend/cache_test.go`, `backend/ratelimit_test.go`

Yang harus dipetakan:
- Allowlist endpoint dan alasan keamanan (bukan open proxy).
- Strategi cache TTL, purge invalidation, retry behavior.
- Rate limit global/login dan implikasi ke UX.

#### C. Android Capacitor (`android` atau `semua`)
Urutan baca file:
1. `mobile/README.md`
2. `mobile/www-src/js/mobile-bridge.js`
3. `mobile/native/ApkUpdaterPlugin.java`
4. `mobile/native/MainActivity.java`
5. `mobile/capacitor.config.json`

Yang harus dipetakan:
- Pengganti peran main-process di Android (bridge langsung ke API).
- Mekanisme updater APK in-app + permission install unknown app.
- Batas fitur parity vs desktop.

#### D. Flutter (sekunder secara default)
Saat fokus `semua`, jalur Flutter cukup status-check ringkas:
1. `mobile-flutter/README.md`
2. `mobile-flutter/pubspec.yaml`
3. `mobile-flutter/lib/main.dart` (opsional jika perlu validasi entry point)

Yang harus dipetakan:
- Tingkat kematangan implementasi Flutter terhadap produk utama.
- Gap antara Flutter app dan desktop/capacitor dari sisi fitur.

Jika user memilih fokus `flutter`, lanjutkan deep dive tambahan:
1. `mobile-flutter/lib/app.dart`
2. Struktur `mobile-flutter/lib/core/` dan `mobile-flutter/lib/features/`
3. Strategi integrasi API, state, dan parity terhadap desktop

### 4) Business Workflow Mapping
Petakan alur domain inti dari dokumen + kode renderer:
1. Manifest-driven module rendering.
2. Flow kasir standar (inventory_sale).
3. Flow food_order (kitchen/KDS/antrian/open bill).
4. Flow service_job (stage laundry).
5. QR tracking dan self-order.
6. Pembayaran termasuk QRIS dan langganan.

Decision point:
- Jika implementasi kode berbeda dari blueprint, catat sebagai "drift".
- Jika behavior hanya ada di demo mode, tandai jelas agar tidak dianggap production parity.

### 5) Verification Pass
Jika mode `plus-test`, jalankan:
1. `cd frontend && npm test`
2. `cd backend && go test ./...`

Opsional build check:
1. `cd frontend && npm run dist`
2. `cd mobile && powershell -ExecutionPolicy Bypass -File build-android.ps1`

Catat status:
- Lolos/gagal per command.
- Error penting + area file terkait.

### 6) Deliverable Format
Susun hasil akhir dengan format tetap:
1. Executive summary (5-10 poin).
2. Peta komponen per platform.
3. Alur data dan keamanan.
4. Alur bisnis utama.
5. Risiko/gap dan asumsi.
6. Rekomendasi next steps (maks 3 langkah).

## Completion Criteria
Skill dianggap selesai bila semua cek berikut terpenuhi:
- Bisa menjelaskan alur end-to-end request desktop dan Android tanpa ambigu.
- Bisa menyebut entry point utama tiap platform dan fungsi ringkasnya.
- Bisa membedakan sumber kebenaran: blueprint vs implementasi saat ini.
- Bisa menunjukkan command test/build yang relevan untuk area yang dibahas.
- Menghasilkan daftar gap/asumsi yang butuh validasi owner.

## Guardrails
- Jangan ubah kode saat sesi hanya meminta pemahaman konteks.
- Jangan asumsi fitur production hanya dari demo data.
- Jangan menyebarkan token, credential, atau detail sensitif dari environment.
- Jika ada konflik antara dokumen dan kode, prioritaskan observasi kode lalu tandai konflik eksplisit.

## Example Prompts
- `/pahami-context-tuleh semua lengkap plus-test`
- `/pahami-context-tuleh desktop lengkap`
- `/pahami-context-tuleh backend singkat`
- `/pahami-context-tuleh android lengkap dokumen-saja`
