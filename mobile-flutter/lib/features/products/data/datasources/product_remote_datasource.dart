import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/product.dart';

class ProductRemoteDataSource {
  ProductRemoteDataSource(this._dio);

  final Dio _dio;

  /// Batas halaman per pemuatan: 100 × 30 = 3.000 produk, cukup untuk toko
  /// kelontong besar; lebih dari itu pakai pencarian.
  static const int _perHalaman = 100;
  static const int _maksHalaman = 30;

  /// GET /produk (opsional ?q=) → katalog toko aktif (interceptor menyisipkan
  /// toko_id). Server memberi 50 item per halaman secara bawaan, jadi SEMUA
  /// halaman ditarik — tanpa ini toko dengan >50 produk hanya melihat
  /// sebagian katalognya di kasir.
  ///
  /// [includeHabis]: sertakan produk berstok 0 (layar kelola produk, agar bisa
  /// direstok); kasir tidak (mengikuti desktop).
  Future<List<Product>> list({String? query, bool includeHabis = false}) async {
    final hasil = <Product>[];
    for (var halaman = 1; halaman <= _maksHalaman; halaman++) {
      final body = await _send(() => _dio.get<dynamic>(
            '/produk',
            queryParameters: {
              if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
              if (includeHabis) 'include_habis': 1,
              'per_page': _perHalaman,
              'page': halaman,
            },
          ));
      final data = body['data'];
      final list = data is List ? data : const [];
      hasil.addAll([
        for (final e in list)
          if (e is Map) _product(Map<String, dynamic>.from(e)),
      ]);
      final meta = body['meta'];
      final terakhir = meta is Map ? meta['last_page'] : null;
      final iniTerakhir =
          terakhir is! num || halaman >= terakhir || list.length < _perHalaman;
      if (iniTerakhir) break;
    }
    return hasil;
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
    final hargaJual = _double(m['harga_jual'] ?? m['harga'] ?? m['price']);
    final promo = m['promo_aktif'] == true && m['harga_efektif'] != null;
    final gambar = m['gambar']?.toString();
    return Product(
      id: (m['id'] ?? '').toString(),
      nama: (m['nama'] ?? m['name'] ?? '-').toString(),
      harga: promo ? _double(m['harga_efektif']) : hargaJual,
      hargaNormal: promo ? hargaJual : null,
      promo: promo,
      gambar: gambar == null || gambar.isEmpty ? null : gambar,
      tipe: m['tipe']?.toString(),
      hargaBeli: m['harga_beli'] == null ? null : _double(m['harga_beli']),
      satuan: satNama?.toString(),
      kategori: katNama?.toString(),
      barcode: m['barcode']?.toString(),
      stok: m['stok'] == null ? null : _double(m['stok']),
    );
  }
}
