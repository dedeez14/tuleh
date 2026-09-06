import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/bill_detail.dart';
import '../../domain/entities/meja.dart';

class MejaRemoteDataSource {
  MejaRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /bills → { tables: [{id, nomor, kode, bill}] } (peta meja + status bon).
  Future<List<Meja>> peta() async {
    final body = await _send(() => _dio.get<dynamic>('/bills'));
    final data = body['data'];
    final tables = data is Map && data['tables'] is List ? data['tables'] as List : const [];
    return [
      for (final t in tables)
        if (t is Map) _meja(Map<String, dynamic>.from(t)),
    ];
  }

  /// POST /bills → buka bon. `meja_id` + `pax` (kontrak Electron); meja_id_dec
  /// disertakan utk kompatibilitas (server men-dekode sendiri).
  Future<void> bukaBon(String mejaId, {int pax = 1}) async {
    await _send(() => _dio.post<dynamic>('/bills', data: {
          'meja_id': mejaId,
          'meja_id_dec': mejaId,
          'pax': pax,
        }));
  }

  /// GET /bills/{id} → detail bon (item agregat + total).
  Future<BillDetail> detail(String id) async {
    final body = await _send(() => _dio.get<dynamic>('/bills/$id'));
    final d = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
    final rawItems = d['items'] is List ? d['items'] as List : const [];
    return BillDetail(
      id: (d['id'] ?? id).toString(),
      nomor: (d['nomor'] ?? '-').toString(),
      label: d['label']?.toString(),
      pax: d['pax'] is num ? (d['pax'] as num).toInt() : null,
      status: d['status']?.toString(),
      total: _double(d['total'] ?? d['grand_total']),
      items: [
        for (final e in rawItems)
          if (e is Map) _billItem(Map<String, dynamic>.from(e)),
      ],
    );
  }

  /// POST /bills/{id}/rounds → tambah ronde (pesanan) ke bon.
  Future<void> tambahRonde(String id, List<Map<String, dynamic>> items) async {
    await _send(() => _dio.post<dynamic>('/bills/$id/rounds', data: {'items': items}));
  }

  /// POST /bills/{id}/settle → bayar & tutup bon.
  Future<void> bayar(String id, {required String tipe, required double dibayar}) async {
    await _send(() => _dio.post<dynamic>('/bills/$id/settle', data: {
          'tipe_pembayaran': tipe,
          'dibayar': dibayar,
        }));
  }

  // ---- varian badan apa adanya (jalur antrean offline; badan sudah memuat
  // client_ref & waktu_klien) ----
  Future<void> bukaBonBody(Map<String, dynamic> badan) async {
    await _send(() => _dio.post<dynamic>('/bills', data: badan));
  }

  Future<void> tambahRondeBody(String id, Map<String, dynamic> badan) async {
    await _send(() => _dio.post<dynamic>('/bills/$id/rounds', data: badan));
  }

  Future<void> bayarBody(String id, Map<String, dynamic> badan) async {
    await _send(() => _dio.post<dynamic>('/bills/$id/settle', data: badan));
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

  BillItem _billItem(Map<String, dynamic> m) {
    final kuantitas = _double(m['kuantitas'] ?? m['qty']);
    final harga = _double(m['harga']);
    final sub = _double(m['subtotal']);
    return BillItem(
      nama: (m['nama'] ?? m['produk'] ?? '-').toString(),
      kuantitas: kuantitas,
      harga: harga,
      subtotal: sub > 0 ? sub : harga * kuantitas, // fallback bila agregat kosong
    );
  }

  Meja _meja(Map<String, dynamic> m) {
    final bill = m['bill'] is Map ? Map<String, dynamic>.from(m['bill'] as Map) : null;
    return Meja(
      id: (m['id'] ?? '').toString(),
      nomor: (m['nomor'] ?? m['no'] ?? '-').toString(),
      kode: m['kode']?.toString(),
      billId: bill?['id']?.toString(),
      billTotal: bill == null ? null : _double(bill['total'] ?? bill['grand_total'] ?? bill['subtotal']),
      pax: bill?['pax'] is num ? (bill!['pax'] as num).toInt() : null,
    );
  }
}
