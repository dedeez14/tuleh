import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/toko.dart';

class TokoRemoteDataSource {
  TokoRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /tokos → daftar toko aktif tenant.
  Future<List<Toko>> list() async {
    late final Response<dynamic> res;
    try {
      res = await _dio.get<dynamic>('/tokos');
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
      );
    }
    final data = body['data'];
    final list = data is List ? data : const [];
    return [
      for (final e in list)
        if (e is Map) _toko(Map<String, dynamic>.from(e)),
    ];
  }

  Toko _toko(Map<String, dynamic> m) {
    final bu = m['bidang_usaha'] is Map ? Map<String, dynamic>.from(m['bidang_usaha'] as Map) : const <String, dynamic>{};
    return Toko(
      id: (m['id'] ?? '').toString(),
      nama: (m['nama'] ?? m['name'] ?? 'Toko').toString(),
      bidangUsaha: (bu['nama'] ?? bu['name'])?.toString(),
      kategori: (bu['kategori'] ?? bu['archetype'])?.toString(),
    );
  }
}
