// Produk terlaris (2.21.0): GET /laporan/penjualan-produk di Android —
// endpoint yang sudah lama dipakai desktop tetapi belum ada di aplikasi HP.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';
import 'package:tuleh_pos/features/laporan/data/datasources/laporan_remote_datasource.dart';
import 'package:tuleh_pos/features/laporan/data/repositories/laporan_repository_impl.dart';

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
    Dio(BaseOptions(baseUrl: 'https://x.test/api', validateStatus: (_) => true))
      ..httpClientAdapter = s;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LaporanRemoteDataSource.penjualanProduk', () {
    test('membaca list langsung dan mengurutkan menurun menurut nilai', () async {
      final server = _Server((_) => _json({
        'success': true,
        'data': [
          {'produk': 'Es Teh', 'qty_terjual': 200, 'total_nilai': 600000},
          {'produk': 'Kopi Susu', 'qty_terjual': 120, 'total_nilai': 2160000},
          {'produk': 'Roti Bakar', 'qty_terjual': 45, 'total_nilai': 675000},
        ],
      }));
      final rows = await LaporanRemoteDataSource(_dio(server)).penjualanProduk();
      expect(server.permintaan.single.path, '/laporan/penjualan-produk');
      expect([for (final r in rows) r.produk], ['Kopi Susu', 'Roti Bakar', 'Es Teh']);
      expect(rows.first.qtyTerjual, 120);
      expect(rows.first.totalNilai, 2160000);
    });

    test('menerima bentuk {rows: []} dan nama field alternatif', () async {
      final server = _Server((_) => _json({
        'success': true,
        'data': {
          'rows': [
            {'nama': 'Gula 1kg', 'qty_terjual': '3', 'total_nilai': '45000'},
          ],
        },
      }));
      final rows = await LaporanRemoteDataSource(_dio(server)).penjualanProduk();
      expect(rows.single.produk, 'Gula 1kg');
      expect(rows.single.qtyTerjual, 3);
      expect(rows.single.totalNilai, 45000);
    });

    test('data kosong / bentuk tak terduga → daftar kosong, bukan galat', () async {
      for (final data in [<dynamic>[], null, 'bukan-list']) {
        final server = _Server((_) => _json({'success': true, 'data': data}));
        expect(await LaporanRemoteDataSource(_dio(server)).penjualanProduk(), isEmpty);
      }
    });

    test('galat server diteruskan sebagai ApiException', () async {
      final server = _Server((_) => _json({'success': false, 'message': 'Tidak diizinkan.'}, 403));
      expect(
        () => LaporanRemoteDataSource(_dio(server)).penjualanProduk(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });
  });

  group('DemoEngine /laporan/penjualan-produk', () {
    const toko = {'toko_id': 'TOKO-1'};

    test('mengakumulasi item transaksi selesai dan mengurutkan menurun', () {
      final e = DemoEngine();
      final rows = (e.handle(method: 'GET', path: '/laporan/penjualan-produk', query: toko)
              .body['data'] as List)
          .cast<Map>();
      expect(rows, isNotEmpty, reason: 'mesin demo menyemai transaksi');
      for (var i = 1; i < rows.length; i++) {
        expect(
          (rows[i - 1]['total_nilai'] as num) >= (rows[i]['total_nilai'] as num),
          isTrue,
          reason: 'urut menurun menurut nilai',
        );
      }
      expect(rows.first.keys, containsAll(['produk', 'qty_terjual', 'total_nilai']));
    });

    test('checkout baru menambah kuantitas produk yang bersangkutan', () {
      final e = DemoEngine();
      final produk = ((e.handle(method: 'GET', path: '/produk', query: toko).body['data'] as List)
              .first as Map)
          .cast<String, dynamic>();
      double nilai(String nama) {
        final rows = (e.handle(method: 'GET', path: '/laporan/penjualan-produk', query: toko)
                .body['data'] as List)
            .cast<Map>();
        for (final r in rows) {
          if (r['produk'] == nama) return (r['qty_terjual'] as num).toDouble();
        }
        return 0;
      }

      final sebelum = nilai('${produk['nama']}');
      final bayar = e.handle(
        method: 'POST',
        path: '/transaksi/checkout',
        query: toko,
        body: {
          'items': [
            {'id_produk': produk['id'], 'kuantitas': 3, 'harga': produk['harga_jual']},
          ],
          'tipe_pembayaran': 'QRIS',
          'dibayar': (produk['harga_jual'] as num) * 3,
        },
      );
      expect(bayar.status, 201);
      expect(nilai('${produk['nama']}'), sebelum + 3);

      // Transaksi yang dibatalkan tidak lagi dihitung sebagai terjual.
      final id = '${(bayar.body['data'] as Map)['id']}';
      e.handle(method: 'POST', path: '/transaksi/$id/batal', query: toko);
      expect(nilai('${produk['nama']}'), sebelum);
    });
  });

  group('LaporanRepositoryImpl.penjualanProduk', () {
    LaporanRepositoryImpl repo(int status) => LaporanRepositoryImpl(
      LaporanRemoteDataSource(
        _dio(_Server((_) => _json({'success': false, 'message': 'x'}, status))),
      ),
    );

    test('server tanpa endpoint (404/405) → daftar kosong, laporan tetap utuh', () async {
      for (final status in [404, 405]) {
        final r = await repo(status).penjualanProduk();
        expect(r.isOk, isTrue, reason: 'status $status');
        expect(r.valueOrNull, isEmpty);
      }
    });

    test('galat lain tetap dilaporkan sebagai Err', () async {
      for (final status in [401, 403, 500]) {
        final r = await repo(status).penjualanProduk();
        expect(r.isOk, isFalse, reason: 'status $status');
      }
    });
  });
}
