import 'package:dio/dio.dart';

import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/api_exception.dart';
import '../../../sesi/domain/entities/sesi_rekap.dart';
import '../../domain/entities/laporan_keuangan.dart';
import '../../domain/entities/penjualan_hari.dart';
import '../../domain/entities/penjualan_produk.dart';

class LaporanRemoteDataSource {
  LaporanRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /laporan/keuangan → ringkasan bulan berjalan.
  Future<LaporanKeuangan> keuangan() async {
    final body = await _send(() => _dio.get<dynamic>('/laporan/keuangan'));
    final d = _map(body['data']);
    return LaporanKeuangan(
      bulan: (d['bulan'] ?? '').toString(),
      omset: _double(d['omset']),
      jumlahTransaksi: _int(d['jumlah_transaksi']),
      pengeluaran: _double(d['pengeluaran']),
      laba: _double(d['laba']),
    );
  }

  /// GET /laporan/penjualan-harian → rows[] penjualan per hari.
  Future<List<PenjualanHari>> penjualanHarian() async {
    final body = await _send(() => _dio.get<dynamic>('/laporan/penjualan-harian'));
    final d = _map(body['data']);
    final rows = d['rows'] is List ? d['rows'] as List : const [];
    return [
      for (final e in rows)
        if (e is Map)
          PenjualanHari(
            tanggal: (Map<String, dynamic>.from(e)['tanggal'] ?? '').toString(),
            jumlahTransaksi: _int(Map<String, dynamic>.from(e)['jumlah_transaksi']),
            totalOmzet: _double(Map<String, dynamic>.from(e)['total_omzet']),
          ),
    ];
  }

  /// GET /laporan/penjualan-produk → produk terlaris, terurut nilai terbesar.
  /// Server bisa membalas list langsung atau {rows: []} seperti laporan lain.
  Future<List<PenjualanProduk>> penjualanProduk() async {
    final body = await _send(() => _dio.get<dynamic>('/laporan/penjualan-produk'));
    final data = body['data'];
    final rows = data is List
        ? data
        : (data is Map && data['rows'] is List ? data['rows'] as List : const []);
    final hasil = [
      for (final e in rows)
        if (e is Map)
          PenjualanProduk(
            produk: (Map<String, dynamic>.from(e)['produk'] ??
                    Map<String, dynamic>.from(e)['nama'] ??
                    '-')
                .toString(),
            qtyTerjual: _double(Map<String, dynamic>.from(e)['qty_terjual']),
            totalNilai: _double(Map<String, dynamic>.from(e)['total_nilai']),
          ),
    ];
    hasil.sort((a, b) => b.totalNilai.compareTo(a.totalNilai));
    return hasil;
  }

  /// GET /laporan/rekap-kasir → daftar sesi kasir + total (bentuk = SesiRekap).
  Future<List<SesiRekap>> rekapKasir() async {
    final body = await _send(() => _dio.get<dynamic>('/laporan/rekap-kasir'));
    final data = body['data'];
    final rows = data is List
        ? data
        : (data is Map && data['rows'] is List ? data['rows'] as List : const []);
    return [
      for (final e in rows)
        if (e is Map) SesiRekap.fromJson(Map<String, dynamic>.from(e)),
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
  int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
}
