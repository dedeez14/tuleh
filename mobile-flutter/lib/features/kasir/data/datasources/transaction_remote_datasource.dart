import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';

/// Hasil checkout — nomor transaksi + kembalian.
typedef CheckoutResult = ({String nomor, double kembalian});

class TransactionRemoteDataSource {
  TransactionRemoteDataSource(this._dio);

  final Dio _dio;

  /// POST /transaksi/checkout. Kontrak MOVERA (terverifikasi):
  /// `items` = [{id_produk, kuantitas, harga}], `tipe_pembayaran`, `dibayar`.
  Future<CheckoutResult> checkout({
    required List<Map<String, dynamic>> items,
    required String metode,
    required double dibayar,
  }) async {
    late final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>('/transaksi/checkout', data: {
        'items': items,
        'tipe_pembayaran': metode,
        'dibayar': dibayar,
      });
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
    final data = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
    final kembalian = data['kembalian'];
    return (
      nomor: (data['nomor'] ?? data['no'] ?? '').toString(),
      kembalian: kembalian is num ? kembalian.toDouble() : 0.0,
    );
  }
}
