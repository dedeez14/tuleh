// Kelola Meja (2.26.0): tambah / ubah nomor / nonaktifkan lewat endpoint
// /tables yang baru ada di server MOVERA (9 Sep 2026).
//
// Dua aturan server yang dijaga di sini: kode QR tidak berubah saat meja
// di-rename, dan meja dengan bon terbuka tidak boleh dinonaktifkan.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';
import 'package:tuleh_pos/features/meja/data/datasources/meja_remote_datasource.dart';
import 'package:tuleh_pos/features/meja/presentation/screens/kelola_meja_screen.dart';

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

Map<String, dynamic> _meja({String nomor = '7', bool aktif = true}) => {
  'id': 'MEJA-9',
  'toko_id': 'TOKO-2',
  'nomor': nomor,
  'kode': 'MJ-09',
  'aktif': aktif,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hak akses', () {
    test('hanya OWNER/MANAGER yang melihat Kelola Meja', () {
      expect(bolehKelolaMeja('OWNER'), isTrue);
      expect(bolehKelolaMeja('manager'), isTrue);
      expect(bolehKelolaMeja('KASIR'), isFalse);
      expect(bolehKelolaMeja(null), isFalse);
      expect(bolehKelolaMeja(''), isFalse);
    });
  });

  group('MejaRemoteDataSource', () {
    test('daftarMeja(semua) mengirim ?semua=1 dan membaca penanda aktif', () async {
      final server = _Server((_) => _json({
        'success': true,
        'data': [_meja(), _meja(nomor: '8', aktif: false)],
      }));
      final rows = await MejaRemoteDataSource(_dio(server)).daftarMeja(semua: true);
      expect(server.permintaan.single.path, '/tables');
      expect(server.permintaan.single.queryParameters['semua'], 1);
      expect(rows.length, 2);
      expect(rows.first.aktif, isTrue);
      expect(rows.last.aktif, isFalse);
    });

    test('ubahMeja TIDAK mengirim kode (QR yang tertempel tetap sah)', () async {
      final server = _Server((_) => _json({'success': true, 'data': _meja(nomor: 'A1')}));
      final m = await MejaRemoteDataSource(_dio(server)).ubahMeja('MEJA-9', 'A1');
      final o = server.permintaan.single;
      expect(o.method, 'PUT');
      expect(o.path, '/tables/MEJA-9');
      expect(o.data, {'nomor': 'A1'});
      expect((o.data as Map).containsKey('kode'), isFalse);
      expect(m.nomor, 'A1');
      expect(m.kode, 'MJ-09');
    });

    test('nonaktifkanMeja: 409 dari server diteruskan apa adanya', () async {
      final tolak = _Server((_) => _json({
        'success': false,
        'message': 'Meja 3 masih punya bon BON/0007 yang belum dibayar.',
      }, 409));
      expect(
        () => MejaRemoteDataSource(_dio(tolak)).nonaktifkanMeja('MEJA-3'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.message, 'pesan', contains('BON/0007'))),
      );
    });

    test('peta meja menyembunyikan yang nonaktif', () async {
      final server = _Server((_) => _json({
        'success': true,
        'data': {
          'tables': [_meja(), _meja(nomor: '8', aktif: false)],
        },
      }));
      final rows = await MejaRemoteDataSource(_dio(server)).peta();
      expect(rows.map((m) => m.nomor), ['7']);
    });
  });

  group('DemoEngine /tables', () {
    const toko = {'toko_id': 'TOKO-2'};

    List<Map> daftar(DemoEngine e, {bool semua = false}) =>
        (e.handle(
          method: 'GET',
          path: '/tables',
          query: {...toko, if (semua) 'semua': '1'},
        ).body['data'] as List).cast<Map>();

    test('tambah: nomor wajib & unik; kode QR dibuat mesin demo', () {
      final e = DemoEngine();
      final sebelum = daftar(e).length;

      expect(e.handle(method: 'POST', path: '/tables', query: toko, body: {'nomor': '  '}).status, 422);

      final r = e.handle(method: 'POST', path: '/tables', query: toko, body: {'nomor': '99'});
      expect(r.status, 201);
      expect((r.body['data'] as Map)['kode'], isNotNull);
      expect(daftar(e).length, sebelum + 1);

      final bentrok = e.handle(method: 'POST', path: '/tables', query: toko, body: {'nomor': '99'});
      expect(bentrok.status, 409);
      expect('${bentrok.body['message']}', contains('sudah dipakai'));
    });

    test('ubah nomor tidak mengubah kode QR', () {
      final e = DemoEngine();
      final meja = daftar(e).first;
      final r = e.handle(
        method: 'PUT',
        path: '/tables/${meja['id']}',
        query: toko,
        body: {'nomor': 'A1'},
      );
      expect(r.status, 200);
      expect((r.body['data'] as Map)['nomor'], 'A1');
      expect((r.body['data'] as Map)['kode'], meja['kode']);
      expect(e.handle(method: 'PUT', path: '/tables/TIDAK-ADA', query: toko, body: {'nomor': 'X'}).status, 404);
    });

    test('nonaktifkan: ditolak bila ada bon terbuka, lalu hilang dari peta', () {
      final e = DemoEngine();
      final semuaMeja = daftar(e);
      final meja = semuaMeja.first;

      // Mesin demo sudah menyemai bon berjalan di sebagian meja; pastikan ada
      // satu yang terisi (buka bon bila meja pertama masih kosong).
      final petaAwal = (e.handle(method: 'GET', path: '/bills', query: toko).body['data']
          as Map)['tables'] as List;
      final terisi = petaAwal.cast<Map>().firstWhere(
        (m) => m['bill'] != null,
        orElse: () {
          e.handle(
            method: 'POST',
            path: '/bills',
            query: toko,
            body: {'meja_id': meja['id'], 'pax': 2},
          );
          return {'id': meja['id'], 'nomor': meja['nomor']};
        },
      );

      final tolak = e.handle(method: 'DELETE', path: '/tables/${terisi['id']}', query: toko);
      expect(tolak.status, 409);
      expect('${tolak.body['message']}', contains('belum dibayar'));

      // Meja lain yang kosong bisa dinonaktifkan dan hilang dari peta kasir.
      final kosong = semuaMeja.last;
      final ok = e.handle(method: 'DELETE', path: '/tables/${kosong['id']}', query: toko);
      expect(ok.status, 200);
      expect((ok.body['data'] as Map)['aktif'], false);

      final peta = (e.handle(method: 'GET', path: '/bills', query: toko).body['data']
          as Map)['tables'] as List;
      expect(peta.any((m) => (m as Map)['id'] == kosong['id']), isFalse);
      expect(daftar(e).any((m) => m['id'] == kosong['id']), isFalse);
      expect(daftar(e, semua: true).any((m) => m['id'] == kosong['id']), isTrue);
    });
  });
}
