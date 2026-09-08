import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/transaksi.dart';
import '../../domain/entities/transaksi_detail.dart';

class RiwayatRemoteDataSource {
  RiwayatRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /transaksi → daftar transaksi toko aktif (interceptor menyisipkan toko_id).
  Future<List<Transaksi>> list() async {
    final body = await _send(() => _dio.get<dynamic>('/transaksi'));
    final data = body['data'];
    final list = data is List ? data : const [];
    return [
      for (final e in list)
        if (e is Map) _trx(Map<String, dynamic>.from(e)),
    ];
  }

  /// GET /transaksi/{id} → detail transaksi (struk).
  Future<TransaksiDetail> detail(String id) async {
    final body = await _send(() => _dio.get<dynamic>('/transaksi/$id'));
    final d = _map(body['data']);
    final rawItems = d['items'] is List ? d['items'] as List : const [];
    return TransaksiDetail(
      id: (d['id'] ?? id).toString(),
      nomor: (d['nomor'] ?? d['no'] ?? '-').toString(),
      tanggal: (d['tanggal'] ?? d['created_at'])?.toString(),
      status: d['status']?.toString(),
      pelanggan: d['pelanggan']?.toString(),
      kasir: d['kasir']?.toString(),
      tipePembayaran: (d['tipe_pembayaran'] ?? d['metode_bayar'])?.toString(),
      subtotal: _double(d['subtotal']),
      totalDiskon: _double(d['total_diskon']),
      totalPajak: _double(d['total_pajak']),
      grandTotal: _double(d['grand_total'] ?? d['total']),
      dibayar: _double(d['dibayar']),
      kembalian: _double(d['kembalian']),
      items: [
        for (final e in rawItems)
          if (e is Map) _item(Map<String, dynamic>.from(e)),
      ],
    );
  }

  /// POST /transaksi/{id}/batal → batalkan transaksi (stok kembali ke gudang,
  /// jurnal di-reverse di server). Hanya online — tidak diantrekan.
  Future<void> batal(String id) async {
    await _send(() => _dio.post<dynamic>('/transaksi/${Uri.encodeComponent(id)}/batal'));
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
    final body = _map(res.data);
    final ok = code >= 200 && code < 300 && body['success'] == true;
    if (!ok) {
      throw ApiException(
        message: (body['message'] as String?) ?? ApiErrorMapper.statusMessage(code),
        statusCode: code,
      );
    }
    return body;
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
  double _double(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  Transaksi _trx(Map<String, dynamic> m) => Transaksi(
        id: (m['id'] ?? '').toString(),
        nomor: (m['nomor'] ?? m['no'] ?? '-').toString(),
        grandTotal: _double(m['grand_total'] ?? m['total'] ?? m['grandtotal']),
        tanggal: (m['tanggal'] ?? m['created_at'] ?? m['waktu'])?.toString(),
        status: m['status']?.toString(),
        metode: (m['metode_bayar'] ?? m['tipe_pembayaran'] ?? m['metode'])?.toString(),
      );

  TrxItem _item(Map<String, dynamic> m) => TrxItem(
        nama: (m['nama'] ?? m['produk'] ?? '-').toString(),
        kuantitas: _double(m['kuantitas'] ?? m['qty']),
        harga: _double(m['harga']),
        subtotal: _double(m['subtotal']),
      );
}
