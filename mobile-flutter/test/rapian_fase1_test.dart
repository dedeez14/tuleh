// Rapian temuan tinjauan Fase 1 (refund): id transaksi di-encode di SEMUA
// endpoint riwayat, metode pembayaran datang dari server (bukan konstanta),
// dan gerbang Kelola Meja memakai hak akses — bukan nama peran.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/pengaturan/data/datasources/pengaturan_remote_datasource.dart';
import 'package:tuleh_pos/features/riwayat/data/datasources/riwayat_remote_datasource.dart';

class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final ResponseBody Function(RequestOptions o) jawab;
  final permintaan = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    permintaan.add(o);
    return jawab(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
);

Dio _dio(_Server s) =>
    Dio(BaseOptions(baseUrl: 'https://x.test/api', validateStatus: (_) => true))..httpClientAdapter = s;

void main() {
  test('detail() meng-encode id terenkripsi (berisi / dan =) seperti batal() & refund()', () async {
    final server = _Server((_) => _json({'success': true, 'data': {'id': 'x', 'nomor': 'A', 'items': []}}));
    await RiwayatRemoteDataSource(_dio(server)).detail('abc/def==');
    expect(server.permintaan.single.path, '/transaksi/abc%2Fdef%3D%3D');
  });

  test('metodePembayaran() membaca /config payment_methods; bentuk asing → daftar kosong', () async {
    final server = _Server((_) => _json({
      'success': true,
      'data': {'payment_methods': ['TUNAI', 'QRIS', 7, '']},
    }));
    expect(await PengaturanRemoteDataSource(_dio(server)).metodePembayaran(), ['TUNAI', 'QRIS']);
    expect(server.permintaan.single.path, '/config');

    final aneh = _Server((_) => _json({'success': true, 'data': {'payment_methods': 'TUNAI'}}));
    expect(await PengaturanRemoteDataSource(_dio(aneh)).metodePembayaran(), isEmpty);
  });
}
