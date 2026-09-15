/// Konfigurasi INFRASTRUKTUR aplikasi (alamat MOVERA POS API, batas waktu,
/// nama header protokol). Data bisnis — kontak CS, tautan perpanjang, ambang
/// peringatan langganan, kebijakan pembaruan — TIDAK boleh ada di sini: semuanya
/// dibaca dari server (`/kontak-cs`, `/langganan/status`, `/app/versi`).
///
/// Alamat server bisa diganti saat build tanpa menyunting kode:
/// `flutter build apk --dart-define=TULEH_API_BASE=https://host-lain`.
class AppConfig {
  AppConfig._();

  static const String defaultBaseUrl = String.fromEnvironment(
    'TULEH_API_BASE',
    defaultValue: 'https://tatreport.com',
  );
  static const String apiPrefix = '/api/pos/v1';
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Header versi aplikasi (Auto-Update). Diisi runtime dari package_info_plus.
  static const String versionHeader = 'X-Tuleh-Version';

  /// Header jalur rilis — server memilih kebijakan pembaruan per platform.
  static const String platformHeader = 'X-Tuleh-Platform';

  /// Nilai `platform` aplikasi ini di semua kontrak server (`/app/versi`,
  /// `/diagnostik`, header [platformHeader]).
  static const String platform = 'android-flutter';
}
