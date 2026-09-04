/// Kebijakan sumber APK pembaruan — SATU aturan yang dipakai Dart (memilih
/// aset, menampilkan tombol unduh) dan diduplikasi di native
/// (`MainActivity.kt` → `hostAllowed`) sebagai penegakan akhir sebelum
/// DownloadManager. Keduanya harus sama; test `pembaruan_test.dart` menjaga
/// sisi Dart.
///
/// Kasus nyata: rilis 2.1.0/2.2.0 menawarkan pembaruan dari GitHub, tetapi
/// native hanya mengizinkan `tatreport.com`, sehingga tombol unduh gagal dengan
/// "URL unduhan tidak valid / host tidak diizinkan".
abstract final class SumberApk {
  /// Repo GitHub tempat APK Flutter diterbitkan (tag `flutter-vX.Y.Z`).
  static const String repoGithub = 'dedeez14/tuleh';

  /// Host server MOVERA (dan subdomainnya) — sumber lewat `/app/versi`.
  static const String hostServer = 'tatreport.com';

  /// Awalan path aset Release di github.com untuk repo ini.
  static String get awalanRilisGithub => '/$repoGithub/releases/download/';

  /// true bila [url] boleh diunduh dan dipasang sebagai pembaruan:
  /// - wajib https;
  /// - host `tatreport.com` atau subdomainnya, path bebas; atau
  /// - host `github.com` dengan path aset Release repo ini.
  static bool diizinkan(String? url) {
    if (url == null) return false;
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return false;
    final host = u.host.toLowerCase();
    if (host == hostServer || host.endsWith('.$hostServer')) return true;
    if (host == 'github.com' || host == 'www.github.com') {
      return u.path.startsWith(awalanRilisGithub);
    }
    return false;
  }
}
