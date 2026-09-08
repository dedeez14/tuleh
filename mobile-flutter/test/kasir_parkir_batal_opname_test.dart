// Fitur 2.17.0: parkir keranjang (penyimpan berkas per toko), pembatalan
// transaksi (server & Mode Demo), opname stok (server & Mode Demo).

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';
import 'package:tuleh_pos/features/inventory/data/datasources/inventory_remote_datasource.dart';
import 'package:tuleh_pos/features/kasir/data/parkir_store.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/keranjang_meta.dart';
import 'package:tuleh_pos/features/pelanggan/domain/entities/pelanggan.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/riwayat/data/datasources/riwayat_remote_datasource.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';

const _kopi = Product(id: 'P1', nama: 'Kopi Susu', harga: 18000, stok: 10, satuan: 'cup');
const _roti = Product(id: 'P2', nama: 'Roti Bakar', harga: 15000, tipe: 'PRODUK', promo: true, hargaNormal: 17000);
const _jasa = Product(id: 'J1', nama: 'Antar', harga: 5000, tipe: 'JASA');

/// Server palsu: mencatat permintaan terakhir dan menjawab sesuai [jawab].
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

// Seperti api_client: 4xx/5xx dikembalikan sebagai Response (bukan exception).
Dio _dio(_Server s) =>
    Dio(BaseOptions(baseUrl: 'https://x.test/api', validateStatus: (_) => true))..httpClientAdapter = s;

/// Penyimpan yang pembacaannya selalu gagal — meniru berkas terkunci/izin.
class _StoreBacaGagal extends ParkirStore {
  _StoreBacaGagal(Directory dir) : super(dir: (() async => dir));
  @override
  Future<List<KeranjangParkir>> daftar(String? tokoId) async =>
      throw const ParkirTidakTerbaca('uji');
}

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('parkir-');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ParkirStore store({DateTime Function()? jam}) => ParkirStore(dir: () async => tmp, jam: jam);

  group('ParkirStore', () {
    test('simpan → daftar → ambil: item, kuantitas, meta utuh; nomor berurut', () async {
      final s = store(jam: () => DateTime(2026, 9, 8, 10, 30));
      const meta = KeranjangMeta(
        pelanggan: Pelanggan(id: 'C1', nama: 'Bu Sari', telepon: '0812'),
        diskonPersen: 10,
        catatan: 'tanpa es',
      );
      final a = await s.simpan('TOKO-1', items: const [CartItem(product: _kopi, qty: 2), CartItem(product: _roti, qty: 1)], meta: meta);
      final b = await s.simpan('TOKO-1', items: const [CartItem(product: _jasa, qty: 1)]);
      expect(a.nomor, 1);
      expect(b.nomor, 2);
      expect(a.jumlahItem, 3);
      expect(a.totalKotor, 51000);
      expect(a.total, 45900); // diskon 10 %
      expect(a.ringkasan, '2× Kopi Susu, 1× Roti Bakar');

      final daftar = await s.daftar('TOKO-1');
      expect(daftar.map((p) => p.id), [a.id, b.id]);
      final ulang = daftar.first;
      expect(ulang.waktu, DateTime(2026, 9, 8, 10, 30));
      expect(ulang.items.length, 2);
      expect(ulang.items.first.product, _kopi); // freezed: semua field sama
      expect(ulang.items[1].product.promo, isTrue);
      expect(ulang.items[1].product.hargaNormal, 17000);
      expect(ulang.meta.pelanggan?.nama, 'Bu Sari');
      expect(ulang.meta.pelanggan?.telepon, '0812');
      expect(ulang.meta.diskonPersen, 10);
      expect(ulang.meta.catatan, 'tanpa es');

      // Toko lain tidak melihat parkir toko ini.
      expect(await s.daftar('TOKO-2'), isEmpty);

      final diambil = await s.ambil('TOKO-1', a.id);
      expect(diambil?.id, a.id);
      expect((await s.daftar('TOKO-1')).map((p) => p.id), [b.id]);
      expect(await s.ambil('TOKO-1', a.id), isNull, reason: 'sudah diambil');

      await s.hapus('TOKO-1', b.id);
      expect(await s.daftar('TOKO-1'), isEmpty);
    });

    test('nomor melanjutkan yang terbesar dan berputar setelah 999', () async {
      final s = store();
      final f = File('${tmp.path}/parkir/TOKO-1.json');
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode([
        {
          'id': 'x', 'nomor': 999, 'waktu': '2026-09-08T09:00:00',
          'items': [{'qty': 1, 'produk': {'id': 'P1', 'nama': 'Kopi', 'harga': 1000}}],
        },
      ]));
      final baru = await s.simpan('TOKO-1', items: const [CartItem(product: _kopi, qty: 1)]);
      expect(baru.nomor, 1);
    });

    test('penuh pada $maksParkir → ParkirPenuh dengan pesan jelas; keranjang kosong ditolak', () async {
      final s = store();
      for (var i = 0; i < maksParkir; i++) {
        await s.simpan('TOKO-1', items: const [CartItem(product: _kopi, qty: 1)]);
      }
      expect(
        () => s.simpan('TOKO-1', items: const [CartItem(product: _kopi, qty: 1)]),
        throwsA(isA<ParkirPenuh>().having((e) => e.pesan, 'pesan', contains('Maksimal $maksParkir'))),
      );
      expect(() => s.simpan('TOKO-1', items: const []), throwsArgumentError);
      expect((await s.daftar('TOKO-1')).length, maksParkir);
    });

    test('berkas rusak disisihkan (.rusak) lalu mulai kosong', () async {
      final s = store();
      final f = File('${tmp.path}/parkir/TOKO-1.json');
      await f.parent.create(recursive: true);
      await f.writeAsString('{bukan json');
      expect(await s.daftar('TOKO-1'), isEmpty);
      // Isinya tidak dibuang diam-diam: masih bisa diselamatkan manual.
      expect(await File('${f.path}.rusak').exists(), isTrue);
      expect(await File('${f.path}.rusak').readAsString(), '{bukan json');
      // Memarkir lagi setelah itu tetap bisa.
      final baru = await s.simpan('TOKO-1', items: const [CartItem(product: _kopi, qty: 1)]);
      expect((await s.daftar('TOKO-1')).single.id, baru.id);
      await f.writeAsString(jsonEncode([
        {'id': 'kosong', 'nomor': 1, 'items': []},
        {'id': 'tanpa-harga', 'nomor': 2, 'items': [{'qty': 1, 'produk': {'id': 'P9', 'nama': 'X'}}]},
        {'id': 'sah', 'nomor': 3, 'waktu': 'x', 'items': [{'qty': 2, 'produk': {'id': 'P1', 'nama': 'Kopi', 'harga': 1000}}]},
      ]));
      final daftar = await s.daftar('TOKO-1');
      expect(daftar.map((p) => p.id), ['sah']);
      expect(daftar.single.total, 2000);
    });

    test('baca gagal → simpan menolak, berkas lama tidak tertimpa', () async {
      // Isi berkas dengan satu keranjang yang sah lebih dulu.
      final asli = store();
      await asli.simpan('TOKO-1', items: const [CartItem(product: _kopi, qty: 2)]);
      final f = File('${tmp.path}/parkir/TOKO-1.json');
      final sebelum = await f.readAsString();

      // Penyimpan yang pembacaannya gagal (mis. berkas terkunci proses lain).
      final rusak = _StoreBacaGagal(tmp);
      await expectLater(rusak.daftar('TOKO-1'), throwsA(isA<ParkirTidakTerbaca>()));
      await expectLater(
        rusak.simpan('TOKO-1', items: const [CartItem(product: _roti, qty: 1)]),
        throwsA(isA<ParkirTidakTerbaca>()),
        reason: 'menulis daftar kosong akan menghapus keranjang yang sudah ada',
      );
      expect(await f.readAsString(), sebelum, reason: 'berkas lama utuh');
    });

    test('id toko terenkripsi panjang menghasilkan nama berkas wajar & tetap', () async {
      final s = store();
      final panjang = 'eyJpdiI6${'a' * 260}=';
      await s.simpan(panjang, items: const [CartItem(product: _kopi, qty: 1)]);
      final berkas = tmp.listSync(recursive: true).whereType<File>().map((f) => f.uri.pathSegments.last).toList();
      expect(berkas.length, 1);
      expect(berkas.single.length, lessThan(70));
      expect((await s.daftar(panjang)).length, 1);
    });
  });

  group('RiwayatRemoteDataSource.batal', () {
    test('POST /transaksi/{id}/batal; id di-encode; galat server jadi ApiException', () async {
      final server = _Server((o) => o.path.contains('/batal')
          ? _json({'success': true, 'data': {'id': 'T1', 'status': 'DIBATALKAN'}})
          : _json({'success': false, 'message': 'x'}, 404));
      final ds = RiwayatRemoteDataSource(_dio(server));
      await ds.batal('abc/def==');
      expect(server.permintaan.single.method, 'POST');
      expect(server.permintaan.single.path, '/transaksi/abc%2Fdef%3D%3D/batal');

      final tolak = _Server((o) => _json({'success': false, 'message': 'Transaksi sudah dibatalkan.'}, 409));
      expect(
        () => RiwayatRemoteDataSource(_dio(tolak)).batal('T1'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.message, 'pesan', 'Transaksi sudah dibatalkan.')),
      );
    });
  });

  group('InventoryRemoteDataSource.opnameBody', () {
    test('POST /inventory/opname dengan badan apa adanya; 422 diteruskan', () async {
      final server = _Server((o) => _json({'success': true, 'data': {'stok_sekarang': 7}}));
      await InventoryRemoteDataSource(_dio(server)).opnameBody({'id_produk': 'P1', 'jumlah': 3, 'keterangan': 'rusak', 'client_ref': 'c1'});
      final o = server.permintaan.single;
      expect(o.path, '/inventory/opname');
      expect(o.data, {'id_produk': 'P1', 'jumlah': 3, 'keterangan': 'rusak', 'client_ref': 'c1'});

      final tolak = _Server((o) => _json({'success': false, 'message': 'Stok tidak mencukupi'}, 422));
      expect(
        () => InventoryRemoteDataSource(_dio(tolak)).opnameBody({'id_produk': 'P1', 'jumlah': 99}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
      );
    });
  });

  group('DemoEngine', () {
    const toko = {'toko_id': 'TOKO-1'};

    Map<String, dynamic> produkBerstok(DemoEngine e) {
      final daftar = (e.handle(method: 'GET', path: '/produk', query: toko).body['data'] as List).cast<Map>();
      return Map<String, dynamic>.from(daftar.firstWhere((p) => p['kelola_stok'] == true && (p['stok'] as num) >= 5));
    }

    num stok(DemoEngine e, String id) {
      final daftar = (e.handle(method: 'GET', path: '/produk', query: {...toko, 'include_habis': '1'}).body['data'] as List).cast<Map>();
      return daftar.firstWhere((p) => p['id'] == id)['stok'] as num;
    }

    test('batal transaksi: status DIBATALKAN, stok kembali, sesi berkurang; ulang → 409', () {
      final e = DemoEngine();
      final p = produkBerstok(e);
      final awal = stok(e, '${p['id']}');
      final sesiSebelum = Map<String, dynamic>.from(e.handle(method: 'GET', path: '/sesi/aktif', query: toko).body['data'] as Map);
      final bayar = e.handle(
        method: 'POST',
        path: '/transaksi/checkout',
        query: toko,
        body: {
          'items': [{'id_produk': p['id'], 'kuantitas': 2, 'harga': p['harga_jual']}],
          'tipe_pembayaran': 'TUNAI',
          'dibayar': (p['harga_jual'] as num) * 2,
        },
      );
      expect(bayar.status, 201);
      final id = '${(bayar.body['data'] as Map)['id']}';
      expect(stok(e, '${p['id']}'), awal - 2);

      final batal = e.handle(method: 'POST', path: '/transaksi/$id/batal', query: toko);
      expect(batal.status, 200);
      expect((batal.body['data'] as Map)['status'], 'DIBATALKAN');
      expect(stok(e, '${p['id']}'), awal, reason: 'stok kembali');

      final detail = e.handle(method: 'GET', path: '/transaksi/$id', query: toko);
      expect((detail.body['data'] as Map)['status'], 'DIBATALKAN');

      final sesi = Map<String, dynamic>.from(e.handle(method: 'GET', path: '/sesi/aktif', query: toko).body['data'] as Map);
      expect(sesi['total_penjualan'], sesiSebelum['total_penjualan']);
      expect(sesi['jumlah_transaksi'], sesiSebelum['jumlah_transaksi']);

      final ulang = e.handle(method: 'POST', path: '/transaksi/$id/batal', query: toko);
      expect(ulang.status, 409);
      expect(e.handle(method: 'POST', path: '/transaksi/TIDAK-ADA/batal', query: toko).status, 404);
    });

    test('opname: stok berkurang; melebihi stok / jasa / nol ditolak 422', () {
      final e = DemoEngine();
      final p = produkBerstok(e);
      final awal = stok(e, '${p['id']}');
      final ok = e.handle(method: 'POST', path: '/inventory/opname', query: toko, body: {'id_produk': p['id'], 'jumlah': 3, 'keterangan': 'rusak'});
      expect(ok.status, 200);
      expect((ok.body['data'] as Map)['stok_sekarang'], awal - 3);
      expect(stok(e, '${p['id']}'), awal - 3);

      final lebih = e.handle(method: 'POST', path: '/inventory/opname', query: toko, body: {'id_produk': p['id'], 'jumlah': awal + 100});
      expect(lebih.status, 422);
      expect(lebih.body['message'], contains('tidak mencukupi'));
      expect(e.handle(method: 'POST', path: '/inventory/opname', query: toko, body: {'id_produk': p['id'], 'jumlah': 0}).status, 422);

      final daftar = (e.handle(method: 'GET', path: '/produk', query: toko).body['data'] as List).cast<Map>();
      final jasa = daftar.where((x) => x['kelola_stok'] != true);
      if (jasa.isNotEmpty) {
        final r = e.handle(method: 'POST', path: '/inventory/opname', query: toko, body: {'id_produk': jasa.first['id'], 'jumlah': 1});
        expect(r.status, 422);
        expect(r.body['message'], contains('tidak mengelola stok'));
      }
    });
  });
}
