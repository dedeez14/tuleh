import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../domain/entities/hasil_pesanan.dart';
import '../../domain/entities/pesanan.dart';

/// `GET /orders` & `POST /orders/{id}/transition` — cermin ipc.js desktop.
class PesananRemoteDataSource {
  PesananRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<Pesanan>> list({String? stage, String? bayar}) async {
    final body = await _send(
      () => _dio.get<dynamic>(
        '/orders',
        queryParameters: {
          if (stage != null && stage.isNotEmpty) 'stage': stage,
          if (bayar != null && bayar.isNotEmpty) 'bayar': bayar,
        },
      ),
    );
    return parseRows(body['data']);
  }

  /// `POST /orders` — nota bayar nanti (`NANTI`) atau uang muka (`DP`). Online-only; `client_ref` membuat
  /// kirim ulang mengembalikan pesanan yang sama (server `pos.idempoten`).
  Future<NotaPesanan> buatNota({
    required String bayar,
    required List<ItemNota> items,
    String? idPelanggan,
    String? catatan,
    num? uangMuka,
    String? metodeUangMuka,
    required String clientRef,
  }) async {
    final body = await _send(
      () => _dio.post<dynamic>(
        '/orders',
        data: {
          'bayar': bayar,
          'items': [
            for (final i in items)
              {'id_produk': i.idProduk, 'kuantitas': i.kuantitas},
          ],
          if (idPelanggan != null && idPelanggan.isNotEmpty)
            'id_pelanggan': idPelanggan,
          if (catatan != null && catatan.trim().isNotEmpty)
            'catatan': catatan.trim(),
          if (bayar == 'DP')
            'dp': {'jumlah': uangMuka, 'tipe_pembayaran': metodeUangMuka},
          'client_ref': clientRef,
        },
      ),
    );
    final data = body['data'];
    final m = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
    return NotaPesanan(
      pesanan: m['order'] is Map
          ? Pesanan.fromJson(Map<String, dynamic>.from(m['order'] as Map))
          : const Pesanan(id: '', stage: ''),
      nota: m['nota'] is Map
          ? Map<String, dynamic>.from(m['nota'] as Map)
          : <String, dynamic>{},
    );
  }

  Future<HasilTransisi> transition(
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
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      // Server: field pesanan + `struk` opsional (pelunasan). Bentuk lama Mode Demo desktop: {order, struk}.
      final orderMap = m['order'] is Map
          ? Map<String, dynamic>.from(m['order'] as Map)
          : m;
      final struk = m['struk'] is Map
          ? Map<String, dynamic>.from(m['struk'] as Map)
          : null;
      return HasilTransisi(pesanan: Pesanan.fromJson(orderMap), struk: struk);
    }
    // Server minimal (tanpa echo order) → tebakan lokal agar UI maju.
    return HasilTransisi(pesanan: Pesanan(id: id, stage: to));
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
      throw ApiErrorMapper.fromResponse(res);
    }
    return body;
  }
}
