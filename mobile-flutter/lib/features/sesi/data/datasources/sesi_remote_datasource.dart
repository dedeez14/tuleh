import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/sesi.dart';
import '../../domain/entities/sesi_rekap.dart';

class SesiRemoteDataSource {
  SesiRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /sesi/aktif → sesi berjalan (minimal, utk gating) atau null.
  /// Catatan: /sesi/aktif TIDAK memuat `id` → id diambil dari [aktifId].
  Future<Sesi?> aktif() async {
    final body = await _send(() => _dio.get<dynamic>('/sesi/aktif'));
    final data = body['data'];
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);
    return Sesi(
      id: (m['id'] ?? '').toString(),
      nomor: (m['nomor'] ?? m['no'])?.toString(),
      dibukaPada: (m['waktu_buka'] ?? m['dibuka_pada'] ?? m['created_at'])?.toString(),
    );
  }

  /// GET /sesi/aktif → rekap kaya (kas & penjualan) atau null.
  Future<SesiRekap?> rekapAktif() async {
    final body = await _send(() => _dio.get<dynamic>('/sesi/aktif'));
    final data = body['data'];
    if (data is! Map) return null;
    return SesiRekap.fromJson(Map<String, dynamic>.from(data));
  }

  /// GET /sesi → cari id sesi berstatus BUKA (dibutuhkan utk tutup, karena
  /// /sesi/aktif tak mengembalikan id).
  Future<String?> aktifId() async {
    final body = await _send(() => _dio.get<dynamic>('/sesi'));
    for (final e in _rows(body['data'])) {
      if (e is Map && (e['status']?.toString().toUpperCase() == 'BUKA')) {
        return e['id']?.toString();
      }
    }
    return null;
  }

  /// GET /gudang → id gudang pertama (dibutuhkan utk buka sesi).
  Future<String?> firstGudangId() async {
    final body = await _send(() => _dio.get<dynamic>('/gudang'));
    for (final e in _rows(body['data'])) {
      if (e is Map && e['id'] != null) return e['id'].toString();
    }
    return null;
  }

  /// POST /sesi/buka {kas_awal, gudang_id, catatan}.
  Future<void> buka({
    required double kasAwal,
    required String gudangId,
    String? catatan,
  }) async {
    await _send(() => _dio.post<dynamic>('/sesi/buka', data: {
          'kas_awal': kasAwal,
          'gudang_id': gudangId,
          if (catatan != null && catatan.trim().isNotEmpty) 'catatan': catatan.trim(),
        }));
  }

  /// POST /sesi/{id}/tutup {kas_akhir_fisik, catatan}.
  Future<void> tutup({
    required String id,
    required double kasAkhirFisik,
    String? catatan,
  }) async {
    await _send(
      () => _dio.post<dynamic>('/sesi/${Uri.encodeComponent(id)}/tutup', data: {
        'kas_akhir_fisik': kasAkhirFisik,
        if (catatan != null && catatan.trim().isNotEmpty) 'catatan': catatan.trim(),
      }),
    );
  }

  // ---- helper ----
  List<dynamic> _rows(dynamic data) => data is List
      ? data
      : (data is Map && data['rows'] is List ? data['rows'] as List : const []);

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    late final Response<dynamic> res;
    try {
      res = await call();
    } on DioException catch (e) {
      throw ApiErrorMapper.fromDio(e);
    }
    final code = res.statusCode ?? 0;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
    final ok = code >= 200 && code < 300 && body['success'] == true;
    if (!ok) {
      throw ApiException(
        message: (body['message'] as String?) ?? ApiErrorMapper.statusMessage(code),
        statusCode: code,
        errors: ApiErrorMapper.parseErrors(body['errors']),
      );
    }
    return body;
  }
}
