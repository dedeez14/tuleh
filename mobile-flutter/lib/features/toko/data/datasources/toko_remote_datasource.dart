import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/toko.dart';
import '../../domain/entities/toko_manifest.dart';

class TokoRemoteDataSource {
  TokoRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /tokos → daftar toko aktif tenant.
  Future<List<Toko>> list() async {
    final body = await _send(() => _dio.get<dynamic>('/tokos'));
    final data = body['data'];
    final list = data is List ? data : const [];
    return [
      for (final e in list)
        if (e is Map) _toko(Map<String, dynamic>.from(e)),
    ];
  }

  /// GET /tokos/{id}/manifest → "wajah" aplikasi untuk toko itu (menu,
  /// kapabilitas, tahapan pesanan, stasiun). Server yang belum menyediakan
  /// endpoint ini (404) diperlakukan sebagai manifest kosong: app tetap jalan
  /// dengan menu bawaan, papan pesanan disembunyikan.
  Future<TokoManifest> manifest(String tokoId) async {
    late final Map<String, dynamic> body;
    try {
      body = await _send(
        () => _dio.get<dynamic>('/tokos/${Uri.encodeComponent(tokoId)}/manifest'),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const TokoManifest();
      rethrow;
    }
    final data = body['data'];
    if (data is! Map) return const TokoManifest();
    return TokoManifest.fromJson(Map<String, dynamic>.from(data));
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

  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() call,
  ) async {
    late final Response<dynamic> res;
    try {
      res = await call();
    } on DioException catch (e) {
      throw ApiErrorMapper.fromDio(e);
    }
    final code = res.statusCode ?? 0;
    final body = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : const <String, dynamic>{};
    final ok = code >= 200 && code < 300 && body['success'] == true;
    if (!ok) {
      throw ApiException(
        message:
            (body['message'] as String?) ?? ApiErrorMapper.statusMessage(code),
        statusCode: code,
      );
    }
    return body;
  }
}
