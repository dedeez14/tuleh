# Kontrak Masa Coba Mode Demo (server MOVERA)

Ringkasan kontrak untuk tim server. Versi lengkap dengan alur, tabel data, dan
aturan keamanan ada di dokumen "Kontrak Masa Coba Tuléh" (dibagikan pemilik).

Aplikasi desktop ≥ 0.9.14 dan Android ≥ 2.6.0 sudah memanggil endpoint ini dan
**fail-open**: selama server membalas 404 atau tak terjangkau, aplikasi memakai
masa coba lokal saja (waktu server + catatan bertanda). Begitu endpoint hidup,
lapis perangkat dan identitas aktif tanpa rilis aplikasi baru.

Semua endpoint publik (tanpa Bearer, tanpa middleware 426), prefix `/api/pos/v1`,
envelope `{success, data, meta, message, errors}`, rate limit seperti `/app/versi`.

## Tiga lapis

| Lapis | Menutup | Tidak menutup |
|---|---|---|
| 1. Lokal (sudah rilis) | ubah jam, edit berkas | hapus aplikasi, reset perangkat |
| 2. Perangkat (`/demo/perangkat`) | hapus & pasang ulang aplikasi | factory reset, install ulang Windows, ganti perangkat |
| 3. Identitas OTP (`/demo/otp/*`) | reset & ganti perangkat (satu nomor = satu masa coba) | factory reset + nomor baru |

## Endpoint

### `POST /demo/perangkat`
Daftarkan/muat ulang perangkat. Idempoten.

```json
{ "perangkat_id": "<64 hex>", "platform": "android|windows", "sidik_jari": "<64 hex>",
  "versi_app": "2.6.0", "identitas_token": "<opsional, dari verifikasi OTP>" }
```
Jawaban `data`:
```json
{ "status": "AKTIF|BELUM_VERIFIKASI|BERAKHIR|DIBLOKIR", "butuh_identitas": false,
  "mulai": "2026-09-05T03:00:00Z", "berakhir_pada": "2026-09-12T03:00:00Z", "sisa_hari": 7,
  "waktu_server": "2026-09-05T03:00:12Z", "identitas": { "jenis": "wa", "nilai_tersamar": "0812••••567" } }
```

### `GET /demo/perangkat/{perangkat_id}`
Status terbaru (bentuk sama). Perangkat tak dikenal → 404 (aplikasi lalu POST).

### `POST /demo/otp/kirim`
`{ perangkat_id, jenis: "wa"|"email", tujuan }` → `{ kadaluarsa_detik: 300, kirim_ulang_setelah_detik: 60 }`.
Kode 6 digit, 5 menit, maks 5 percobaan. Balasan sama apa pun status nomor (jangan bocorkan).

### `POST /demo/otp/verifikasi`
`{ perangkat_id, jenis, tujuan, kode }` → `{ identitas_token, status, mulai, berakhir_pada, sisa_hari, waktu_server }`.
Kode salah → 422 `errors.kode`.

## Aturan

1. Server menentukan `mulai` (`now()` saat perangkat pertama terlihat / identitas terverifikasi). Aplikasi tak pernah mengirim waktu.
2. Satu identitas satu masa coba: verifikasi di perangkat baru mengembalikan masa coba yang sudah ada.
3. Satu perangkat satu masa coba: identitas baru di perangkat yang sudah berakhir tetap `BERAKHIR`.
4. `butuh_identitas` adalah flag global server; matikan bila pengirim OTP belum siap (lapis 2 tetap jalan).
5. `DIBLOKIR` manual/otomatis (mis. > 3 identitas dari satu perangkat dalam 30 hari).
6. Selalu sertakan `waktu_server`.

## Identitas perangkat di aplikasi

- Android: SHA-256(`ANDROID_ID` | nama paket) — bertahan hapus/pasang ulang, berubah saat factory reset.
- Windows: SHA-256(`MachineGuid` | nama pengguna) — bertahan hapus/pasang ulang, berubah saat install ulang Windows. Catatan lokal juga disalin ke registry `HKCU\Software\Tuleh` dan `%ProgramData%\Tuleh`.
