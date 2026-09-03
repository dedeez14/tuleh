/// Konfigurasi global aplikasi (endpoint MOVERA POS API).
///
/// baseUrl = domain tenant. Untuk multi-tenant, nilai ini bisa diubah di layar
/// pengaturan dan disimpan aman (lihat [SecureStorage]).
class AppConfig {
  AppConfig._();

  static const String defaultBaseUrl = 'https://tatreport.com';
  static const String apiPrefix = '/api/pos/v1';
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Header versi aplikasi (Auto-Update). Diisi runtime dari package_info_plus.
  static const String versionHeader = 'X-Tuleh-Version';
}
