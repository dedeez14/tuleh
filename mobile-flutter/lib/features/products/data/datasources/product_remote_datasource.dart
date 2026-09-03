import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/product.dart';

class ProductRemoteDataSource {
  ProductRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /produk (opsional ?q=) → katalog toko aktif (interceptor menyisipkan toko_id).
  Future<List<Product>> list({String? query}) async {
    final body = await _send(() => _dio.get<dynamic>(
          '/produk',
          queryParameters: {
            if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          },
        ));
    final data = body['data'];
    final list = data is List ? data : const [];
    return [
      for (final e in list)
        if (e is Map) _product(Map<String, dynamic>.from(e)),
    ];
  }

  /// POST /produk → tambah produk. Kontrak MOVERA: wajib {nama, tipe, harga_jual};
  /// harga_beli & barcode opsional.
  Future<void> create({
    required String nama,
    required String tipe,
    required double hargaJual,
    double? hargaBeli,
    String? barcode,
  }) async {
    await _send(() => _dio.post<dynamic>('/produk', data: {
          'nama': nama,
          'tipe': tipe,
          'harga_jual': hargaJual,
          'harga_beli': ?hargaBeli,
          if (barcode != null && barcode.trim().isNotEmpty) 'barcode': barcode.trim(),
        }));
  }

  /// PATCH /produk/{id} → ubah sebagian field (PUT tak didukung server).
  Future<void> update({
    required String id,
    String? nama,
    double? hargaJual,
    double? hargaBeli,
    String? barcode,
  }) async {
    final data = <String, dynamic>{
      'nama': ?nama,
      'harga_jual': ?hargaJual,
      'harga_beli': ?hargaBeli,
      'barcode': ?barcode,
    };
    await _send(() => _dio.patch<dynamic>('/produk/$id', data: data));
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

  Product _product(Map<String, dynamic> m) {
    final kat = m['kategori'];
    final katNama = kat is Map ? (kat['nama'] ?? kat['name']) : kat;
    final sat = m['satuan'];
    final satNama = sat is Map ? (sat['nama'] ?? sat['name']) : sat;
    return Product(
      id: (m['id'] ?? '').toString(),
      nama: (m['nama'] ?? m['name'] ?? '-').toString(),
      harga: _double(m['harga_jual'] ?? m['harga'] ?? m['price']),
      tipe: m['tipe']?.toString(),
      hargaBeli: m['harga_beli'] == null ? null : _double(m['harga_beli']),
      satuan: satNama?.toString(),
      kategori: katNama?.toString(),
      barcode: m['barcode']?.toString(),
      stok: m['stok'] == null ? null : _double(m['stok']),
    );
  }
}
