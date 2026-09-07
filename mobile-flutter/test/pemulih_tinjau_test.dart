import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/antrean_tulis.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/pemulih_tinjau.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/rujukan_lokal.dart';
import 'package:tuleh_pos/features/meja/data/datasources/meja_remote_datasource.dart';
import 'package:tuleh_pos/features/meja/data/repositories/meja_offline_repository.dart';

/// Pemulihan otomatis TINJAU "mungkin sudah sampai": dicocokkan ke daftar
/// transaksi server (total, metode, waktu ±15 menit); satu cocok → TERKIRIM,
/// tak ada → kirim ulang, ganda → tetap TINJAU dengan petunjuk. Juga delta
/// stok saat bayar bon dari ronde lokal.

class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final Object Function(RequestOptions o) jawab;
  final List<RequestOptions> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    log.add(o);
    final r = jawab(o);
    if (r is DioExceptionType) throw DioException(requestOptions: o, type: r);
    final (int code, Map<String, dynamic> body) = r as (int, Map<String, dynamic>);
    return ResponseBody.fromString(jsonEncode(body), code, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Server s) => Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = s;

const _pesanTimeout = 'Server tidak menjawab setelah data dikirim. Periksa dulu.';

Future<AntreanMemori> _antreanDengan(List<(String ref, double total, String tipe, DateTime waktu)> baris) async {
  final a = AntreanMemori();
  for (final (ref, total, tipe, waktu) in baris) {
    await a.antrekan(
      PesanAntrean(
        urut: 0, clientRef: ref, jenis: 'CHECKOUT', path: '/transaksi/checkout',
        body: {
          'items': [{'id_produk': 'P1', 'kuantitas': 1, 'harga': total}],
          'tipe_pembayaran': tipe, 'dibayar': total, 'waktu_klien': waktu.toIso8601String(),
        },
        dibuat: waktu, tokoId: 'T1', status: StatusAntrean.tinjau, galatTerakhir: _pesanTimeout,
      ),
      transaksi: TransaksiTertunda(
        clientRef: ref, tokoId: 'T1', nomorLokal: 'L-$ref', tipePembayaran: tipe,
        grandTotal: total, dibayar: total, waktuKlien: waktu, strukJson: '{}',
      ),
    );
  }
  return a;
}

Map<String, dynamic> _daftar(List<Map<String, dynamic>> rows) => {'success': true, 'data': rows};

void main() {
  final jam = DateTime(2026, 9, 8, 14, 0);
  Map<String, dynamic> trx(String id, double total, String tipe, DateTime t, {String status = 'SELESAI'}) => {
    'id': id, 'nomor': 'N-$id', 'grand_total': total, 'tipe_pembayaran': tipe,
    'status': status, 'tanggal': t.toUtc().toIso8601String(),
  };

  test('satu kandidat cocok → TERKIRIM dengan nomor server; transaksi lokal dibuang', () async {
    final a = await _antreanDengan([('a', 25000, 'TUNAI', jam)]);
    final server = _Server((o) => (200, _daftar([
      trx('s1', 25000, 'TUNAI', jam.add(const Duration(minutes: 3))),
      trx('s2', 25000, 'QRIS', jam), // metode beda → bukan kandidat
      trx('s3', 25000, 'TUNAI', jam.subtract(const Duration(hours: 2))), // di luar jendela
      trx('s4', 25000, 'TUNAI', jam, status: 'DIBATALKAN'),
    ])));
    final n = await PemulihTinjau(store: a, dio: _dio(server)).jalankan();
    expect(n, 1);
    final p = (await a.cari('a'))!;
    expect(p.status, StatusAntrean.terkirim);
    expect(p.hasil!['nomor'], 'N-s1');
    expect(p.hasil!['dipulihkan'], isTrue);
    expect(await a.transaksiLokal('a'), isNull);
    final q = server.log.single.queryParameters;
    expect(q['toko_id'], 'T1');
    expect(q['dari'], '2026-09-07');
    expect(q['sampai'], '2026-09-09');
  });

  test('tidak ada kandidat → kembali MENUNGGU dan dikirim ulang oleh pengurai di putaran yang sama', () async {
    final a = await _antreanDengan([('a', 25000, 'TUNAI', jam)]);
    var kirim = 0;
    final server = _Server((o) {
      if (o.path == '/transaksi' && o.method == 'GET') return (200, _daftar([trx('x', 99000, 'TUNAI', jam)]));
      kirim++;
      return (201, {'success': true, 'data': {'nomor': '26-POS-000077'}});
    });
    final dio = _dio(server);
    final pengurai = PenguraiAntrean(store: a, dio: dio, koneksi: null);
    expect(await pengurai.jalankan(), 1);
    expect(kirim, 1);
    final p = (await a.cari('a'))!;
    expect(p.status, StatusAntrean.terkirim);
    expect(p.hasil!['nomor'], '26-POS-000077');
    pengurai.hentikan();
  });

  test('kandidat ganda → tetap TINJAU dengan petunjuk nomor; daftar gagal ditarik → tidak diputuskan', () async {
    final a = await _antreanDengan([('a', 25000, 'TUNAI', jam)]);
    final ganda = _Server((o) => (200, _daftar([
      trx('s1', 25000, 'TUNAI', jam.add(const Duration(minutes: 2))),
      trx('s2', 25000, 'TUNAI', jam.subtract(const Duration(minutes: 4))),
    ])));
    expect(await PemulihTinjau(store: a, dio: _dio(ganda)).jalankan(), 0);
    var p = (await a.cari('a'))!;
    expect(p.status, StatusAntrean.tinjau);
    expect(p.galatTerakhir, contains('N-s1, N-s2'));
    expect(PemulihTinjau.layakDipulihkan(p), isFalse, reason: 'sudah jadi keputusan kasir');

    final b = await _antreanDengan([('b', 25000, 'TUNAI', jam)]);
    final putus = _Server((_) => DioExceptionType.connectionError);
    expect(await PemulihTinjau(store: b, dio: _dio(putus)).jalankan(), 0);
    p = (await b.cari('b'))!;
    expect(p.status, StatusAntrean.tinjau);
    expect(p.galatTerakhir, _pesanTimeout);
  });

  test('dua baris TINJAU tidak mengklaim transaksi server yang sama', () async {
    final a = await _antreanDengan([('a', 25000, 'TUNAI', jam), ('b', 25000, 'TUNAI', jam.add(const Duration(minutes: 1)))]);
    final server = _Server((o) => (200, _daftar([trx('s1', 25000, 'TUNAI', jam)])));
    final n = await PemulihTinjau(store: a, dio: _dio(server)).jalankan();
    expect(n, 2);
    expect((await a.cari('a'))!.status, StatusAntrean.terkirim);
    expect((await a.cari('b'))!.status, StatusAntrean.menunggu, reason: 's1 sudah diklaim a → b dikirim ulang');
    expect(server.log.length, 1, reason: 'daftar per toko+tanggal ditarik sekali');
  });

  test('bayar bon: delta stok dari ronde lokal yang produknya berstok', () async {
    final store = AntreanMemori();
    final penanda = _PenandaOffline();
    final server = _Server((_) => DioExceptionType.connectionError);
    final repo = MejaOfflineRepository(
      remote: MejaRemoteDataSource(_dio(server)),
      antrean: store,
      tulis: AntreanTulis(antrean: store, koneksi: penanda, tokoId: 'T1'),
      tokoId: 'T1',
    );
    final buka = (await repo.bukaBon('M1')).when(ok: (h) => h, err: (e) => throw e);
    final idLokal = rujukanLokal(buka.clientRef!);
    await repo.tambahRonde(idLokal, [{'id_produk': 'P1', 'kuantitas': 2}, {'id_produk': 'J1', 'kuantitas': 1}], tampilan: [
      {'id_produk': 'P1', 'nama': 'Teh', 'harga': 4000, 'kuantitas': 2, 'kelola_stok': true},
      {'id_produk': 'J1', 'nama': 'Jasa', 'harga': 10000, 'kuantitas': 1, 'kelola_stok': false},
    ]);
    expect(await store.deltaStokTertunda(), isEmpty, reason: 'stok belum berkurang saat ronde');
    await repo.bayar(idLokal, tipe: 'TUNAI', dibayar: 18000);
    expect(await store.deltaStokTertunda(), {'P1': -2});
  });
}

class _PenandaOffline implements PenandaKoneksi {
  @override
  bool get offline => true;
  @override
  void tandaiOffline({DateTime? ditarikPada}) {}
  @override
  void tandaiOnline() {}
}
