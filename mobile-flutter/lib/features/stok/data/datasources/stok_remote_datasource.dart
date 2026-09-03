import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/stok_item.dart';

class StokRemoteDataSource {
  StokRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /laporan/stok → daftar stok produk toko aktif ({id,kode,produk,stok}).
  Future<List<StokItem>> list() async {
    final body = await _send(() => _dio.get<dynamic>('/laporan/stok'));
    final data = body['data'];
    final rows = data is List
        ? data
        : (data is Map && data['rows'] is List ? data['rows'] as List : const []);
    return [
      for (final e in rows)
        if (e is Map) _item(Map<String, dynamic>.from(e)),
    ];
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

  double _double(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  StokItem _item(Map<String, dynamic> m) => StokItem(
        id: (m['id'] ?? '').toString(),
        kode: (m['kode'] ?? '-').toString(),
        produk: (m['produk'] ?? m['nama'] ?? '-').toString(),
        stok: _double(m['stok'] ?? m['jumlah'] ?? m['qty']),
      );
}
