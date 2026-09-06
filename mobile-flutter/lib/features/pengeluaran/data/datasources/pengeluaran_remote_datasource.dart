import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/pengeluaran.dart';

class PengeluaranRemoteDataSource {
  PengeluaranRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /pengeluaran?bulan=YYYY-MM → daftar kas keluar bulan itu (array).
  Future<List<Pengeluaran>> list(String bulan) async {
    final body = await _send(
      () => _dio.get<dynamic>('/pengeluaran', queryParameters: {'bulan': bulan}),
    );
    final data = body['data'];
    final rows = data is List
        ? data
        : (data is Map && data['rows'] is List ? data['rows'] as List : const []);
    return [
      for (final e in rows)
        if (e is Map) _item(Map<String, dynamic>.from(e)),
    ];
  }

  /// POST /pengeluaran {keterangan, nominal, tanggal?} (peran O/M; kasir 403).
  Future<void> tambah({
    required String keterangan,
    required double nominal,
    String? tanggal,
  }) => tambahBody({
    'keterangan': keterangan,
    'nominal': nominal,
    if (tanggal != null && tanggal.isNotEmpty) 'tanggal': tanggal,
  });

  /// Kirim badan apa adanya (jalur antrean offline menambah client_ref).
  Future<void> tambahBody(Map<String, dynamic> badan) async {
    await _send(() => _dio.post<dynamic>('/pengeluaran', data: badan));
  }

  /// DELETE /pengeluaran/{id}. Id terenkripsi → di-encode utuh untuk path.
  Future<void> hapus(String id) async {
    await _send(
      () => _dio.delete<dynamic>('/pengeluaran/${Uri.encodeComponent(id)}'),
    );
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

  Pengeluaran _item(Map<String, dynamic> m) => Pengeluaran(
        id: (m['id'] ?? '').toString(),
        tanggal: (m['tanggal'] ?? m['tgl'] ?? '').toString(),
        keterangan: (m['keterangan'] ?? m['catatan'] ?? '-').toString(),
        nominal: _double(m['nominal'] ?? m['jumlah'] ?? m['total']),
      );
}
