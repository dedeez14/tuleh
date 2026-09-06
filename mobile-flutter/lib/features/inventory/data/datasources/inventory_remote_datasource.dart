import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';

class InventoryRemoteDataSource {
  InventoryRemoteDataSource(this._dio);

  final Dio _dio;

  /// POST /inventory/stok-masuk — tambah stok produk.
  /// Kontrak MOVERA (terverifikasi): { id_produk, jumlah }.
  Future<void> stokMasuk({required String idProduk, required double jumlah}) =>
      stokMasukBody({'id_produk': idProduk, 'jumlah': jumlah});

  /// Kirim badan apa adanya (jalur antrean offline menambah client_ref).
  Future<void> stokMasukBody(Map<String, dynamic> badan) async {
    late final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>('/inventory/stok-masuk', data: badan);
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
  }
}
