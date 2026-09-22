/// Status HTTP yang berarti **gangguan**, bukan penolakan: server tidak
/// terjangkau (0), kehabisan waktu (408), sedang dibatasi (429), atau galat
/// server/gateway (5xx, termasuk 502/503/504 dari proxy).
///
/// Kontrak kesiapan produksi 2026-09-15 ("Klien — perilaku wajib"): gangguan
/// diperlakukan seperti jaringan putus — permintaan tulis diantrekan dan
/// dicoba ulang dengan mundur (menghormati `Retry-After`), permintaan baca
/// dijawab dari salinan, dan pita "offline" tampil. Penjualan TIDAK BOLEH
/// hilang atau tersangkut di "perlu ditinjau" hanya karena server sesaat
/// bermasalah — server menolak kiriman ganda lewat `client_ref`.
bool statusGangguan(int statusCode) =>
    statusCode <= 0 || statusCode == 408 || statusCode == 429 || statusCode >= 500;

/// Kesalahan lapisan jaringan yang dinormalisasi (pesan siap tampil ke pengguna,
/// Bahasa Indonesia). Membawa [statusCode] + [errors] validasi bila ada.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode = 0,
    this.errors,
    this.mungkinSampai = false,
    this.cobaLagiSetelah,
    this.meta,
  });

  final String message;
  final int statusCode;

  /// Galat jaringan (statusCode 0) yang terjadi SETELAH permintaan mungkin
  /// sampai ke server (timeout menunggu jawaban). Sejak server mengenal
  /// `client_ref`, mengulangnya aman — penanda ini tinggal informasi.
  final bool mungkinSampai;

  /// Jeda dari header `Retry-After` (429/503) bila server menyebutkannya.
  final Duration? cobaLagiSetelah;

  /// `meta` amplop server (mis. `meta.langganan` pada 402).
  final Map<String, dynamic>? meta;

  /// Gagal jaringan murni (tidak ada jawaban HTTP sama sekali).
  bool get isJaringan => statusCode == 0;

  /// Gangguan (jaringan putus, 408, 429, 5xx): aman diulang / diantrekan.
  bool get isGangguan => statusGangguan(statusCode);

  /// Peta error validasi per-field (mengikuti envelope MOVERA `errors`).
  final Map<String, List<String>>? errors;

  /// 401 → sesi berakhir (token ditolak).
  bool get isUnauthorized => statusCode == 401;

  /// 402 → langganan perusahaan diblokir untuk permintaan tulis.
  bool get isLanggananBerakhir => statusCode == 402;

  /// 426 → wajib perbarui aplikasi (Auto-Update).
  bool get isUpgradeRequired => statusCode == 426;

  /// Pesan validasi pertama yang LAYAK DIBACA kasir, atau null bila tak ada —
  /// pemanggil jatuh ke [message], kalimat dari server.
  ///
  /// Kunci `kode` dan nilai berbentuk kode mesin (`SESI_BUTUH_TOKO`) dilewati:
  /// itu penanda untuk program, bukan kalimat. Tanpa saringan ini, 422
  /// `errors.kode=['SESI_BUTUH_TOKO']` dari `/sesi/buka` terpampang apa adanya
  /// di layar kasir. Paritas `firstError()` di `api.js` desktop (7de4db4).
  String? firstError() {
    final map = errors;
    if (map == null || map.isEmpty) return null;
    for (final entri in map.entries) {
      if (entri.key == 'kode' || entri.value.isEmpty) continue;
      final pesan = entri.value.first;
      if (_kodeMesin.hasMatch(pesan)) continue;
      return pesan;
    }
    return null;
  }

  static final _kodeMesin = RegExp(r'^[A-Z][A-Z0-9_]*$');

  @override
  String toString() => 'ApiException($statusCode): $message';
}
