# Panduan Server — Auto-Update Tuléh

Panduan tunggal untuk mengimplementasikan seluruh sisi server fitur **Auto-Update Tuléh POS** pada MOVERA POS API (Laravel di `https://tatreport.com`, prefix `/api/pos/v1`) beserta subdomain unduhan `pos.tatreport.com`. Semua contoh utama memakai Laravel; padanan Node/Express disertakan di bagian yang relevan. Contoh bersifat framework-agnostik — yang **wajib identik** adalah kontrak HTTP, bentuk envelope, nama berkas, dan perilaku Range/`latest.yml`.

> Prinsip menyeluruh: **klien bersifat _fail-open_** (kegagalan cek tak memblokir pemakaian), tetapi **server harus tetap benar & andal**. Semua teks yang tampil ke pengguna **wajib Bahasa Indonesia**. **TLS unduhan tidak pernah dinonaktifkan.**

---

## Ringkasan Arsitektur

Tiga bidang bekerja sama: klien (desktop `.exe` via electron-updater + Android `.apk`), API MOVERA (endpoint cek versi + penegakan 426), dan subdomain unduhan biner. Nomor versi desktop & Android **selalu sama** dan dirilis bersamaan, jadi cukup **satu `versi_terbaru` global + satu `versi_minimum` global**; hanya URL unduhan yang berbeda per platform.

```
                        Header di SEMUA request:  X-Tuleh-Version: <semver>
┌──────────────────────────┐                                   ┌──────────────────────────────┐
│  Klien Tuléh POS         │   request /api/pos/v1/*           │  Gateway Go (lokal klien)    │
│  • Desktop .exe          │  ───────────────────────────────▶ │  meneruskan X-Tuleh-Version   │
│    (electron-updater)    │                                   │  apa adanya                   │
│  • Android .apk          │  ◀─────────────────────────────── └───────────────┬──────────────┘
└─────────┬────────────────┘   envelope {success,data,meta,                     │
          │                     message,errors}                                 ▼
          │  (a) GET /app/versi  (TANPA auth, advisory)          ┌──────────────────────────────┐
          │  (b) sadap HTTP 426  (dari endpoint mana pun)        │  MOVERA POS API (Laravel)     │
          │                                                      │  https://tatreport.com        │
          │                                                      │  /api/pos/v1                  │
          │                                                      │   • GET /app/versi (§1)       │
          │                                                      │   • Middleware 426 (§2)       │
          │                                                      │   • tabel app_versi (§4)      │
          │                                                      └──────────────────────────────┘
          │  unduh installer (HTTP Range wajib, TLS wajib)
          ▼
┌───────────────────────────────────────────────────────────┐
│  Subdomain unduhan:  https://pos.tatreport.com/unduh/{nama}│
│   Tuleh-Setup-<versi>.exe   Tuleh-Setup-<versi>.exe.blockmap│
│   latest.yml                Tuleh-<versi>-android.apk       │
│   → redirect/mirror ke GitHub Release (CI, tag v<versi>)   │
└───────────────────────────────────────────────────────────┘
```

Alur klien yang harus didukung:

1. **Cek berkala** memanggil `GET /app/versi` → tampilkan **banner** (`update_tersedia && !wajib`) atau **layar penuh memblokir** (`wajib`).
2. **Interseptor 426** — bila endpoint mana pun membalas `426`, klien membuka layar update wajib dan menampilkan `message` apa adanya, lalu memanggil `/app/versi` untuk memperoleh URL unduhan.
3. **electron-updater** (desktop) memakai base feed `https://pos.tatreport.com/unduh`: ambil `latest.yml` → baca `path`+`sha512` → unduh `.exe` dengan Range → verifikasi sha512.

---

## Daftar Langkah (ringkas)

Urutan implementasi & deliverable:

1. **[ ] Fondasi bersama** — util perbandingan `SemVer` yang benar + `config/tuleh.php` statis (§1).
2. **[ ] Sumber kebenaran versi** — tabel `app_versi` (1 baris) + `AppVersiService` (cache 60 dtk) + default aman (§4).
3. **[ ] Endpoint publik** `GET /api/pos/v1/app/versi` — tanpa auth, tanpa 426, envelope + `unduhan` dua platform (§1).
4. **[ ] Middleware 426** `EnforceMinimumVersion` — dipasang **sebelum auth** di semua route `/api/pos/v1` **kecuali** `/app/versi`; baca `X-Tuleh-Version`; fail-open (§2).
5. **[ ] Endpoint admin** — CI menaikkan `versi_terbaru` (`POST /admin/app-versi`); manusia menaikkan `versi_minimum` (`PUT /admin/app-versi/minimum`) (§4).
6. **[ ] Auto-isi saat rilis** — job CI mengirim `versi_terbaru`/`catatan`/`ukuran` dari GitHub Release (§4).
7. **[ ] Proksi unduhan** `pos.tatreport.com/unduh/{nama}` — TLS + HTTP Range + whitelist nama; `latest.yml`+`.blockmap`+`.exe` satu direktori (§3).
8. **[ ] Keamanan** — rate-limit publik, validasi ketat, whitelist proksi, proteksi admin, TLS/HSTS (§5).
9. **[ ] Verifikasi** — jalankan blok `curl` & matriks uji; pastikan acceptance criteria lulus (§6).

Invarian yang **wajib dijaga**: `versi_minimum <= versi_terbaru` (jika dilanggar, seluruh klien terkunci tanpa jalan keluar).

---

## 1. Endpoint `/app/versi`

`GET /api/pos/v1/app/versi?versi=<semver>` — **tanpa auth**, idempoten, aman di-cache singkat. Endpoint ini murni **advisory**: memberi tahu apakah ada update (banner) atau update wajib (layar penuh). Penegakan keras versi minimum dilakukan lewat **HTTP 426** di middleware (§2), bukan di sini. **Endpoint ini tidak boleh diberi auth dan tidak boleh pernah membalas 426** — justru saat klien usang ia harus bisa mengambil `versi_terbaru`, `catatan`, dan URL `unduhan`.

### 1.1 Fondasi bersama

**`config/tuleh.php`** — hanya nilai statis. Nilai versi yang berubah tiap rilis (`versi_terbaru`, `versi_minimum`, `catatan`, `ukuran`) disimpan di tabel `app_versi` (§4), bukan di sini, agar ops bisa menaikkan ambang **tanpa deploy ulang**.

```php
// config/tuleh.php
<?php
return [
    // Template & base unduhan (URL diturunkan dari versi_terbaru, tidak disimpan di DB — DRY)
    'unduh_base'   => rtrim(env('TULEH_UNDUH_BASE', 'https://pos.tatreport.com/unduh'), '/'),
    'nama_win'     => env('TULEH_NAMA_WIN', 'Tuleh-Setup-{versi}.exe'),
    'nama_android' => env('TULEH_NAMA_ANDROID', 'Tuleh-{versi}-android.apk'),

    // Default aman bila tabel app_versi kosong (netral: tak menawarkan & tak memaksa)
    'default_versi_terbaru' => env('TULEH_DEFAULT_VERSI', '0.0.0'),
    'default_catatan'       => 'Tidak ada pembaruan.',

    // Penegakan 426 (§2)
    'enforce'       => (bool) env('TULEH_ENFORCE_MIN_VERSION', true), // kill-switch global
    'enforce_login' => (bool) env('TULEH_ENFORCE_LOGIN', true),       // rollout: set false dulu
    'catatan_wajib' => env('TULEH_CATATAN_WAJIB',
        'Versi aplikasi Anda sudah tidak didukung. Silakan perbarui untuk melanjutkan.'),

    // Admin & cache (§4)
    'admin_token' => env('APP_VERSI_ADMIN_TOKEN'), // rahasia; juga jadi GitHub Secret
    'cache_ttl'   => (int) env('TULEH_CACHE_TTL', 60), // detik
];
```

**`App\Support\SemVer`** — util perbandingan semver **satu-satunya** yang dipakai endpoint (§1), middleware (§2), dan service (§4). Presedensi SemVer 2.0.0: bandingkan `major.minor.patch` numerik; versi **tanpa** pre-release > versi **dengan** pre-release yang sama; identifier pre-release dibanding satu-per-satu (numerik < alfanumerik, lebih banyak identifier menang); build metadata (`+...`) diabaikan. Jangan pakai perbandingan string (`"0.9.9" > "0.10.0"` **salah**).

```php
// app/Support/SemVer.php
<?php
namespace App\Support;

class SemVer
{
    // Longgar tapi aman: 2–3 segmen, pre-release & build metadata opsional. Anchor + tanpa
    // quantifier bersarang → aman ReDoS bila panjang input dibatasi (max:64) lebih dulu.
    public const REGEX = '/^v?\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/';

    public static function isValid(?string $v): bool
    {
        return is_string($v) && $v !== '' && preg_match(self::REGEX, trim($v)) === 1;
    }

    /** @return array{0: array{int,int,int}, 1: string} [ [major,minor,patch], preRelease ] */
    private static function split(string $v): array
    {
        $v = ltrim(trim($v), 'vV');
        if (($p = strpos($v, '+')) !== false) $v = substr($v, 0, $p); // buang build metadata
        $pre = '';
        if (($d = strpos($v, '-')) !== false) { $pre = substr($v, $d + 1); $v = substr($v, 0, $d); }
        $n = array_map('intval', array_pad(explode('.', $v), 3, '0'));
        return [[$n[0], $n[1], $n[2]], $pre];
    }

    /** -1 jika a<b, 0 sama, 1 jika a>b (presedensi SemVer 2.0.0). */
    public static function compare(string $a, string $b): int
    {
        [$am, $ap] = self::split($a);
        [$bm, $bp] = self::split($b);

        for ($i = 0; $i < 3; $i++) {
            if ($am[$i] !== $bm[$i]) return $am[$i] < $bm[$i] ? -1 : 1;
        }
        if ($ap === '' && $bp === '') return 0;
        if ($ap === '') return 1;    // tanpa pre-release > dengan pre-release
        if ($bp === '') return -1;

        $ai = explode('.', $ap); $bi = explode('.', $bp);
        $len = min(count($ai), count($bi));
        for ($i = 0; $i < $len; $i++) {
            $x = $ai[$i]; $y = $bi[$i];
            $xn = ctype_digit($x); $yn = ctype_digit($y);
            if ($xn && $yn) {
                if ((int)$x !== (int)$y) return (int)$x < (int)$y ? -1 : 1;
            } elseif ($xn !== $yn) {
                return $xn ? -1 : 1;                 // numerik < alfanumerik
            } else {
                $c = strcmp($x, $y);
                if ($c !== 0) return $c < 0 ? -1 : 1;
            }
        }
        return count($ai) <=> count($bi);            // lebih banyak identifier menang
    }
}
```

Padanan Node (dipakai varian Express di §1.7 & §2.7):

```js
// semver.js
const SEMVER_RE = /^v?\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

function splitSemver(v) {
  v = String(v).trim().replace(/^v/i, '');
  const plus = v.indexOf('+'); if (plus !== -1) v = v.slice(0, plus);
  let pre = ''; const dash = v.indexOf('-');
  if (dash !== -1) { pre = v.slice(dash + 1); v = v.slice(0, dash); }
  const n = v.split('.').map(x => parseInt(x, 10) || 0);
  while (n.length < 3) n.push(0);
  return { main: n.slice(0, 3), pre };
}
function compareSemver(a, b) {
  const A = splitSemver(a), B = splitSemver(b);
  for (let i = 0; i < 3; i++) if (A.main[i] !== B.main[i]) return A.main[i] < B.main[i] ? -1 : 1;
  if (!A.pre && !B.pre) return 0;
  if (!A.pre) return 1;
  if (!B.pre) return -1;
  const ai = A.pre.split('.'), bi = B.pre.split('.');
  const len = Math.min(ai.length, bi.length);
  for (let i = 0; i < len; i++) {
    const x = ai[i], y = bi[i], xn = /^\d+$/.test(x), yn = /^\d+$/.test(y);
    if (xn && yn) { const nx = +x, ny = +y; if (nx !== ny) return nx < ny ? -1 : 1; }
    else if (xn !== yn) return xn ? -1 : 1;      // numerik < alfanumerik
    else if (x !== y) return x < y ? -1 : 1;
  }
  return ai.length === bi.length ? 0 : (ai.length < bi.length ? -1 : 1);
}
module.exports = { SEMVER_RE, compareSemver };
```

### 1.2 Validasi & resolusi versi klien

Kebijakan resolusi (paling eksplisit lebih dulu):

1. Ambil dari query `?versi=`. **Bila ada tapi malformed → balas `422`** (envelope error). Caller mengirim nilai eksplisit yang salah; munculkan agar bug klien ketahuan (klien tetap _fail-open_, jadi aman).
2. Bila query kosong → fallback ke header `X-Tuleh-Version` (best-effort, tidak memicu 422).
3. Bila keduanya kosong/malformed → **default aman = `versi_terbaru`** (anggap klien terbaru → `wajib=false`, `update_tersedia=false`). Ini menghindari memblokir klien tak dikenal **dan** menampilkan banner palsu.

Normalisasi ringan sebelum regex: `trim`, buang prefiks `v`/`V`, terima 2–3 segmen (`0.9` = `0.9.0`), pre-release/build metadata opsional. Batasi panjang (`max:64`) untuk cegah payload aneh/ReDoS.

**FormRequest** — validasi query, balas envelope `422` bila malformed:

```php
// app/Http/Requests/AppVersiRequest.php
<?php
namespace App\Http\Requests;

use App\Support\SemVer;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Http\Exceptions\HttpResponseException;

class AppVersiRequest extends FormRequest
{
    public function authorize(): bool { return true; } // endpoint publik

    protected function prepareForValidation(): void
    {
        if ($this->query('versi') !== null) {
            $this->merge(['versi' => ltrim(trim((string) $this->query('versi')), 'vV')]);
        }
    }

    public function rules(): array
    {
        return [
            'versi'    => ['nullable', 'string', 'max:64', 'regex:' . SemVer::REGEX],
            'platform' => ['nullable', 'in:windows,android'],
        ];
    }

    protected function failedValidation(Validator $validator): void
    {
        throw new HttpResponseException(response()->json([
            'success' => false,
            'data'    => null,
            'meta'    => null,
            'message' => 'Parameter versi tidak valid.',
            'errors'  => $validator->errors()->toArray(),
        ], 422)->header('Cache-Control', 'no-store'));
    }
}
```

### 1.3 Logika keputusan

```
wajib           = compare(client, versi_minimum) < 0
update_tersedia = compare(client, versi_terbaru) < 0
```

Klien menampilkan **BANNER hanya bila `update_tersedia && !wajib`**; saat `wajib=true`, layar penuh mengambil alih sehingga banner ditekan di sisi klien. Aturan "maks 1×/hari" untuk banner adalah tanggung jawab **klien**; server tidak menyimpan state harian. Versi klien tidak valid/tak dikenal → keduanya `false` (fail-open).

### 1.4 Objek `unduhan` + `ukuran`

Nama berkas mengikuti tag Release CI (`v<versi>`) dan **selalu** dari `versi_terbaru`:

- Windows: `Tuleh-Setup-<versi>.exe`
- Android: `Tuleh-<versi>-android.apk`

Base: `https://pos.tatreport.com/unduh/`. Server **selalu** mengirim **kedua** URL; klien memilih sesuai platformnya.

`ukuran` bersifat **opsional** dan bernilai tunggal (byte). Karena dua platform berbeda ukuran sementara response hanya punya satu field, endpoint menerima hint opsional `?platform=windows|android` untuk memilih ukuran yang tepat; tanpa itu `ukuran = null`. Ini tidak melanggar kontrak (yang wajib hanya `?versi=`) dan aman karena electron-updater membaca ukuran sebenarnya dari `latest.yml`, sedangkan Android dari `DownloadManager` — `ukuran` murni informatif.

### 1.5 Controller & Route

Controller memakai `AppVersiService` (sumber kebenaran versi; definisi lengkap di **§4**), yang membaca tabel `app_versi` dengan cache singkat.

```php
// app/Http/Controllers/AppVersiController.php
<?php
namespace App\Http\Controllers;

use App\Http\Requests\AppVersiRequest;
use App\Services\AppVersiService;
use Illuminate\Http\JsonResponse;

class AppVersiController extends Controller
{
    public function show(AppVersiRequest $request, AppVersiService $svc): JsonResponse
    {
        // Query tervalidasi (422 bila malformed) → fallback header → service fail-open ke terbaru.
        $client   = $request->query('versi') ?: $request->header('X-Tuleh-Version');
        $platform = $request->query('platform'); // opsional: windows|android

        return response()->json([
            'success' => true,
            'data'    => $svc->buildResponse($client, $platform),
            'meta'    => null,
            'message' => 'OK',
            'errors'  => null,
        ])
        ->header('Cache-Control', 'public, max-age=60')
        ->header('Vary', 'X-Tuleh-Version, Accept-Encoding');
    }
}
```

```php
// routes/api.php — endpoint publik: TANPA auth, TANPA middleware 426; throttle ringan.
Route::get('pos/v1/app/versi', [AppVersiController::class, 'show'])
    ->middleware('throttle:60,1'); // 60 req/menit/IP
```

Varian ringkas Node/Express (memakai `compareSemver`/`SEMVER_RE` dari §1.1; nilai versi dari sumber Anda):

```js
// versi.js
const express = require('express');
const router = express.Router();
const { SEMVER_RE, compareSemver } = require('./semver');

const LATEST  = process.env.TULEH_VERSI_TERBARU || '0.9.9';
const MIN     = process.env.TULEH_VERSI_MINIMUM || '0.9.0';
const BASE    = (process.env.TULEH_UNDUH_BASE || 'https://pos.tatreport.com/unduh').replace(/\/+$/, '');
const CATATAN = process.env.TULEH_CATATAN || 'Perbaikan bug dan peningkatan performa.';
const UKURAN  = { windows: Number(process.env.TULEH_UKURAN_WINDOWS) || null,
                  android: Number(process.env.TULEH_UKURAN_ANDROID) || null };

const envelope = (success, data, message, errors = null) => ({ success, data, meta: null, message, errors });

router.get('/api/pos/v1/app/versi', (req, res) => {
  let versi = String(req.query.versi || '').trim();
  if (versi && !SEMVER_RE.test(versi)) {
    return res.status(422).set('Cache-Control', 'no-store')
      .json(envelope(false, null, 'Parameter versi tidak valid.', { versi: ['Format semver tidak valid.'] }));
  }
  let client = versi || String(req.get('X-Tuleh-Version') || '').trim() || LATEST;
  if (!SEMVER_RE.test(client)) client = LATEST; // fallback header malformed → aman

  const wajib = compareSemver(client, MIN) < 0;
  const updateTersedia = compareSemver(client, LATEST) < 0;
  const platform = req.query.platform;

  const data = {
    wajib,
    update_tersedia: updateTersedia,
    versi_terbaru: LATEST,
    catatan: CATATAN,
    ukuran: (platform === 'windows' || platform === 'android') ? UKURAN[platform] : null,
    unduhan: {
      windows: { url: `${BASE}/Tuleh-Setup-${LATEST}.exe` },
      android: { url: `${BASE}/Tuleh-${LATEST}-android.apk` },
    },
  };

  res.set('Cache-Control', 'public, max-age=60');
  res.set('Vary', 'X-Tuleh-Version, Accept-Encoding');
  res.json(envelope(true, data, 'OK'));
});

module.exports = router;
```

### 1.6 Header cache & keandalan rollout

- **Sukses:** `Cache-Control: public, max-age=60` + `Vary: X-Tuleh-Version, Accept-Encoding`. Respons di-_key_ per versi klien (query berbeda = entri cache berbeda), jadi caching aman. `max-age` pendek (≤60 dtk) membatasi jeda saat menaikkan `versi_terbaru`/`versi_minimum` — **jangan** cache berjam-jam agar rollout paksa cepat menyebar.
- **Jangan** kirim `ETag`/`Last-Modified` panjang di sini; nilai berubah begitu konfigurasi dinaikkan.
- **422** (versi tidak valid) & **426** (versi kadaluarsa): `Cache-Control: no-store` — keputusan penegakan tak boleh ter-cache.
- `Content-Type: application/json; charset=utf-8`; selalu sertakan **kelima** kunci envelope.
- `catatan` dikembalikan **apa adanya** (Bahasa Indonesia), tanpa dipotong/di-escape berlebihan (klien menampilkannya sebagai teks polos).

### 1.7 Contoh JSON balasan

Asumsi: `versi_terbaru = "0.9.9"`, `versi_minimum = "0.9.0"`.

**A. Sudah terbaru** — `GET /app/versi?versi=0.9.9` → `200`

```json
{
  "success": true,
  "data": {
    "wajib": false,
    "update_tersedia": false,
    "versi_terbaru": "0.9.9",
    "catatan": "Perbaikan bug dan peningkatan performa.",
    "ukuran": null,
    "unduhan": {
      "windows": { "url": "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe" },
      "android": { "url": "https://pos.tatreport.com/unduh/Tuleh-0.9.9-android.apk" }
    }
  },
  "meta": null,
  "message": "OK",
  "errors": null
}
```

**B. Update opsional (banner)** — `GET /app/versi?versi=0.9.5&platform=windows` → `200`

```json
{
  "success": true,
  "data": {
    "wajib": false,
    "update_tersedia": true,
    "versi_terbaru": "0.9.9",
    "catatan": "Fitur baru: Display Pelanggan. Perbaikan sinkronisasi stok.",
    "ukuran": 84213760,
    "unduhan": {
      "windows": { "url": "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe" },
      "android": { "url": "https://pos.tatreport.com/unduh/Tuleh-0.9.9-android.apk" }
    }
  },
  "meta": null,
  "message": "OK",
  "errors": null
}
```

**C. Update wajib (layar penuh memblokir)** — `GET /app/versi?versi=0.8.2` → `200`

```json
{
  "success": true,
  "data": {
    "wajib": true,
    "update_tersedia": true,
    "versi_terbaru": "0.9.9",
    "catatan": "Pembaruan keamanan wajib. Silakan perbarui untuk melanjutkan.",
    "ukuran": null,
    "unduhan": {
      "windows": { "url": "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe" },
      "android": { "url": "https://pos.tatreport.com/unduh/Tuleh-0.9.9-android.apk" }
    }
  },
  "meta": null,
  "message": "OK",
  "errors": null
}
```

**D. Query malformed** — `GET /app/versi?versi=abc` → `422`

```json
{
  "success": false,
  "data": null,
  "meta": null,
  "message": "Parameter versi tidak valid.",
  "errors": { "versi": ["Format semver tidak valid."] }
}
```

**E. Kadaluarsa dari endpoint lain (426)** — mis. `GET /api/pos/v1/produk` dengan `X-Tuleh-Version: 0.8.2` → `426`

```json
{
  "success": false,
  "data": null,
  "meta": null,
  "message": "Versi aplikasi Anda sudah tidak didukung. Silakan perbarui untuk melanjutkan.",
  "errors": null
}
```

---

## 2. Middleware Versi Minimum (426)

Menyadap **semua** request `/api/pos/v1/*` (kecuali daftar pengecualian), membaca `X-Tuleh-Version`, dan membalas **HTTP 426** dengan envelope kontrak bila klien `< versi_minimum`. `versi_minimum` global (satu nilai untuk desktop + Android).

### 2.1 Prinsip inti

- **Satu keputusan, satu status.** `client < versi_minimum` → **selalu 426**, tidak pernah 200/401/403/4xx lain. Agar penyadap 426 di klien deterministik.
- **426 mendahului auth.** Dipasang **sebelum** middleware autentikasi, supaya endpoint ber-auth tak lebih dulu membalas 401 (yang akan menutupi 426).
- **Fail-open di server.** Header kosong/tak terkirim/tak bisa diparse → **jangan blokir**, teruskan. Fail-open server + fail-open klien = tidak ada dead-lock.
- **Perbandingan semver numerik** (via `App\Support\SemVer`), bukan string.
- **Konfigurasi runtime.** `versi_minimum` dibaca dari DB via `AppVersiService`; kill-switch & flag dari config → bisa dinaikkan/di-rollback tanpa deploy.

### 2.2 Alur keputusan (berurutan)

```
1. Kill-switch enforce=false?                     → next()  (nonaktif total)
2. Path termasuk PENGECUALIAN?                     → next()  (lolos)
3. X-Tuleh-Version kosong / tak ada?               → next()  (FAIL-OPEN)
4. Versi klien tak valid (tak bisa diparse)?       → next()  (FAIL-OPEN)
5. compare(client, versi_minimum) < 0 ?
     TIDAK (>= minimum)                            → next()  (lolos)
     YA                                            → BALAS 426 + envelope
```

Envelope 426 (persis kontrak, semua field ada), `Cache-Control: no-store`:

```json
{
  "success": false,
  "data": null,
  "meta": null,
  "message": "Versi aplikasi Anda sudah tidak didukung. Silakan perbarui untuk melanjutkan.",
  "errors": null
}
```

`message` diisi dari `config('tuleh.catatan_wajib')` (Bahasa Indonesia, teks polos, ditampilkan apa adanya). Opsional: sertakan header `X-Tuleh-Min-Version` & `X-Tuleh-Latest-Version` untuk observabilitas.

### 2.3 Daftar pengecualian (tidak boleh kena 426)

| Endpoint | Alasan |
|---|---|
| `GET /api/pos/v1/app/versi` | **WAJIB.** Justru saat usang klien harus bisa mengambil `versi_terbaru`, `catatan`, URL `unduhan`. Memblokir ini = dead-lock. Endpoint ini juga tanpa-auth. |
| `/ping`, `/healthz`, `/health`, `/status` | Probe uptime tak mengirim header (sudah fail-open), tapi dikecualikan eksplisit agar monitoring tak pernah menerima 426. |
| `/unduh/*` (jika sejalur) | Memblokir unduhan installer = dead-lock. Umumnya di host statis `pos.tatreport.com` **terpisah** dari gateway API, jadi biasanya **di luar** middleware ini. |
| Webhook/callback pihak-ketiga (mis. Midtrans) | Bukan klien Tuléh, tak mengirim `X-Tuleh-Version`. Fail-open sudah melindungi; kecualikan eksplisit bila ingin bersih. |
| `POST /auth/login` | **Kondisional — lihat di bawah.** |

**Pencocokan:** berdasarkan nama route bila tersedia; jika tidak, **suffix path** (`endsWith('/app/versi')`) agar tahan prefix `/api/pos/v1`.

**Apakah `/auth/login` dikecualikan?** Kekuatan penegakan sama baik login ditegakkan maupun tidak (klien tetap kena 426 pada panggilan bisnis pertama). **Rekomendasi: JANGAN kecualikan `/auth/login` secara permanen — tegakkan 426 di login juga**, karena klien modern menyadap 426 global termasuk di layar login, sehingga "tak bisa login" menjadi sinyal **"Update Wajib"** yang paling dini. **Namun** sediakan flag `enforce_login` (default `true`) dan **saat rollout perdana set `false`**: fitur penyadap-426 baru ditambahkan, sehingga masih banyak klien lama yang **belum paham 426** — bagi mereka 426 di login hanya tampak "Login gagal" tanpa penjelasan. Setelah telemetri menunjukkan populasi pra-426 kecil, balik `enforce_login` ke `true`. Risiko "tak bisa login sama sekali" diatasi lewat **kebijakan rollout**, bukan mengecualikan login selamanya.

### 2.4 Fail-open sisi server (wajib)

- Header **kosong/tak ada** → teruskan (jangan 426, jangan 400).
- Header **tak bisa diparse** → teruskan (jangan tebak, jangan blokir).
- **Jangan pernah** memperketat menjadi memblokir header hilang.
- Kill-switch `TULEH_ENFORCE_MIN_VERSION=false` mematikan seluruh penegakan secara instan saat darurat.

### 2.5 Keamanan rollout (menaikkan `versi_minimum` bertahap)

1. **Observasi dulu.** Log distribusi `X-Tuleh-Version` (counter per versi) 1–2 minggu sebelum menaikkan.
2. **Sadari paradoks kesadaran-426.** Klien di bawah versi pertama yang paham 426 melihat error generik, bukan layar update. Jendela penegakan mulus hanya `[versi-pertama-paham-426, versi_minimum)`. Dorong populasi pra-426 naik lewat banner `update_tersedia`, email, CS.
3. **Soft-then-hard.** Fase 1: rilis dengan `update_tersedia=true`, `wajib=false` (banner) selama grace. Fase 2: baru naikkan `versi_minimum`. Auto-update desktop memindahkan mayoritas pengguna sendiri.
4. **Bertahap kecil.** Satu langkah minor/patch, tunggu, amati rasio 426 & tiket CS. Nilai dari DB/remote-config → **rollback instan** tanpa redeploy.
5. **Jangan pernah `versi_minimum > versi_terbaru`.** Itu mengunci 100% pengguna. Tambahkan guard saat set (§4) & CI check.
6. **Pastikan target siap.** Naikkan `versi_minimum` hanya setelah versi target live dan `/unduh/*` melayani berkas benar (Range teruji, `latest.yml`+`.blockmap` ada). Memblokir user menuju installer 404 = bencana.
7. **Canary bila mungkin** (tenant beta/internal, jam sepi, CS siaga) sebelum global.
8. **Runbook rollback** tertulis: "set `versi_minimum` kembali ke X" + kill-switch, dapat dieksekusi < 1 menit.

### 2.6 Kode Laravel

```php
// app/Http/Middleware/EnforceMinimumVersion.php
<?php
namespace App\Http\Middleware;

use Closure;
use App\Support\SemVer;
use App\Services\AppVersiService;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnforceMinimumVersion
{
    private const HTTP_UPGRADE_REQUIRED = 426;

    public function __construct(private AppVersiService $svc) {}

    public function handle(Request $request, Closure $next): Response
    {
        // (1) Kill-switch global (rollback darurat).
        if (! config('tuleh.enforce', true)) {
            return $next($request);
        }
        // (2) Pengecualian.
        if ($this->isExcluded($request)) {
            return $next($request);
        }
        // (3)(4) Fail-open bila header kosong / tak valid.
        $client = trim((string) $request->header('X-Tuleh-Version', ''));
        if ($client === '' || ! SemVer::isValid($client)) {
            return $next($request);
        }
        // (5) versi klien < minimum → 426.
        $policy = $this->svc->policy();
        if (SemVer::compare($client, $policy['versi_minimum']) < 0) {
            return response()->json([
                'success' => false,
                'data'    => null,
                'meta'    => null,
                'message' => (string) config('tuleh.catatan_wajib'),
                'errors'  => null,
            ], self::HTTP_UPGRADE_REQUIRED, [
                'Cache-Control'          => 'no-store',
                'X-Tuleh-Min-Version'    => $policy['versi_minimum'],
                'X-Tuleh-Latest-Version' => $policy['versi_terbaru'],
            ]);
        }
        return $next($request);
    }

    private function isExcluded(Request $request): bool
    {
        $path = '/' . ltrim($request->path(), '/'); // mis. "api/pos/v1/app/versi"

        $always = ['/app/versi', '/ping', '/healthz', '/health', '/status'];
        foreach ($always as $suffix) {
            if (str_ends_with($path, $suffix)) return true;
        }
        // Login dikecualikan hanya saat flag rollout dimatikan.
        if (! config('tuleh.enforce_login', true) && str_ends_with($path, '/auth/login')) {
            return true;
        }
        return false;
    }
}
```

**Registrasi — Laravel 11+ (`bootstrap/app.php`):** pasang di **depan** grup `api` agar 426 mendahului auth.

```php
->withMiddleware(function (Illuminate\Foundation\Configuration\Middleware $middleware) {
    $middleware->api(prepend: [
        \App\Http\Middleware\EnforceMinimumVersion::class,
    ]);
})
```

**Registrasi — Laravel ≤10 (`app/Http/Kernel.php`):** entri **pertama** grup `api`, sebelum `auth:sanctum`.

```php
protected $middlewareGroups = [
    'api' => [
        \App\Http\Middleware\EnforceMinimumVersion::class, // paling atas
        \Illuminate\Routing\Middleware\ThrottleRequests::class.':api',
        \Illuminate\Routing\Middleware\SubstituteBindings::class,
    ],
];
```

> Route `app/versi` di-daftar tanpa grup 426 (§1.5), jadi cek versi sendiri tak pernah kena 426.

### 2.7 Kode Node / Express

```js
// middleware/enforceMinimumVersion.js
const { SEMVER_RE, compareSemver } = require('../semver');
const HTTP_UPGRADE_REQUIRED = 426;

const CONFIG = {
  enforce:      (process.env.TULEH_ENFORCE_MIN_VERSION || 'true') !== 'false', // kill-switch
  versiMinimum: process.env.TULEH_VERSI_MINIMUM || '0.0.0',
  versiTerbaru: process.env.TULEH_VERSI_TERBARU || '0.9.9',
  catatanWajib: process.env.TULEH_CATATAN_WAJIB ||
    'Versi aplikasi Anda sudah tidak didukung. Silakan perbarui untuk melanjutkan.',
  enforceLogin: (process.env.TULEH_ENFORCE_LOGIN || 'true') !== 'false', // rollout: 'false' dulu
};

const EXCLUDED = ['/app/versi', '/ping', '/healthz', '/health', '/status'];

function isExcluded(path) {
  const p = '/' + String(path).replace(/^\/+/, '');
  if (EXCLUDED.some((s) => p.endsWith(s))) return true;
  if (!CONFIG.enforceLogin && p.endsWith('/auth/login')) return true;
  return false;
}
const envelope = (message) => ({ success: false, data: null, meta: null, message, errors: null });

module.exports = function enforceMinimumVersion(req, res, next) {
  if (!CONFIG.enforce) return next();               // (1) kill-switch
  if (isExcluded(req.path)) return next();          // (2) pengecualian

  const client = (req.get('X-Tuleh-Version') || '').trim();
  if (client === '' || !SEMVER_RE.test(client)) return next(); // (3)(4) fail-open

  if (compareSemver(client, CONFIG.versiMinimum) < 0) {        // (5) < minimum → 426
    res.set('Cache-Control', 'no-store');
    res.set('X-Tuleh-Min-Version', CONFIG.versiMinimum);
    res.set('X-Tuleh-Latest-Version', CONFIG.versiTerbaru);
    return res.status(HTTP_UPGRADE_REQUIRED).json(envelope(CONFIG.catatanWajib));
  }
  return next();
};
```

**Registrasi:** pasang **sebelum** router bisnis & auth agar 426 mendahului 401.

```js
const enforceMinimumVersion = require('./middleware/enforceMinimumVersion');
app.use('/api/pos/v1', enforceMinimumVersion); // paling awal
app.use('/api/pos/v1', authMiddleware);        // auth setelahnya
app.use('/api/pos/v1', businessRouter);
```

### 2.8 Checklist kepatuhan (unik untuk §2)

- [ ] Dipasang **sebelum auth** agar 426 mendahului 401.
- [ ] `< versi_minimum` → **426** dengan envelope lima kunci; tidak pernah 200/4xx lain; `no-store`.
- [ ] Pengecualian mencakup `GET /app/versi` (wajib) + health probe; `/auth/login` via flag `enforce_login`.
- [ ] Header kosong/tak valid → **fail-open**; kill-switch `enforce` tersedia.

---

## 3. Proksi Unduhan `pos.tatreport.com`

Melayani berkas rilis di `https://pos.tatreport.com/unduh/{nama}` dengan **HTTP Range wajib** dan dukungan penuh **electron-updater** (`latest.yml` + `.exe` + `.blockmap` pada base path yang sama). Ganti placeholder `<OWNER>/tuleh-git` dengan repo GitHub rilis Anda.

### 3.0 Ringkasan opsi & rekomendasi

| Opsi | Cara | Range | Sembunyi origin | Repo privat | Kompleksitas | Rekomendasi |
|------|------|:----:|:---------------:|:-----------:|:-----------:|:-----------:|
| **A** | nginx `302 redirect` → GitHub Releases | Didelegasikan ke CDN GitHub | Tidak | Tidak | Sangat rendah | ✅ **DIPILIH** |
| **B1** | nginx `proxy_pass` ke GitHub + `Authorization` | Diteruskan lewat proxy | Ya | Ya (butuh Lua/sidecar) | Sedang–tinggi | Bila origin harus tersembunyi tanpa mirror |
| **B2** | Mirror aset ke disk saat rilis, serve statis | Native nginx | Ya | Ya | Sedang | ✅ Andal untuk repo privat |

**Kesimpulan:** mulai dengan **OPSI A** (paling sederhana; Range & CDN gratis dari GitHub; electron-updater mengikuti redirect). Naik ke **B2** hanya bila repo harus privat atau origin GitHub wajib disembunyikan. **B1** hanya bila Anda tidak mau menyimpan aset di disk.

Alur electron-updater yang harus didukung ketiga opsi:
1. Ambil `/unduh/latest.yml` → baca `version`, `path: Tuleh-Setup-<versi>.exe`, `sha512`, `size`.
2. Unduh `/unduh/Tuleh-Setup-<versi>.exe` **dengan Range** (verifikasi sha512).
3. Opsional ambil `/unduh/Tuleh-Setup-<versi>.exe.blockmap` untuk unduhan diferensial.

### 3.1 Prasyarat: DNS + TLS Let's Encrypt

**DNS** — arahkan subdomain ke server:
```
pos.tatreport.com.   A     <IP_SERVER>
; atau AAAA untuk IPv6
```

**TLS (certbot + plugin nginx):**
```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d pos.tatreport.com \
     --agree-tos -m dedefebrinasyh@gmail.com --no-eff-email
sudo certbot renew --dry-run   # uji auto-renew
```
> **JANGAN pernah menonaktifkan TLS untuk unduhan.** electron-updater menolak feed non-HTTPS, dan integritas biner bergantung pada TLS + sha512.

Header keamanan minimum (di `server {}` HTTPS):
```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

### 3.2 OPSI A — Redirect 302 ke GitHub Releases (DIREKOMENDASIKAN)

**Cara kerja Range:** nginx **tidak** menyentuh body. Ia membalas `302` dengan `Location:` ke aset GitHub `.../releases/latest/download/{nama}`. Klien **mengulang** request — lengkap dengan header `Range:` — ke URL redirect. GitHub men-302 lagi ke `objects.githubusercontent.com` (CDN) yang **mendukung Range native** dan mengembalikan `206 Partial Content`. Range bekerja end-to-end tanpa beban di server Anda.

**Whitelist regex wajib** (cegah open-proxy):
```
^(Tuleh-Setup-[0-9.]+\.exe(\.blockmap)?|latest\.yml|Tuleh-[0-9.]+-android\.apk)$
```

```nginx
server {
    listen 443 ssl http2;
    server_name pos.tatreport.com;

    ssl_certificate     /etc/letsencrypt/live/pos.tatreport.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pos.tatreport.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;

    location ~ ^/unduh/(?<berkas>[^/]+)$ {
        # Whitelist: hanya nama berkas rilis sah. 'return' di dalam 'if' AMAN (pengecualian resmi nginx).
        if ($berkas !~ "^(Tuleh-Setup-[0-9.]+\.exe(\.blockmap)?|latest\.yml|Tuleh-[0-9.]+-android\.apk)$") {
            return 404;
        }
        # 302 (BUKAN 301) agar klien selalu menanyakan ulang & mengikuti 'latest' terbaru.
        return 302 https://github.com/<OWNER>/tuleh-git/releases/latest/download/$berkas;
    }
    location /unduh { return 404; }
}

server { # Redirect HTTP → HTTPS
    listen 80;
    server_name pos.tatreport.com;
    return 301 https://$host$request_uri;
}
```

**Catatan Opsi A:**
- `releases/latest/download/{nama}` hanya menunjuk rilis **published** (bukan draft/pre-release). CI harus menandai Release `v<versi>` sebagai *latest* stabil.
- MIME, `Accept-Ranges`, `Content-Length` datang dari CDN GitHub — **tidak perlu** konfigurasi MIME di server Anda untuk opsi ini.
- Repo **wajib publik**. Untuk repo privat, gunakan Opsi B.
- Gunakan `302` (temporer), bukan `301` (permanen di-cache) — agar rilis berikutnya tetap terselesaikan ke *latest*.

### 3.3 OPSI B — Repo privat / sembunyikan origin GitHub

**B1 — Reverse-proxy dengan Authorization token.** Origin GitHub tak terlihat klien; nginx meneruskan body. Karena URL unduhan GitHub membalas `302` ke CDN bertanda-tangan, pakai pola `error_page` follow-redirect:

```nginx
server {
    listen 443 ssl http2;
    server_name pos.tatreport.com;

    ssl_certificate     /etc/letsencrypt/live/pos.tatreport.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pos.tatreport.com/privkey.pem;
    resolver 1.1.1.1 8.8.8.8 valid=300s;

    location ~ ^/unduh/(?<berkas>[^/]+)$ {
        if ($berkas !~ "^(Tuleh-Setup-[0-9.]+\.exe(\.blockmap)?|latest\.yml|Tuleh-[0-9.]+-android\.apk)$") {
            return 404;
        }
        proxy_pass https://github.com/<OWNER>/tuleh-git/releases/latest/download/$berkas;
        proxy_set_header Host github.com;
        proxy_set_header Authorization "";     # kosongkan untuk publik
        proxy_ssl_server_name on;
        proxy_intercept_errors on;
        error_page 301 302 307 = @ikuti_cdn;   # tangkap & ikuti redirect CDN
    }
    location @ikuti_cdn {
        internal;
        set $cdn $upstream_http_location;
        proxy_pass $cdn;
        proxy_set_header Host objects.githubusercontent.com;
        proxy_set_header Authorization "";     # JANGAN teruskan token ke CDN publik
        proxy_ssl_server_name on;
        # Range milik klien diteruskan otomatis → CDN balas 206.
    }
}
```

**Keterbatasan B1:** repo **benar-benar privat** tidak bisa hanya dengan config di atas — aset privat wajib lewat `GET https://api.github.com/repos/<OWNER>/tuleh-git/releases/assets/<asset_id>` dengan `Accept: application/octet-stream` + `Authorization: Bearer <PAT>`; `asset_id` dinamis per rilis, butuh resolusi (OpenResty/Lua atau sidecar). Untuk repo privat, **B2 lebih disarankan**. Simpan token sebagai env/file rahasia, **jangan** hardcode di config ter-commit. Bandwidth kini lewat server Anda (bukan CDN GitHub).

**B2 — Mirror aset ke disk saat rilis (paling andal untuk repo privat).** Saat CI mempublikasikan Release, salin aset ke `/var/www/unduh`; nginx menyajikannya **statis** (Range native, kendali MIME penuh, origin tersembunyi).

Langkah GitHub Actions (tambahkan setelah step publish Release di `.github/workflows/release.yml`):
```yaml
      - name: Mirror aset rilis ke pos.tatreport.com
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.DEPLOY_HOST }}
          username: ${{ secrets.DEPLOY_USER }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          target: "/var/www/unduh.incoming/"     # folder sementara (hindari serve setengah-tertulis)
          source: >-
            dist/Tuleh-Setup-*.exe,
            dist/Tuleh-Setup-*.exe.blockmap,
            dist/latest.yml,
            dist/Tuleh-*-android.apk
          strip_components: 1

      - name: Aktifkan mirror secara atomik
        uses: appleboy/ssh-action@v1.2.0
        with:
          host: ${{ secrets.DEPLOY_HOST }}
          username: ${{ secrets.DEPLOY_USER }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          script: |
            set -euo pipefail
            rsync -a --delete /var/www/unduh.incoming/ /var/www/unduh/
            chown -R www-data:www-data /var/www/unduh
            rm -rf /var/www/unduh.incoming
```

Alternatif: webhook `release` GitHub → server menarik dengan `gh` (verifikasi `X-Hub-Signature-256` HMAC-SHA256 lebih dulu), publikasi **atomik** (`unduh.incoming` → `rsync --delete`) agar electron-updater tak membaca `latest.yml` baru saat `.exe`-nya belum selesai tersalin.

Config nginx statis (Range native):
```nginx
server {
    listen 443 ssl http2;
    server_name pos.tatreport.com;

    ssl_certificate     /etc/letsencrypt/live/pos.tatreport.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pos.tatreport.com/privkey.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;

    location /unduh/ {
        alias /var/www/unduh/;
        autoindex off;                 # jangan bocorkan daftar berkas
        sendfile on;
        gzip off;                      # jaga Content-Length & sha512 tepat + Range utuh
        add_header Accept-Ranges bytes;
        location ~ ^/unduh/(?!Tuleh-Setup-[0-9.]+\.exe(\.blockmap)?$|latest\.yml$|Tuleh-[0-9.]+-android\.apk$) {
            return 404;                # whitelist (defense-in-depth)
        }
    }
    location = /unduh/ { return 404; }
}
```
> nginx mendukung `Range`/`206` **native** untuk berkas statis — tak perlu modul tambahan. `gzip off` di lokasi ini wajib agar `Content-Length` cocok dengan `size` di `latest.yml`.

### 3.4 Catatan MIME (khusus Opsi B2 statis; Opsi A memakai MIME dari CDN GitHub)

| Berkas | MIME yang benar | Alasan |
|--------|-----------------|--------|
| `.apk` | `application/vnd.android.package-archive` | Agar Android/DownloadManager mengenali paket instalasi |
| `latest.yml` | `text/yaml; charset=utf-8` | electron-updater mem-parsing sebagai teks; hindari `application/octet-stream` yang memicu unduh |
| `.exe` | `application/octet-stream` | Biner installer |
| `.blockmap` | `application/octet-stream` | JSON ter-gzip untuk diff |

```nginx
# di dalam location /unduh/ pada Opsi B2
types {
    application/vnd.android.package-archive  apk;
    text/yaml                                yml;
    application/octet-stream                 exe blockmap;
}
default_type application/octet-stream;
```
> **Jangan** paksa `Content-Disposition` pada `.yml`/`.blockmap` — electron-updater harus bisa membacanya inline.

### 3.5 Checklist keandalan (unik untuk §3)

- [ ] TLS aktif + auto-renew teruji; HTTP→HTTPS redirect.
- [ ] `latest.yml`, `Tuleh-Setup-<versi>.exe`, `.blockmap` **satu base path** `/unduh/`.
- [ ] Whitelist regex terpasang di **kedua** opsi (cegah open-proxy / path traversal).
- [ ] Range → `206` terverifikasi (`curl -r`) untuk `.exe` & `.apk`; `autoindex off`.
- [ ] (A) Release `v<versi>` = *latest* stabil (bukan draft/pre-release); repo publik.
- [ ] (B) Publikasi mirror **atomik**; token tak ter-hardcode; webhook verifikasi `X-Hub-Signature-256`; MIME & `gzip off` benar.
- [ ] `/unduh/*` **tanpa auth**, hanya melayani nama ter-whitelist.

---

## 4. Kebijakan & Pengelolaan Versi

Merancang **sumber kebenaran** untuk `versi_terbaru`, `versi_minimum`, `catatan`, dan `ukuran`, plus cara mengisinya otomatis saat rilis dan cara memaksa update (426).

### 4.0 Alur nilai

```
GitHub Release (CI, tag v<versi>)
        │  (a) PUSH: POST /admin/app-versi  ← versi_terbaru, catatan, ukuran_*
        ▼
┌─────────────────────────────┐        set manual oleh manusia
│  tabel app_versi (1 baris)  │◀──────  PUT /admin/app-versi/minimum ← versi_minimum
│  versi_terbaru / minimum /  │
│  catatan / ukuran_*         │
└─────────────┬───────────────┘
              │  dibaca via AppVersiService (cache 60s)
   ┌──────────┴───────────┐
   ▼                      ▼
GET /app/versi (§1)   Middleware 426 (§2)
(tanpa auth)          → 426 bila klien < versi_minimum
```

Pemisahan penting: **CI hanya menaikkan `versi_terbaru`** (menawarkan update, tidak memaksa). **`versi_minimum` hanya diubah manusia** (memaksa 426). Ini mencegah rilis rutin tanpa sengaja mengunci semua klien. URL unduhan **tidak disimpan** — diturunkan dari `versi_terbaru` + template di `config/tuleh.php` (§1.1).

### 4.1 Skema tabel `app_versi` + migrasi

Satu baris global (tidak per-platform). `ukuran_win`+`ukuran_android` disimpan terpisah; response memilih salah satu via `?platform=` (§1.4).

```php
// database/migrations/2026_08_06_000000_create_app_versi_table.php
<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('app_versi', function (Blueprint $table) {
            $table->id();
            $table->string('versi_terbaru', 32);                  // mis. "0.9.9"
            $table->string('versi_minimum', 32)->default('0.0.0');// "0.0.0" = tidak memaksa siapa pun
            $table->text('catatan')->nullable();                  // rilis notes, ditampilkan apa adanya
            $table->unsignedBigInteger('ukuran_win')->nullable();     // byte .exe
            $table->unsignedBigInteger('ukuran_android')->nullable(); // byte .apk
            $table->timestamp('updated_at')->nullable();
        });

        // Baris default aman (netral: tak menawarkan & tak memaksa update)
        DB::table('app_versi')->insert([
            'versi_terbaru'  => config('tuleh.default_versi_terbaru', '0.0.0'),
            'versi_minimum'  => '0.0.0',
            'catatan'        => config('tuleh.default_catatan', 'Tidak ada pembaruan.'),
            'ukuran_win'     => null,
            'ukuran_android' => null,
            'updated_at'     => now(),
        ]);
    }
    public function down(): void { Schema::dropIfExists('app_versi'); }
};
```

### 4.2 Model + Service

```php
// app/Models/AppVersi.php
<?php
use Illuminate\Database\Eloquent\Model;

class AppVersi extends Model
{
    protected $table = 'app_versi';
    const CREATED_AT = null;                 // hanya kelola updated_at
    protected $fillable = ['versi_terbaru','versi_minimum','catatan','ukuran_win','ukuran_android'];
    protected $casts = ['ukuran_win' => 'integer', 'ukuran_android' => 'integer'];

    /** Selalu kembalikan objek (baris pertama, atau default in-memory bila tabel kosong). */
    public static function current(): self
    {
        return static::query()->orderBy('id')->first() ?? new static([
            'versi_terbaru' => config('tuleh.default_versi_terbaru', '0.0.0'),
            'versi_minimum' => '0.0.0',
            'catatan'       => config('tuleh.default_catatan', 'Tidak ada pembaruan.'),
        ]);
    }
}
```

```php
// app/Services/AppVersiService.php
<?php
use Illuminate\Support\Facades\Cache;
use App\Models\AppVersi;
use App\Support\SemVer;

class AppVersiService
{
    private const CACHE_KEY = 'app_versi:current';

    /** Snapshot kebijakan (dicache singkat agar hemat query). */
    public function policy(): array
    {
        return Cache::remember(self::CACHE_KEY, config('tuleh.cache_ttl', 60), function () {
            $r = AppVersi::current();
            return [
                'versi_terbaru'  => $r->versi_terbaru,
                'versi_minimum'  => $r->versi_minimum ?: '0.0.0',
                'catatan'        => $r->catatan ?? config('tuleh.default_catatan'),
                'ukuran_win'     => $r->ukuran_win,
                'ukuran_android' => $r->ukuran_android,
            ];
        });
    }

    public function forget(): void { Cache::forget(self::CACHE_KEY); }

    /** true HANYA bila versi valid dan benar-benar di bawah minimum (fail-open selain itu). */
    public function isBelowMinimum(?string $clientVersion): bool
    {
        if (! SemVer::isValid($clientVersion)) return false; // fail-open
        return SemVer::compare($clientVersion, $this->policy()['versi_minimum']) < 0;
    }

    /** Bangun blok `data` untuk GET /app/versi sesuai kontrak. */
    public function buildResponse(?string $clientVersion, ?string $platform): array
    {
        $p = $this->policy();
        $valid = SemVer::isValid($clientVersion);

        $wajib          = $valid && SemVer::compare($clientVersion, $p['versi_minimum']) < 0;
        $updateTersedia = $valid && SemVer::compare($clientVersion, $p['versi_terbaru']) < 0;

        // Response punya SATU field `ukuran` (opsional). Isi sesuai ?platform= bila ada, else null.
        $ukuran = match ($platform) {
            'android' => $p['ukuran_android'],
            'windows' => $p['ukuran_win'],
            default   => null,
        };

        return [
            'wajib'           => $wajib,
            'update_tersedia' => $updateTersedia,
            'versi_terbaru'   => $p['versi_terbaru'],
            'catatan'         => $p['catatan'],
            'ukuran'          => $ukuran,
            'unduhan'         => [
                'windows' => ['url' => $this->url('nama_win', $p['versi_terbaru'])],
                'android' => ['url' => $this->url('nama_android', $p['versi_terbaru'])],
            ],
        ];
    }

    private function url(string $namaKey, string $versi): string
    {
        $base = rtrim(config('tuleh.unduh_base'), '/');
        $nama = str_replace('{versi}', $versi, config("tuleh.$namaKey"));
        return "$base/$nama";
    }
}
```

> `AppVersiService::buildResponse()` dipakai controller §1.5; `AppVersiService::isBelowMinimum()`/`policy()` dipakai middleware §2. Perbandingan memakai `App\Support\SemVer` (§1.1) — presedensi pre-release benar dan **fail-open** saat input tak valid.

### 4.3 Endpoint admin

`versi_terbaru` dinaikkan CI (tak menyentuh `versi_minimum`); `versi_minimum` dinaikkan manusia (memaksa 426). Keduanya idempoten & menolak menurunkan `versi_terbaru`.

```php
// app/Http/Controllers/Admin/AdminAppVersiController.php
<?php
use Illuminate\Http\Request;
use App\Models\AppVersi;
use App\Services\AppVersiService;
use App\Support\SemVer;

class AdminAppVersiController extends Controller
{
    private const SEMVER = 'regex:' . SemVer::REGEX;

    /** Dipanggil CI (opsi a). TIDAK menyentuh versi_minimum. */
    public function upsert(Request $request, AppVersiService $svc)
    {
        $data = $request->validate([
            'versi_terbaru'  => ['required','string','max:32', self::SEMVER],
            'catatan'        => ['nullable','string'],
            'ukuran_win'     => ['nullable','integer','min:0'],
            'ukuran_android' => ['nullable','integer','min:0'],
        ]);

        $row = AppVersi::current();
        if ($row->exists && SemVer::compare($data['versi_terbaru'], $row->versi_terbaru) < 0) {
            return $this->fail('versi_terbaru tidak boleh lebih rendah dari yang tersimpan.', 422);
        }
        $row->fill($data);
        $row->updated_at = now();
        $row->save();
        $svc->forget();

        return $this->ok($row, 'Versi terbaru diperbarui.');
    }

    /** Dipanggil MANUSIA. Menaikkan ini = memaksa 426 pada klien lama. */
    public function setMinimum(Request $request, AppVersiService $svc)
    {
        $data = $request->validate(['versi_minimum' => ['required','string','max:32', self::SEMVER]]);
        $row = AppVersi::current();

        // GUARD KRITIS: minimum tak boleh melampaui versi_terbaru, kalau tidak SEMUA klien
        // (termasuk yang terbaru) kena 426 tanpa jalan keluar.
        if (SemVer::compare($data['versi_minimum'], $row->versi_terbaru) > 0) {
            return $this->fail(
                "versi_minimum ({$data['versi_minimum']}) tidak boleh melebihi versi_terbaru ({$row->versi_terbaru}).",
                422
            );
        }
        $row->versi_minimum = $data['versi_minimum'];
        $row->updated_at = now();
        $row->save();
        $svc->forget();

        return $this->ok($row, 'Versi minimum diperbarui. Klien di bawah versi ini akan dipaksa memperbarui (426).');
    }

    private function ok($data, string $msg)  { return response()->json(['success'=>true,'data'=>$data,'meta'=>null,'message'=>$msg,'errors'=>null]); }
    private function fail(string $msg, int $c){ return response()->json(['success'=>false,'data'=>null,'meta'=>null,'message'=>$msg,'errors'=>null], $c); }
}
```

Auth admin (token rahasia, waktu-konstan, wajib TLS):

```php
// app/Http/Middleware/AdminTokenAuth.php
<?php
use Closure;

class AdminTokenAuth
{
    public function handle($request, Closure $next)
    {
        $expected = (string) config('tuleh.admin_token');
        $given    = (string) $request->bearerToken();

        if ($expected === '' || $given === '' || ! hash_equals($expected, $given)) {
            return response()->json([
                'success'=>false,'data'=>null,'meta'=>null,'message'=>'Tidak diizinkan.','errors'=>null,
            ], 401);
        }
        return $next($request);
    }
}
```

Rute:

```php
// routes/api.php
Route::prefix('pos/v1')->group(function () {
    // Publik, tanpa auth, TANPA middleware 426 (pintu darurat):
    Route::get('app/versi', [AppVersiController::class, 'show'])->middleware('throttle:60,1');

    // Admin (token rahasia + throttle):
    Route::prefix('admin')->middleware(['admin.token', 'throttle:20,1'])->group(function () {
        Route::post('app-versi',        [AdminAppVersiController::class, 'upsert']);     // CI
        Route::put('app-versi/minimum', [AdminAppVersiController::class, 'setMinimum']); // manual
    });

    // Endpoint bisnis lain WAJIB lewat gerbang versi minimum (§2):
    Route::middleware(['auth:sanctum'])->group(function () {
        // ... produk, transaksi, laporan, dst.  (EnforceMinimumVersion sudah di-prepend ke grup api)
    });
});
```

### 4.4 Auto-isi `versi_terbaru` + `catatan` saat rilis

**Opsi (a) — PUSH dari CI (REKOMENDASI).** Setelah Release terbit, satu job memanggil `POST /admin/app-versi` dengan token rahasia; `catatan` dari release notes, `ukuran_*` dari ukuran aset.

```yaml
# .github/workflows/release.yml (job tambahan, jalan setelah aset ter-upload)
  publish-versi:
    needs: [build-windows, build-android]   # sesuaikan dengan job build Anda
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - name: Susun payload dari release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          VERSI="${GITHUB_REF_NAME#v}"                 # v0.9.9 -> 0.9.9
          NOTES=$(gh release view "v$VERSI" --json body      -q '.body' -R "$GITHUB_REPOSITORY")
          SIZE_WIN=$(gh release view "v$VERSI" --json assets  -q '.assets[] | select(.name=="Tuleh-Setup-'"$VERSI"'.exe") | .size' -R "$GITHUB_REPOSITORY")
          SIZE_APK=$(gh release view "v$VERSI" --json assets  -q '.assets[] | select(.name=="Tuleh-'"$VERSI"'-android.apk") | .size' -R "$GITHUB_REPOSITORY")
          jq -n --arg v "$VERSI" --arg c "$NOTES" \
                --argjson w "${SIZE_WIN:-null}" --argjson a "${SIZE_APK:-null}" \
                '{versi_terbaru:$v, catatan:$c, ukuran_win:$w, ukuran_android:$a}' > payload.json

      - name: Kirim ke server (retry ringan)
        run: |
          VERSI="${GITHUB_REF_NAME#v}"
          for i in 1 2 3; do
            curl -fsS --max-time 20 -X POST \
              "https://tatreport.com/api/pos/v1/admin/app-versi" \
              -H "Authorization: Bearer ${{ secrets.APP_VERSI_ADMIN_TOKEN }}" \
              -H "Content-Type: application/json" \
              -H "X-Tuleh-Version: $VERSI" \
              --data @payload.json && exit 0
            sleep $((i*5))
          done
          echo "Gagal mengabari server versi" >&2; exit 1
```

Butuh satu GitHub Secret: `APP_VERSI_ADMIN_TOKEN` (sama dengan `env('APP_VERSI_ADMIN_TOKEN')` di server).

**Opsi (b) — PULL: server menarik "latest release" dari GitHub API (dijadwalkan ~15 mnt).**

```php
// app/Console/Commands/SyncVersiFromGithub.php
<?php
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;
use App\Models\AppVersi;
use App\Services\AppVersiService;
use App\Support\SemVer;

class SyncVersiFromGithub extends Command
{
    protected $signature = 'tuleh:sync-versi';

    public function handle(AppVersiService $svc): int
    {
        $repo = config('tuleh.gh_repo'); // "<OWNER>/tuleh-git"
        $res = Http::withToken(config('tuleh.gh_token'))     // token WAJIB bila repo privat / hindari rate limit
            ->acceptJson()->timeout(15)
            ->get("https://api.github.com/repos/{$repo}/releases/latest");

        if (! $res->ok()) { $this->error('GitHub API gagal'); return self::SUCCESS; } // fail-open

        $tag    = ltrim($res->json('tag_name'), 'v');
        $notes  = $res->json('body');
        $assets = collect($res->json('assets'));
        $win = $assets->firstWhere('name', "Tuleh-Setup-{$tag}.exe")['size']   ?? null;
        $apk = $assets->firstWhere('name', "Tuleh-{$tag}-android.apk")['size'] ?? null;

        $row = AppVersi::current();
        if (SemVer::compare($tag, $row->versi_terbaru) > 0) {   // jangan pernah turunkan
            $row->fill(['versi_terbaru'=>$tag, 'catatan'=>$notes, 'ukuran_win'=>$win, 'ukuran_android'=>$apk]);
            $row->updated_at = now();
            $row->save();
            $svc->forget();
            $this->info("Versi diperbarui ke $tag");
        }
        return self::SUCCESS;
    }
}
```

**Rekomendasi: pakai (a) sebagai mekanisme utama** — instan, tanpa dependensi runtime, cocok dengan alur "desktop+android rilis bersamaan". Jadikan (b) opsional sebagai **rekonsiliasi** (jadwal jarang) untuk menambal kasus job (a) gagal.

| Aspek | (a) Push dari CI | (b) Pull dari GitHub API |
|---|---|---|
| Ketergantungan runtime | Tidak ada | Bergantung GitHub API tiap sync |
| Rate limit | Tidak relevan | 60/jam tanpa token; butuh token utk privat |
| Ketepatan waktu | Instan saat rilis | Tertunda hingga siklus jadwal |
| Rahasia dibutuhkan | 1 GitHub Secret | 1 token GitHub di server |

### 4.5 Kapan menaikkan `versi_minimum` (→ memaksa 426)

Naikkan **hanya** saat klien lama benar-benar tidak boleh berjalan lagi:

- **Perubahan kontrak API breaking** yang membuat klien lama rusak (field dihapus, format transaksi berubah).
- **Perbaikan keamanan** yang tak boleh dilewati (kebocoran, auth bypass).
- **Migrasi data tidak kompatibel** dengan klien lama.
- **Bug fatal** di jalur uang (kasir/QRIS/struk) yang bisa merugikan pengguna.

Untuk rilis fitur/perbaikan biasa: **jangan** naikkan `versi_minimum`. Cukup `versi_terbaru` naik (CI) → klien dapat **banner** opsional, bukan 426. Set `versi_minimum` = versi rilis yang memperbaiki masalah, dan **tidak pernah** melebihi `versi_terbaru`.

### 4.6 Nilai default aman bila tabel kosong

- Migrasi menyeed satu baris netral (`versi_minimum = 0.0.0`).
- Andai baris hilang, `AppVersi::current()` mengembalikan objek in-memory default — endpoint tetap `200`, `wajib=false`, `update_tersedia=false`. **Tidak ada klien terblokir.**
- `versi_minimum` default `0.0.0` → `isBelowMinimum()` selalu `false` → middleware tak pernah 426 sebelum admin sengaja menaikkannya.
- Semua jalur cek/DB gagal bersikap **fail-open** (server tak pernah mengunci pengguna karena kesalahan internal).

---

## 5. Keamanan

Server harus benar & andal walau klien sudah _fail-open_. Semua kontrol menegakkan kontrak (envelope wajib, satu `versi_terbaru`/`versi_minimum` global, TLS wajib) tanpa menambah field baru.

### 5.1 Rate-limit `/app/versi` (publik, tanpa auth)

Titik abuse paling mudah. Trafik sah sangat rendah (klien cek saat start + foreground, throttle 30 menit), jadi batas boleh ketat.

- **Kunci per-IP klien nyata.** Di belakang proxy/Cloudflare, ambil IP dari header tepercaya (`CF-Connecting-IP`, atau `X-Forwarded-For` **hanya** bila dari proxy tepercaya). Jangan percaya `X-Forwarded-For` mentah dari internet.
- **Batas contoh:** 60 req/menit/IP. Lewat batas → **429** + `Retry-After: <detik>`, tetap dalam envelope `{success:false, message:"Terlalu banyak permintaan. Coba lagi nanti.", data:null, meta:null, errors:null}`.
- **Cache jawaban.** `Cache-Control: public, max-age=60` + cache di edge/CDN dengan key `versi` (§1.6).
- **Batas global** (token bucket seluruh endpoint) sebagai jaring anti-DDoS.
- Tidak mengembalikan data sensitif → native app tak butuh CORS longgar.

### 5.2 Validasi ketat query `versi` & header `X-Tuleh-Version`

Bandingkan **numerik/semver**, bukan string (syarat kebenaran, bukan sekadar keamanan).

- **Batasi panjang lebih dulu** (mis. `max:64`) untuk cegah ReDoS, lalu cocokkan regex ber-anchor (`SemVer::REGEX`, §1.1). Untuk versi rilis produksi yang selalu `X.Y.Z`, pola ketat ber-batas berikut aman & ReDoS-safe: `^(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,4})$`.
- `versi` **tidak cocok/kosong** pada `/app/versi` → **422** (§1.7 D). Klien _fail-open_ mengabaikannya; server tetap menolak input kotor.
- `X-Tuleh-Version` pada endpoint lain divalidasi pola sama di **middleware 426** (§2). **Hilang/malformed → jangan paksa 426** (fail-open) — perlakukan seperti klien tanpa versi. **Jangan pernah** memakai nilai header mentah dalam query SQL, path file, atau log tanpa sanitasi.
- Tegakkan invarian `versi_minimum <= versi_terbaru`; klien diblokir **hanya** bila `versi < versi_minimum` (`versi == versi_minimum` **boleh** jalan).

### 5.3 Whitelist nama berkas proksi `/unduh/{nama}` (cegah SSRF, path traversal, open-redirect)

Kontrol paling kritikal. Server **tidak boleh** menerima URL/host dari klien; hanya **nama berkas** yang dipetakan ke rilis GitHub dengan template tetap di sisi server.

- **Whitelist eksak (case-sensitive), tolak selain ini:**
  - `^Tuleh-Setup-(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,4})\.exe$`
  - `…\.exe\.blockmap$`
  - `^Tuleh-(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,4})-android\.apk$`
  - `^latest\.yml$`
- **Tolak** nama yang mengandung `/`, `\`, `..`, byte null, atau `%`. Decode persis **satu kali**; bila hasil ≠ input asli → tolak (cegah double-encoding `%2e%2e`).
- **URL upstream dibangun server**, hanya dari template tetap + versi tervalidasi (diambil dari nama berkas; untuk `latest.yml` = `versi_terbaru`): `https://github.com/<OWNER>/tuleh-git/releases/download/v<versi>/<nama>`. Host upstream **di-pin** ke `github.com` / `objects.githubusercontent.com`. Ikuti redirect **hanya** ke host allowlist; verifikasi TLS aktif. Ini menutup SSRF & open-redirect.
- **Dukung HTTP Range** (wajib electron-updater & resume APK): teruskan `Range`, kembalikan `206` dengan `Accept-Ranges: bytes`, `Content-Range`, `Content-Length` benar. Jangan runtuhkan Range menjadi 200 penuh.
- **Content-Type eksplisit** + `X-Content-Type-Options: nosniff` (§3.4).
- **Cache-Control:** biner ber-versi immutable → `public, max-age=31536000, immutable`. **`latest.yml` harus `no-cache`/revalidate** agar electron-updater melihat rilis baru.
- Nama tak di whitelist → **404** (bukan 400 verbose), tanpa membocorkan struktur path.

### 5.4 Proteksi endpoint admin

- **Auth + role.** Token bearer rahasia **wajib** (§4.3, `hash_equals` waktu-konstan) + pengecekan role bila relevan; namespace admin terpisah, guard berbeda dari POS.
- **Validasi** payload semver ketat + tegakkan `versi_minimum <= versi_terbaru`; tolak `422` bila melanggar.
- **Rate-limit** ketat (mis. 20/menit) + **audit log** (siapa, kapan, nilai lama→baru). Perubahan `versi_minimum` berisiko tinggi (bisa mengunci semua klien lama).

### 5.5 TLS wajib

- **HSTS:** `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload` di `tatreport.com` & `pos.tatreport.com`.
- Paksa HTTPS (redirect/tolak). Sertifikat CA valid. **Jangan pernah** menonaktifkan verifikasi TLS di klien maupun saat proksi ke upstream.
- **Integritas berlapis:** electron-updater memverifikasi `sha512` dari `latest.yml` (jadi `latest.yml` tak boleh dilayani lewat kanal yang bisa dipalsukan). APK di-sign keystore rilis (same-signature update). TLS + sha512 + tanda tangan = tiga lapis.

### 5.6 Jangan bocorkan info sensitif di 426 (dan error lain)

- Body 426 cukup envelope lima kunci dengan `message` teks aman Bahasa Indonesia.
- **Jangan** sertakan stack trace, host internal, versi framework, query/DB error, path server, token, atau data pengguna. `message` ditampilkan **apa adanya** oleh klien → pastikan **teks polos** (tanpa HTML/markup).
- 426 **tidak perlu** memuat URL unduhan; klien membuka layar wajib lalu memanggil `/app/versi` untuk URL. Body 426 minimal.
- Handler error generik seluruh app agar 5xx tak membocorkan detail; log rinci hanya sisi server.

---

## 6. Verifikasi & Uji

Base API: `https://tatreport.com/api/pos/v1` — unduhan: `https://pos.tatreport.com/unduh`. Ganti `$TOKEN` dengan bearer valid. Asumsi: `versi_terbaru = 0.9.9`, `versi_minimum = 0.9.0`.

### 6.1 Blok perintah `curl`

```bash
# (A) Cek versi — SUDAH TERBARU (harus: wajib false, update_tersedia false)
curl -sS -H "X-Tuleh-Version: 0.9.9" \
  "https://tatreport.com/api/pos/v1/app/versi?versi=0.9.9" | jq

# (B) Cek versi — UPDATE OPSIONAL (harus: wajib false, update_tersedia true)
curl -sS "https://tatreport.com/api/pos/v1/app/versi?versi=0.9.5" | jq '.data | {wajib, update_tersedia, versi_terbaru}'

# (C) Cek versi — WAJIB (< minimum → wajib true)
curl -sS "https://tatreport.com/api/pos/v1/app/versi?versi=0.8.5" | jq '.data | {wajib, update_tersedia}'

# (D) /app/versi TANPA auth → harus 200 (bukan 401/403)
curl -sS -o /dev/null -w "%{http_code}\n" "https://tatreport.com/api/pos/v1/app/versi?versi=0.9.9"

# (E) 426 dari ENDPOINT BIASA dengan klien lama (message aman, tanpa stack trace)
curl -sS -i -H "Authorization: Bearer $TOKEN" -H "X-Tuleh-Version: 0.8.0" \
  "https://tatreport.com/api/pos/v1/tokos"          # → HTTP 426 + {success:false, message:"...perbarui..."}

# (F) Klien terbaru TIDAK kena 426
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOKEN" -H "X-Tuleh-Version: 0.9.9" \
  "https://tatreport.com/api/pos/v1/tokos"          # → bukan 426

# (G) latest.yml (feed electron-updater)
curl -sSL "https://pos.tatreport.com/unduh/latest.yml"   # → version, path: Tuleh-Setup-0.9.9.exe, sha512, size

# (H) HTTP Range .exe → HARUS 206 + Content-Range (-L mengikuti redirect Opsi A)
curl -sSL -r 0-1023 -o /dev/null -D - "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe" | \
  grep -Ei 'HTTP/|Content-Range|Accept-Ranges|Content-Length'   # → 206, Content-Range: bytes 0-1023/<total>, len 1024

# (I) blockmap ada di direktori yang sama
curl -sIL "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe.blockmap" | grep -i 'HTTP/'   # → 200

# (J) APK Content-Type & Range
curl -sSL -r 0-4095 -o /dev/null -D - "https://pos.tatreport.com/unduh/Tuleh-0.9.9-android.apk" | \
  grep -Ei 'HTTP/|Content-Type|Content-Range'   # → Content-Type: application/vnd.android.package-archive

# (K) Verifikasi integritas end-to-end (cocokkan sha512 dari latest.yml)
curl -sL "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe" -o /tmp/s.exe
openssl dgst -sha512 -binary /tmp/s.exe | base64 -w0   # bandingkan dengan field sha512 di latest.yml

# --- Uji keamanan (harus DITOLAK) ---
curl -sS -i "https://pos.tatreport.com/unduh/..%2f..%2fetc%2fpasswd" | grep -i 'HTTP/'   # → 404
curl -sS -i "https://pos.tatreport.com/unduh/evil.sh"                | grep -i 'HTTP/'   # → 404
curl -sS -i "https://tatreport.com/api/pos/v1/app/versi?versi=not-a-version"             # → 422
for i in $(seq 1 80); do \
  curl -s -o /dev/null -w "%{http_code}\n" \
  "https://tatreport.com/api/pos/v1/app/versi?versi=0.9.9"; done | sort | uniq -c        # → sebagian 429 + Retry-After
```

### 6.2 Matriks uji

Aturan: **diblokir** hanya bila `versi < versi_minimum`; `update_tersedia` bila `versi < versi_terbaru`; perbandingan **semver numerik** (`0.10.0 > 0.9.9`).

| Skenario | Header / Param | Balasan server | Hasil di app |
|---|---|---|---|
| **Terbaru** | `?versi=0.9.9` | `200` `{wajib:false, update_tersedia:false, versi_terbaru:"0.9.9"}` | Tak ada banner/layar; jalan normal |
| **Update opsional** | `?versi=0.9.5` (≥ min, < terbaru) | `200` `{wajib:false, update_tersedia:true, catatan, unduhan}` | **Banner**; bisa **Tunda** (maks 1×/hari); tidak memblokir |
| **Wajib (start)** | `?versi=0.8.0` (< min) | `200` `{wajib:true, update_tersedia:true, catatan, unduhan}` | **Layar penuh memblokir**; tombol Perbarui; tak bisa ditutup |
| **Wajib (426)** | `X-Tuleh-Version: 0.8.0` di endpoint biasa | `426` `{success:false, message:"...perbarui", data:null}` | Interseptor 426 → layar wajib, `message` apa adanya; lalu panggil `/app/versi` |
| **Offline / fail-open** | Timeout / `5xx` | (tak ada balasan valid) | **Fail-open:** app tetap jalan; cek diulang nanti (throttle 30 mnt) |
| **Batas minimum** | `?versi=0.9.0` (== min) | `200` `{wajib:false, update_tersedia:true}` | Tepat ambang **tidak diblokir**; banner opsional |
| **Downgrade** | `?versi=1.5.0` (> terbaru) | `200` `{wajib:false, update_tersedia:false}` | Tak diblokir, tak ada banner; server tak memaksa turun |
| **`versi` invalid** | `?versi=not-a-version` | `422` envelope `errors.versi` | Klien fail-open mengabaikan; input kotor ditolak |
| **Nama unduhan di luar whitelist / traversal** | `/unduh/..%2f..`, `/unduh/evil.sh` | `404`, tanpa bocor path | SSRF/traversal gagal |
| **Rate-limit `/app/versi`** | > 60 req/menit/IP | `429` + `Retry-After` | Klien fail-open, coba lagi setelah `Retry-After` |
| **Admin ubah versi tanpa token** | tanpa bearer/role | `401` | Konfigurasi tak berubah; teraudit |

### 6.3 Acceptance criteria & checklist siap-rilis

- [ ] `/app/versi` **tanpa auth** → `200` (bukan 401/403), dan **tidak pernah** membalas 426.
- [ ] `?versi=0.9.9` → `wajib=false, update_tersedia=false`; `?versi=0.9.8` → banner; `?versi=0.8.5` → wajib.
- [ ] Respons **selalu** memuat `data.unduhan.windows.url` & `data.unduhan.android.url` → `.../Tuleh-Setup-<versi>.exe` & `.../Tuleh-<versi>-android.apk`.
- [ ] Semua respons JSON mengikuti envelope **lima kunci** `{success, data, meta, message, errors}`; semua teks Bahasa Indonesia.
- [ ] Endpoint terproteksi dengan `X-Tuleh-Version: 0.8.0` → `426`; `0.9.9` → bukan 426; **tanpa** header → bukan 426 (fail-open).
- [ ] `?versi=bukan-semver` → **422** (bukan 500); `catatan` dikembalikan apa adanya.
- [ ] `latest.yml` `200` memuat `path:` & `sha512:`; `.exe`/`.apk` Range → `206` + `Content-Range`; `.blockmap` `200`; semua satu base path `/unduh/` via TLS.
- [ ] `versi_minimum <= versi_terbaru` divalidasi; nama berkas cocok persis tag Release CI.
- [ ] Uji unit `SemVer::compare`: `0.9.9 vs 0.10.0` (→ -1), `1.0.0 vs 1.0.0-rc.1` (→ 1), `1.0.0-alpha.2 vs 1.0.0-alpha.10` (→ -1), input kosong/`v0.9.0`/2-segmen. Uji integrasi endpoint + middleware 426.
- [ ] Mengubah `versi_minimum`/`versi_terbaru` lewat DB/admin mengubah perilaku **tanpa deploy ulang**.

---

## 7. Prompt Implementasi (siap tempel)

````
Anda adalah backend engineer/AI coding agent. Implementasikan SEMUA sisi server untuk fitur
Auto-Update aplikasi "Tuléh POS". Aplikasi ini dirilis dalam dua platform (Windows .exe via
electron-updater, dan Android .apk) dengan NOMOR VERSI SELALU SAMA dan dirilis bersamaan.
Ikuti kontrak di bawah PERSIS. Semua teks yang ditampilkan ke pengguna WAJIB Bahasa Indonesia.

Stack ini FRAMEWORK-AGNOSTIC: sesuaikan dengan stack Anda. Contoh mengacu ke Laravel
(PHP), tetapi silakan gunakan framework/bahasa apa pun. Yang WAJIB identik adalah:
kontrak HTTP, bentuk envelope respons, nama berkas, dan perilaku Range/latest.yml.

================================================================================
KONTEKS SINGKAT
================================================================================
- Server = MOVERA POS API, base URL https://tatreport.com, prefix /api/pos/v1 (kemungkinan Laravel).
- File biner unduhan dilayani di host terpisah: https://pos.tatreport.com/unduh/{nama-berkas}.
- Klien mengirim header "X-Tuleh-Version: <semver>" pada SEMUA request (mis. "0.9.9").
  Gateway lokal Go klien sudah meneruskan header ini; server tinggal membacanya.
- Auth: Bearer token untuk endpoint umum. TAPI endpoint /app/versi TANPA auth.
- Envelope respons WAJIB (berlaku untuk SEMUA respons JSON di /api/pos/v1):
  {
    "success": bool,
    "data": {...}|null,
    "meta": null,
    "message": string,
    "errors": object|null
  }

================================================================================
KONTRAK 1 — ENDPOINT CEK VERSI (TANPA AUTH)
================================================================================
GET /api/pos/v1/app/versi?versi=<semver>

- Query "versi" = versi klien saat ini (mis. 0.9.8). Boleh juga dibaca dari header
  X-Tuleh-Version bila query tidak ada; bila keduanya ada, utamakan query "versi".
- TIDAK memerlukan Bearer token (endpoint publik).
- Bandingkan versi klien terhadap dua nilai konfigurasi GLOBAL (bukan per-platform):
    * versi_terbaru   (mis. "0.9.9")  → versi rilis terbaru yang tersedia
    * versi_minimum   (mis. "0.9.0")  → versi minimum yang masih boleh dipakai
  Aturan (gunakan perbandingan SEMVER yang benar, bukan perbandingan string):
    * wajib            = (versi_klien < versi_minimum)
    * update_tersedia  = (versi_klien < versi_terbaru)
- Balasan sukses (HTTP 200), envelope success=true, data:
  {
    "wajib": bool,              // true  → klien tampilkan LAYAR PENUH memblokir (tak bisa ditutup)
    "update_tersedia": bool,    // true & !wajib → klien tampilkan BANNER (bisa ditunda, maks 1x/hari)
    "versi_terbaru": "0.9.9",
    "catatan": "teks rilis singkat Bahasa Indonesia",  // ditampilkan APA ADANYA di layar update
    "ukuran": 84213760,         // byte, OPSIONAL (klien tak wajib pakai; boleh dihilangkan/null)
    "unduhan": {
      "windows": { "url": "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe" },
      "android": { "url": "https://pos.tatreport.com/unduh/Tuleh-0.9.9-android.apk" }
    }
  }
- Server SELALU mengirim KEDUA url (windows & android). Klien memilih sesuai platformnya sendiri.
- KEBIJAKAN VERSI: cukup SATU versi_terbaru global + SATU versi_minimum global. TIDAK ADA
  logika versi per-platform. Hanya URL unduhan yang berbeda per platform.
- Konfigurasi versi_terbaru, versi_minimum, catatan, ukuran, dan pola URL unduhan HARUS mudah
  diubah admin (env var / tabel config / admin panel) TANPA deploy ulang kode.
- Validasi input: bila query "versi" bukan semver valid, JANGAN 500. Perlakukan sebagai
  "versi sangat lama" (anggap update_tersedia=true, evaluasi wajib sesuai versi_minimum), atau
  balas envelope error yang rapi (success=false, message Bahasa Indonesia). Pilih yang aman.

================================================================================
KONTRAK 2 — SEMANTIK HTTP 426 (BERLAKU DI SEMUA ENDPOINT)
================================================================================
- Di SEMUA endpoint /api/pos/v1/* (kecuali /app/versi), baca header X-Tuleh-Version.
- Bila X-Tuleh-Version < versi_minimum (semver), TOLAK request dengan HTTP 426 (Upgrade Required)
  DAN badan envelope:
    { "success": false, "data": null, "meta": null,
      "message": "Versi aplikasi Anda sudah tidak didukung. Silakan perbarui untuk melanjutkan.",
      "errors": null }
  Klien menyadap status 426 → membuka layar update WAJIB dan menampilkan "message" apa adanya.
- Bila header X-Tuleh-Version TIDAK ADA: JANGAN paksa 426 (fail-open) — layani normal, ATAU
  tangani sesuai kebijakan keamanan Anda, tetapi jangan membuat klien lama tanpa header langsung mati.
- Implementasikan sebagai MIDDLEWARE global (mis. di Laravel: middleware yang di-attach ke grup
  route /api/pos/v1 kecuali /app/versi) supaya konsisten dan tidak perlu diulang per-controller.
- Endpoint /app/versi sendiri TIDAK boleh mengembalikan 426 (harus selalu bisa diakses).

================================================================================
KONTRAK 3 — LAYANAN BERKAS UNDUHAN (WAJIB DUKUNG HTTP RANGE)
================================================================================
Base: https://pos.tatreport.com/unduh/{nama-berkas}   (WAJIB HTTPS; JANGAN pernah nonaktifkan TLS)

Berkas berasal dari GitHub Release (dibuat CI .github/workflows/release.yml, tag v<versi>).
Untuk setiap versi <versi> (mis. 0.9.9), path berikut HARUS dilayani di direktori yang SAMA:
  Windows:
    - Tuleh-Setup-<versi>.exe
    - Tuleh-Setup-<versi>.exe.blockmap
    - latest.yml
  Android:
    - Tuleh-<versi>-android.apk

Persyaratan teknis WAJIB:
  1) Dukung HTTP Range request (header "Range: bytes=...") → balas HTTP 206 Partial Content
     dengan header Content-Range & Accept-Ranges: bytes. electron-updater DAN unduhan besar
     bergantung pada ini (resume + verifikasi sha512 sebagian).
  2) latest.yml dan .blockmap WAJIB dilayani di PATH yang sama dengan .exe (satu direktori),
     karena electron-updater memakai base feed https://pos.tatreport.com/unduh :
       ambil latest.yml → baca "path" (nama .exe) + "sha512" → unduh .exe → verifikasi sha512.
     Jangan ubah/olah isi latest.yml; sajikan apa adanya dari GitHub Release.
  3) Content-Type yang benar:
       .exe      → application/octet-stream (atau application/x-msdownload)
       .apk      → application/vnd.android.package-archive
       .yml      → text/yaml (atau text/plain)
       .blockmap → application/octet-stream
  4) TLS valid & tidak kedaluwarsa. TIDAK BOLEH menonaktifkan/menurunkan TLS demi unduhan.
  5) Content-Length akurat; ETag/Last-Modified boleh untuk caching. Idealnya immutable per versi.

Implementasi boleh: reverse-proxy ke GitHub Release assets, sinkronisasi ke object storage
(S3/GCS) + CDN, atau melayani dari disk. Yang penting: nama berkas PERSIS, Range didukung,
latest.yml+.blockmap satu direktori dengan .exe.

================================================================================
DELIVERABLE
================================================================================
1. Endpoint GET /api/pos/v1/app/versi (publik, tanpa auth) sesuai KONTRAK 1.
2. Middleware global penegak versi (KONTRAK 2) → HTTP 426 + envelope untuk klien di bawah minimum,
   di-attach ke semua route /api/pos/v1 KECUALI /app/versi, membaca header X-Tuleh-Version.
3. Layanan berkas unduhan https://pos.tatreport.com/unduh/{nama} (KONTRAK 3) dengan Range + latest.yml.
4. Sumber konfigurasi versi_terbaru, versi_minimum, catatan, ukuran, pola URL (env/DB/admin), dapat
   diubah tanpa deploy ulang.
5. Utilitas perbandingan semver yang benar (mis. paket semver di bahasa Anda) + unit test untuk
   kasus batas (sama dengan, lebih besar, lebih kecil, pra-rilis, input tak valid).
6. Dokumentasi singkat (README) berisi: cara mengubah versi saat rilis baru, cara berkas ditaruh,
   dan contoh respons.

================================================================================
KRITERIA PENERIMAAN (ACCEPTANCE CRITERIA — HARUS BISA DIUJI)
================================================================================
Asumsi contoh: versi_terbaru="0.9.9", versi_minimum="0.9.0".

A. /app/versi TANPA auth mengembalikan 200 (bukan 401/403).
B. GET /app/versi?versi=0.9.9  → data.wajib=false, data.update_tersedia=false.
C. GET /app/versi?versi=0.9.8  → data.wajib=false, data.update_tersedia=true (skenario BANNER).
D. GET /app/versi?versi=0.8.5  → data.wajib=true,  data.update_tersedia=true (skenario LAYAR PENUH).
E. Respons /app/versi SELALU memuat data.unduhan.windows.url & data.unduhan.android.url yang
   menunjuk https://pos.tatreport.com/unduh/Tuleh-Setup-<versi>.exe dan Tuleh-<versi>-android.apk.
F. Semua respons JSON mengikuti envelope { success, data, meta, message, errors } persis.
G. Request ke endpoint terproteksi mana pun dengan header "X-Tuleh-Version: 0.8.0" → HTTP 426 +
   envelope success=false, message Bahasa Indonesia. Dengan "X-Tuleh-Version: 0.9.9" → TIDAK 426.
H. Request ke endpoint terproteksi TANPA header X-Tuleh-Version TIDAK mengembalikan 426 (fail-open).
I. /app/versi TIDAK pernah membalas 426 walau versi klien sangat lama.
J. GET https://pos.tatreport.com/unduh/latest.yml → 200, Content berisi "path:" & "sha512:".
K. GET .exe dengan header "Range: bytes=0-1023" → HTTP 206, Content-Range ada, panjang 1024 byte.
L. GET .apk mengembalikan Content-Type application/vnd.android.package-archive dan mendukung Range.
M. Semua URL unduhan HTTPS dengan sertifikat valid; tidak ada downgrade ke HTTP.
N. Mengubah versi_minimum/versi_terbaru lewat konfigurasi mengubah perilaku B–D & G TANPA deploy ulang.
O. Input tak valid GET /app/versi?versi=bukan-semver TIDAK menyebabkan HTTP 500 (ditangani rapi).
P. teks "catatan" dikembalikan apa adanya (Bahasa Indonesia), tanpa dipotong/di-escape berlebihan.

================================================================================
PERINTAH VERIFIKASI (jalankan dan tunjukkan hasilnya)
================================================================================
# 1) Cek versi terbaru (tanpa update)
curl -s "https://tatreport.com/api/pos/v1/app/versi?versi=0.9.9" | jq

# 2) Skenario BANNER (update tersedia, tidak wajib)
curl -s "https://tatreport.com/api/pos/v1/app/versi?versi=0.9.8" | jq '.data | {wajib, update_tersedia, versi_terbaru}'

# 3) Skenario LAYAR PENUH WAJIB (di bawah versi minimum)
curl -s "https://tatreport.com/api/pos/v1/app/versi?versi=0.8.5" | jq '.data | {wajib, update_tersedia}'

# 4) Pastikan /app/versi TANPA auth (harus 200, bukan 401)
curl -s -o /dev/null -w "%{http_code}\n" "https://tatreport.com/api/pos/v1/app/versi?versi=0.9.9"

# 5) Semantik 426 pada endpoint terproteksi dengan klien lama (ganti /some/endpoint dengan endpoint nyata)
curl -s -o /dev/null -w "%{http_code}\n" -H "X-Tuleh-Version: 0.8.0" -H "Authorization: Bearer <TOKEN>" \
  "https://tatreport.com/api/pos/v1/some/endpoint"     # harus 426

curl -s -H "X-Tuleh-Version: 0.8.0" -H "Authorization: Bearer <TOKEN>" \
  "https://tatreport.com/api/pos/v1/some/endpoint" | jq '{success, message}'

# 6) Klien terbaru TIDAK kena 426
curl -s -o /dev/null -w "%{http_code}\n" -H "X-Tuleh-Version: 0.9.9" -H "Authorization: Bearer <TOKEN>" \
  "https://tatreport.com/api/pos/v1/some/endpoint"     # bukan 426

# 7) latest.yml tersedia untuk electron-updater
curl -s "https://pos.tatreport.com/unduh/latest.yml"    # harus memuat path: & sha512:

# 8) HTTP Range didukung (harus 206 + Content-Range)
curl -s -D - -o /dev/null -H "Range: bytes=0-1023" \
  "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe" | grep -Ei "HTTP/|Content-Range|Accept-Ranges"

# 9) APK Content-Type & Range
curl -s -D - -o /dev/null -H "Range: bytes=0-1023" \
  "https://pos.tatreport.com/unduh/Tuleh-0.9.9-android.apk" | grep -Ei "HTTP/|Content-Type|Content-Range"

# 10) blockmap ada di direktori yang sama
curl -s -o /dev/null -w "%{http_code}\n" "https://pos.tatreport.com/unduh/Tuleh-Setup-0.9.9.exe.blockmap"  # 200

================================================================================
CATATAN PENTING
================================================================================
- Klien bersifat fail-open (kegagalan cek versi tidak memblokir pemakaian), TAPI server harus tetap
  andal & benar. Jangan mengandalkan klien untuk menutupi bug server.
- JANGAN memakai perbandingan string untuk versi ("0.9.10" > "0.9.9" salah jika string) —
  gunakan pustaka/algoritme semver yang benar.
- JANGAN pernah menonaktifkan TLS untuk unduhan.
- Semua "message"/"catatan" yang tampil ke pengguna WAJIB Bahasa Indonesia.
- Sertakan unit test untuk logika versi dan test integrasi untuk endpoint + middleware 426.
````