import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/pelanggan.dart';

class PelangganRemoteDataSource {
  PelangganRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /pelanggan → daftar pelanggan toko aktif.
  Future<List<Pelanggan>> list() async {
    final body = await _send(() => _dio.get<dynamic>('/pelanggan'));
    final data = body['data'];
    final list = data is List ? data : const [];
    return [
      for (final e in list)
        if (e is Map) _pelanggan(Map<String, dynamic>.from(e)),
    ];
  }

  /// POST /pelanggan → tambah pelanggan (nama wajib; no_whatsapp opsional).
  Future<Pelanggan> tambah({required String nama, String? telepon}) async {
    final body = await _send(() => _dio.post<dynamic>('/pelanggan', data: {
          'nama': nama,
          if (telepon != null && telepon.trim().isNotEmpty)
            'no_whatsapp': telepon.trim(),
        }));
    final d = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
    // Server bisa balas objek pelanggan; fallback ke input bila minim.
    return d.isEmpty
        ? Pelanggan(id: '', nama: nama, telepon: telepon)
        : _pelanggan(d);
  }

  // ---- helper ----
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

  Pelanggan _pelanggan(Map<String, dynamic> m) => Pelanggan(
        id: (m['id'] ?? '').toString(),
        nama: (m['nama'] ?? m['name'] ?? '-').toString(),
        kode: m['kode']?.toString(),
        telepon: (m['telepon'] ?? m['no_whatsapp'] ?? m['whatsapp'] ?? m['wa'])?.toString(),
        alamat: m['alamat']?.toString(),
      );
}
