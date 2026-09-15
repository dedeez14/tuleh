import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Menerjemahkan status HTTP & DioException ke [ApiException] berpesan
/// Bahasa Indonesia (selaras dengan api-client web).
class ApiErrorMapper {
  ApiErrorMapper._();

  static String statusMessage(int status) => switch (status) {
        0 => 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
        401 => 'Sesi Anda telah berakhir. Silakan masuk kembali.',
        402 => 'Langganan usaha ini sudah berakhir.',
        403 => 'Anda tidak memiliki akses untuk aksi ini.',
        404 => 'Data tidak ditemukan.',
        408 => 'Server terlalu lama menjawab. Coba lagi sebentar.',
        409 => 'Aksi bentrok dengan kondisi saat ini.',
        422 => 'Data yang dikirim tidak valid.',
        426 => 'Aplikasi Anda perlu diperbarui ke versi terbaru.',
        429 => 'Terlalu banyak permintaan. Coba lagi sebentar.',
        502 || 503 || 504 => 'Server sedang gangguan. Coba lagi sebentar.',
        >= 500 => 'Terjadi kesalahan pada server.',
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

  /// Header `Retry-After`: detik (`120`) atau tanggal HTTP. null bila tidak
  /// ada / tak terbaca / sudah lewat.
  static Duration? retryAfter(Headers headers, {DateTime? sekarang}) {
    final raw = headers.value('retry-after')?.trim();
    if (raw == null || raw.isEmpty) return null;
    final detik = int.tryParse(raw);
    if (detik != null) return detik > 0 ? Duration(seconds: detik) : null;
    try {
      final t = HttpDate.parse(raw);
      final jeda = t.difference((sekarang ?? DateTime.now()).toUtc());
      return jeda.isNegative ? null : jeda;
    } catch (_) {
      return null;
    }
  }

  /// Jawaban HTTP non-sukses → [ApiException] (pesan server bila ada, status,
  /// error validasi, `Retry-After`, dan `meta`).
  static ApiException fromResponse(Response<dynamic> res) {
    final code = res.statusCode ?? 0;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    final pesan = body['message'];
    final meta = body['meta'];
    return ApiException(
      message: pesan is String && pesan.trim().isNotEmpty ? pesan : statusMessage(code),
      statusCode: code,
      errors: parseErrors(body['errors']),
      cobaLagiSetelah: retryAfter(res.headers),
      meta: meta is Map ? Map<String, dynamic>.from(meta) : null,
    );
  }

  static ApiException fromDio(DioException e) {
    // Dio dengan validateStatus ketat membawa jawaban di dalam exception —
    // tetap klasifikasikan dari status HTTP-nya, bukan sebagai jaringan putus.
    final res = e.response;
    if (e.type == DioExceptionType.badResponse && res != null && (res.statusCode ?? 0) > 0) {
      return fromResponse(res);
    }
    final timedOut = e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    // connectionTimeout = belum tersambung (aman diulang). receive/send
    // timeout = permintaan mungkin sudah diterima server.
    final mungkinSampai = e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    return ApiException(
      message: timedOut
          ? 'Server tidak merespons (timeout).'
          : statusMessage(0),
      mungkinSampai: mungkinSampai,
    );
  }
}
