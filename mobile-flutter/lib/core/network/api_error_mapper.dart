import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Menerjemahkan status HTTP & DioException ke [ApiException] berpesan
/// Bahasa Indonesia (selaras dengan api-client web).
class ApiErrorMapper {
  ApiErrorMapper._();

  static String statusMessage(int status) => switch (status) {
        0 => 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
        401 => 'Sesi Anda telah berakhir. Silakan masuk kembali.',
        403 => 'Anda tidak memiliki akses untuk aksi ini.',
        404 => 'Data tidak ditemukan.',
        409 => 'Aksi bentrok dengan kondisi saat ini.',
        422 => 'Data yang dikirim tidak valid.',
        426 => 'Aplikasi Anda perlu diperbarui ke versi terbaru.',
        429 => 'Terlalu banyak permintaan. Coba lagi sebentar.',
        500 => 'Terjadi kesalahan pada server.',
        _ => 'Terjadi kesalahan (HTTP $status).',
      };

  /// Peta error validasi MOVERA (`errors: { field: [pesan] }`).
  static Map<String, List<String>>? parseErrors(dynamic raw) {
    if (raw is! Map) return null;
    final out = <String, List<String>>{};
    raw.forEach((k, v) {
      if (v is List) {
        out['$k'] = v.map((e) => '$e').toList();
      } else if (v != null) {
        out['$k'] = ['$v'];
      }
    });
    return out.isEmpty ? null : out;
  }

  static ApiException fromDio(DioException e) {
    final timedOut = e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    return ApiException(
      message: timedOut
          ? 'Server tidak merespons (timeout).'
          : statusMessage(0),
    );
  }
}
