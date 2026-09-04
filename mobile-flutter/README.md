# tuleh_pos

Tuléh POS — **aplikasi Android utama** (Flutter, clean architecture, minSdk 29 / Android 10+).
Pendamping aplikasi desktop di [`../frontend`](../frontend); aplikasi Android lama
berbasis Capacitor ada di [`../mobile`](../mobile) (legacy).

## Perintah

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Rilis: naikkan `version:` di `pubspec.yaml`, push ke `main` → workflow
[`flutter-release.yml`](../.github/workflows/flutter-release.yml) membuat tag
`flutter-vX.Y.Z` dan mengunggah APK per ABI. Aplikasi yang terpasang menawarkan
versi baru itu sendiri (server `/app/versi` dulu, lalu GitHub Releases).

## Aset merek

`assets/brand/` — logo Tuléh (notepad + pensil) yang sama dengan desktop dan
aplikasi lama. Ikon peluncur & splash native dibuat ulang dari sini:

```powershell
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
