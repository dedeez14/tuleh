// Fondasi hak akses Android (padanan akses.js desktop): daftar `akses[]` dari
// server adalah SATU-SATUNYA sumber; tanpa daftar = tanpa hak (gagal-tertutup).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/akses/akses.dart';
import 'package:tuleh_pos/features/auth/data/datasources/auth_remote_datasource.dart';

class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final ResponseBody Function(RequestOptions o) jawab;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async => jawab(o);

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
  test('bisaDenganDaftar hanya membaca daftar dari server; null/kosong = tidak ada hak', () {
    expect(bisaDenganDaftar(['kasir.transaksi', 'transaksi.refund'], 'transaksi.refund'), isTrue);
    expect(bisaDenganDaftar(['kasir.transaksi'], 'transaksi.refund'), isFalse);
    expect(bisaDenganDaftar(null, 'kasir.transaksi'), isFalse);
    expect(bisaDenganDaftar(const <String>[], 'kasir.transaksi'), isFalse);
  });

  test('/auth/me: akses[] (hanya string) dan peran.nama masuk ke User; server lama tanpa akses = kosong', () async {
    final baru = await AuthRemoteDataSource(_dio(_Server((_) => _json({
      'success': true,
      'data': {
        'user': {'id': 7, 'name': 'Manager Toko'},
        'akses': ['kasir.transaksi', 'transaksi.refund', 12, ''],
        'peran': {'nama': 'Manajer'},
        'company': {'nama': 'Warung'},
      },
    })))).me();
    expect(baru.akses, ['kasir.transaksi', 'transaksi.refund']);
    expect(baru.peran, 'Manajer');

    final lama = await AuthRemoteDataSource(_dio(_Server((_) => _json({
      'success': true,
      'data': {'user': {'id': 1, 'name': 'A'}},
    })))).me();
    expect(lama.akses, isEmpty);
    expect(lama.peran, isNull);
  });
}
