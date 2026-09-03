/// Info versi dari `GET /app/versi?versi=<v>` (Auto-Update).
/// Server yang MENENTUKAN `wajib` / `update_tersedia` berdasarkan versi klien —
/// app tak perlu bandingkan sendiri (satu sumber kebenaran).
class AppVersionInfo {
  const AppVersionInfo({
    required this.wajib,
    required this.updateTersedia,
    required this.versiTerbaru,
    required this.versiMinimum,
    required this.catatan,
    required this.androidUrl,
    required this.androidNama,
    required this.ukuran,
  });

  /// true → wajib perbarui (layar penuh memblokir).
  final bool wajib;

  /// true (dan !wajib) → banner opsional.
  final bool updateTersedia;

  final String versiTerbaru;
  final String? versiMinimum;

  /// Catatan rilis — ditampilkan apa adanya.
  final String catatan;

  /// URL + nama berkas APK Android (dari proksi unduh server).
  final String? androidUrl;
  final String? androidNama;

  /// Ukuran berkas (byte), bila server menyertakan.
  final int? ukuran;

  /// Nilai "tak ada pembaruan" — dipakai saat cek gagal (fail-open).
  static const none = AppVersionInfo(
    wajib: false,
    updateTersedia: false,
    versiTerbaru: '',
    versiMinimum: null,
    catatan: '',
    androidUrl: null,
    androidNama: null,
    ukuran: null,
  );

  /// APK bisa diunduh dalam-app (URL https valid).
  bool get hasAndroidDownload =>
      androidUrl != null && androidUrl!.startsWith('https://');

  factory AppVersionInfo.fromJson(Map<String, dynamic> d) {
    final unduhan = d['unduhan'];
    final android = unduhan is Map && unduhan['android'] is Map
        ? Map<String, dynamic>.from(unduhan['android'] as Map)
        : const <String, dynamic>{};
    return AppVersionInfo(
      wajib: d['wajib'] == true,
      updateTersedia: d['update_tersedia'] == true,
      versiTerbaru: (d['versi_terbaru'] ?? '').toString(),
      versiMinimum: d['versi_minimum']?.toString(),
      catatan: (d['catatan'] ?? '').toString(),
      androidUrl: android['url']?.toString(),
      androidNama: android['nama']?.toString(),
      ukuran: android['ukuran'] is num ? (android['ukuran'] as num).toInt() : null,
    );
  }
}
