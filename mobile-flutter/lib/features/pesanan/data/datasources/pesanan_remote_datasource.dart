import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/pesanan.dart';

/// `GET /orders` & `POST /orders/{id}/transition` — cermin ipc.js desktop.
class PesananRemoteDataSource {
  PesananRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<Pesanan>> list({String? stage}) async {
    final body = await _send(
      () => _dio.get<dynamic>(
        '/orders',
        queryParameters: {
          if (stage != null && stage.isNotEmpty) 'stage': stage,
        },
      ),
    );
    return parseRows(body['data']);
  }

  Future<Pesanan> transition(
    String id, {
    required String to,
    String? tipePembayaran,
  }) async {
    final body = await _send(
      () => _dio.post<dynamic>(
        '/orders/${Uri.encodeComponent(id)}/transition',
        data: {
          'to': to,
          if (tipePembayaran != null && tipePembayaran.isNotEmpty)
            'tipe_pembayaran': tipePembayaran,
        },
      ),
    );
    final data = body['data'];
    if (data is Map) return Pesanan.fromJson(Map<String, dynamic>.from(data));
    // Server minimal (tanpa echo order) → kembalikan tebakan lokal agar UI maju.
    return Pesanan(id: id, stage: to);
  }

  /// `data` bisa berupa list langsung atau `{ rows: [...] }` (paginasi).
  static List<Pesanan> parseRows(dynamic data) {
    final rows = data is List
        ? data
        : (data is Map && data['rows'] is List ? data['rows'] as List : const []);
    return [
      for (final e in rows)
        if (e is Map) Pesanan.fromJson(Map<String, dynamic>.from(e)),
    ];
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
        errors: ApiErrorMapper.parseErrors(body['errors']),
      );
    }
    return body;
  }
}
