/// Kesalahan lapisan jaringan yang dinormalisasi (pesan siap tampil ke pengguna,
/// Bahasa Indonesia). Membawa [statusCode] + [errors] validasi bila ada.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode = 0,
    this.errors,
  });

  final String message;
  final int statusCode;

  /// Peta error validasi per-field (mengikuti envelope MOVERA `errors`).
  final Map<String, List<String>>? errors;

  /// 401 → sesi berakhir (token ditolak).
  bool get isUnauthorized => statusCode == 401;

  /// 426 → wajib perbarui aplikasi (Auto-Update).
  bool get isUpgradeRequired => statusCode == 426;

  String? firstError() {
    if (errors == null || errors!.isEmpty) return null;
    final first = errors!.values.first;
    return first.isNotEmpty ? first.first : null;
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
