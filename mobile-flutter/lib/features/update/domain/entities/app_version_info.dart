import '../sumber_apk.dart';

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

  /// Salinan dengan sebagian nilai diganti (penyesuaian ABI & penegasan
  /// `wajib` dari server saat berkas diambil dari cadangan GitHub).
  AppVersionInfo dengan({
    bool? wajib,
    String? androidUrl,
    String? androidNama,
    int? ukuran,
    bool kosongkanUkuran = false,
  }) => AppVersionInfo(
    wajib: wajib ?? this.wajib,
    updateTersedia: updateTersedia,
    versiTerbaru: versiTerbaru,
    versiMinimum: versiMinimum,
    catatan: catatan,
    androidUrl: androidUrl ?? this.androidUrl,
    androidNama: androidNama ?? this.androidNama,
    ukuran: kosongkanUkuran ? null : (ukuran ?? this.ukuran),
  );

  /// APK bisa diunduh dalam-app: https dari sumber yang diizinkan
  /// ([SumberApk] — aturan yang sama dengan penegakan native).
  bool get hasAndroidDownload => SumberApk.diizinkan(androidUrl);

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
