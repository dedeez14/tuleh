import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/antrean_tulis.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/nomor_lokal.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/salinan_db.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/kasir/data/checkout_repository.dart';
import 'package:tuleh_pos/features/kasir/data/datasources/transaction_remote_datasource.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';

/// Mode offline fase 2 — antrean kirim ("Tuléh Offline-First"):
/// checkout saat offline disimpan lokal (nomor L-…, delta stok), dikirim
/// berurutan saat online, ditolak server → tinjau, timeout setelah kirim →
/// tinjau (tidak diulang otomatis), gagal jaringan → mundur eksponensial.

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async =>
      v == null ? m.remove(k) : m[k] = v;
}

class _Penanda implements PenandaKoneksi {
  bool offlineNilai = false;
  @override
  bool get offline => offlineNilai;
  @override
  void tandaiOffline({DateTime? ditarikPada}) => offlineNilai = true;
  @override
  void tandaiOnline() => offlineNilai = false;
}

/// Adapter HTTP tiruan: jawaban per panggilan dari [jawab]; galat jaringan
/// bila mengembalikan DioExceptionType.
class _Server implements HttpClientAdapter {
  _Server(this.jawab);
  final Object Function(RequestOptions o) jawab;
  final List<Map<String, dynamic>> badan = [];
  int panggilan = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    panggilan++;
    if (o.data is Map) badan.add(Map<String, dynamic>.from(o.data as Map));
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

const _aqua = Product(id: 'P1', nama: 'Aqua', harga: 4000, stok: 40);
const _jasa = Product(id: 'J1', nama: 'Cuci', harga: 7000);
final _items = [
  const CartItem(product: _aqua, qty: 2),
  const CartItem(product: _jasa, qty: 1),
];
Struk _struk(String nomor, double kembalian) => Struk(
  namaToko: 'Toko',
  nomor: nomor,
  waktu: DateTime(2026, 9, 5, 14),
  baris: const [StrukBaris(nama: 'Aqua', kuantitas: 2, harga: 4000)],
  total: 15000,
  metode: 'TUNAI',
  dibayar: 20000,
  kembalian: kembalian,
);

CheckoutRepository _repo(_Server server, AntreanStore antrean, _Penanda penanda) =>
    CheckoutRepository(
      remote: TransactionRemoteDataSource(_dio(server)),
      antrean: antrean,
      nomorLokal: NomorLokal(_Storage()),
      koneksi: penanda,
      tokoId: 'T1',
    );

final sukses = (200, {'success': true, 'data': {'nomor': '26-POS-000041', 'kembalian': 5000}});

void main() {
  group('AntreanStore (memori & drift berperilaku sama)', () {
    for (final (nama, buat) in <(String, AntreanStore Function())>[
      ('memori', AntreanMemori.new),
      ('drift', () => AntreanDriftStore(SalinanDb(NativeDatabase.memory()))),
    ]) {
      test('$nama: FIFO, perbarui, selesai, batalkan, ringkas, delta stok', () async {
        final st = buat();
        PesanAntrean p(String ref) => PesanAntrean(
          urut: 0, clientRef: ref, jenis: 'CHECKOUT', path: '/x', body: {'a': 1},
          dibuat: DateTime(2026, 9, 5), tokoId: 'T1',
        );
        await st.antrekan(p('a'), transaksi: TransaksiTertunda(
          clientRef: 'a', tokoId: 'T1', nomorLokal: 'L-1', tipePembayaran: 'TUNAI',
          grandTotal: 1, dibayar: 1, waktuKlien: DateTime(2026, 9, 5), strukJson: '{}',
        ), deltaStok: {'P1': -2});
        await st.antrekan(p('b'), deltaStok: {'P1': -1, 'P2': 5});

        final siap = await st.siapKirim(DateTime(2026, 9, 5, 1));
        expect(siap.map((e) => e.clientRef), ['a', 'b'], reason: 'urutan kirim');
        expect(await st.deltaStokTertunda(), {'P1': -3, 'P2': 5});

        await st.perbarui('a', status: StatusAntrean.menunggu, percobaan: 1,
            cobaLagiSetelah: DateTime(2026, 9, 5, 2));
        expect((await st.siapKirim(DateTime(2026, 9, 5, 1))).map((e) => e.clientRef), ['b'],
            reason: 'a menunggu jadwal coba lagi');
        expect((await st.siapKirim(DateTime(2026, 9, 5, 3))).length, 2);

        await st.selesai('a', hasil: {'nomor': 'X'});
        expect((await st.cari('a'))!.status, StatusAntrean.terkirim);
        expect(await st.transaksiLokal('a'), isNull, reason: 'transaksi lokal dihapus');
        expect(await st.deltaStokTertunda(), {'P1': -1, 'P2': 5});

        await st.perbarui('b', status: StatusAntrean.tinjau, galatTerakhir: 'x');
        expect((await st.ringkas()).tinjau, 1);
        await st.batalkan('b');
        expect(await st.cari('b'), isNull);
        expect(await st.deltaStokTertunda(), isEmpty);
        expect((await st.ringkas()).total, 0);
      });
    }
  });

  group('CheckoutRepository', () {
    test('online: kirim langsung, badan membawa client_ref & waktu_klien', () async {
      final server = _Server((_) => sukses);
      final antrean = AntreanMemori();
      final r = await _repo(server, antrean, _Penanda()).bayar(
        items: _items, metode: 'TUNAI', dibayar: 20000, total: 15000, buatStruk: _struk,
      );
      expect(r.tertunda, isFalse);
      expect(r.nomor, '26-POS-000041');
      expect(server.badan.single['client_ref'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(server.badan.single['waktu_klien'], isNotNull);
      expect((await antrean.ringkas()).total, 0);
    });

    test('diketahui offline: tidak menyentuh jaringan, nomor L-, delta stok hanya produk berstok', () async {
      final server = _Server((_) => sukses);
      final antrean = AntreanMemori();
      final penanda = _Penanda()..offlineNilai = true;
      final r = await _repo(server, antrean, penanda).bayar(
        items: _items, metode: 'TUNAI', dibayar: 20000, total: 15000, buatStruk: _struk,
      );
      expect(server.panggilan, 0);
      expect(r.tertunda, isTrue);
      expect(r.nomor, matches(RegExp(r'^L-\d{6}-0001$')));
      expect(r.kembalian, 5000);
      final pesan = (await antrean.semua()).single;
      expect(pesan.status, StatusAntrean.menunggu);
      expect(pesan.path, '/transaksi/checkout');
      expect(pesan.body['client_ref'], r.clientRef);
      expect(await antrean.deltaStokTertunda(tokoId: 'T1'), {'P1': -2}, reason: 'jasa tanpa stok tidak dihitung');
      final lokal = await antrean.transaksiLokal(r.clientRef!);
      expect(lokal!.nomorLokal, r.nomor);
      final struk = Struk.fromJson(Map<String, dynamic>.from(jsonDecode(lokal.strukJson) as Map));
      expect(struk.nomor, r.nomor);
      expect(struk.catatanKaki, contains('Belum tersinkron'));
    });

    test('gagal jaringan sebelum sampai: diantrekan MENUNGGU', () async {
      final server = _Server((_) => DioExceptionType.connectionError);
      final antrean = AntreanMemori();
      final r = await _repo(server, antrean, _Penanda()).bayar(
        items: _items, metode: 'QRIS', dibayar: 15000, total: 15000, buatStruk: _struk,
      );
      expect(r.tertunda, isTrue);
      expect((await antrean.semua()).single.status, StatusAntrean.menunggu);
    });

    test('timeout setelah kirim: diantrekan biasa & dikirim ulang otomatis', () async {
      final server = _Server((_) => DioExceptionType.receiveTimeout);
      final antrean = AntreanMemori();
      final r = await _repo(server, antrean, _Penanda()).bayar(
        items: _items, metode: 'TUNAI', dibayar: 20000, total: 15000, buatStruk: _struk,
      );
      // Sejak server mengenal client_ref, timeout "mungkin sudah sampai" cukup
      // dikirim ulang otomatis — kirim ulang tidak membuat transaksi kedua.
      expect(r.tertunda, isTrue);
      expect((await antrean.semua()).single.status, StatusAntrean.menunggu);
    });

    test('ditolak server (409 sesi belum dibuka): dilempar apa adanya, tidak diantrekan', () async {
      final server = _Server((_) => (409, {'success': false, 'message': 'Sesi kasir belum dibuka.'}));
      final antrean = AntreanMemori();
      await expectLater(
        _repo(server, antrean, _Penanda()).bayar(
          items: _items, metode: 'TUNAI', dibayar: 20000, total: 15000, buatStruk: _struk,
        ),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Sesi kasir belum dibuka.')),
      );
      expect((await antrean.ringkas()).total, 0);
    });
  });

  group('PenguraiAntrean', () {
    Future<AntreanMemori> antreanIsi(int n) async {
      final a = AntreanMemori();
      for (var i = 1; i <= n; i++) {
        await a.antrekan(
          PesanAntrean(
            urut: 0, clientRef: 'c$i', jenis: 'CHECKOUT', path: '/transaksi/checkout',
            body: {'i': i}, dibuat: DateTime(2026, 9, 5, 10, i), tokoId: 'T1',
          ),
          transaksi: TransaksiTertunda(
            clientRef: 'c$i', tokoId: 'T1', nomorLokal: 'L-$i', tipePembayaran: 'TUNAI',
            grandTotal: 1, dibayar: 1, waktuKlien: DateTime(2026, 9, 5, 10, i), strukJson: '{}',
          ),
          deltaStok: {'P1': -1},
        );
      }
      return a;
    }

    test('kirim berurutan; sukses → TERKIRIM, transaksi lokal & delta hilang', () async {
      final urutan = <int>[];
      final server = _Server((o) {
        urutan.add((o.data as Map)['i'] as int);
        return (201, {'success': true, 'data': {'nomor': '26-POS-${urutan.length}'}});
      });
      final a = await antreanIsi(3);
      var berubah = 0;
      final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda(), setelahBerubah: () => berubah++);
      expect(await p.jalankan(), 3);
      expect(urutan, [1, 2, 3]);
      expect((await a.ringkas()).total, 0);
      expect(await a.transaksiTertunda(), isEmpty);
      expect(await a.deltaStokTertunda(), isEmpty);
      expect((await a.cari('c2'))!.hasil!['nomor'], '26-POS-2');
      expect(berubah, greaterThan(0));
    });

    test('ditolak 422 → TINJAU dengan pesan server; pesan berikutnya tetap dikirim', () async {
      final server = _Server((o) => (o.data as Map)['i'] == 1
          ? (422, {'success': false, 'errors': {'items': ['Stok Aqua tidak cukup.']}})
          : (201, {'success': true, 'data': {}}));
      final a = await antreanIsi(2);
      final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda());
      expect(await p.jalankan(), 1);
      expect((await a.cari('c1'))!.status, StatusAntrean.tinjau);
      expect((await a.cari('c1'))!.galatTerakhir, 'Stok Aqua tidak cukup.');
      expect((await a.cari('c2'))!.status, StatusAntrean.terkirim);
    });

    test('gagal jaringan → mundur eksponensial, putaran berhenti, koneksi ditandai offline', () async {
      final server = _Server((_) => DioExceptionType.connectionError);
      final a = await antreanIsi(2);
      final penanda = _Penanda();
      var kini = DateTime(2026, 9, 5, 10);
      final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: penanda, sekarang: () => kini);
      expect(await p.jalankan(), 0);
      expect(server.panggilan, 1, reason: 'berhenti setelah yang pertama gagal');
      final c1 = (await a.cari('c1'))!;
      expect(c1.status, StatusAntrean.menunggu);
      expect(c1.percobaan, 1);
      expect(c1.cobaLagiSetelah, kini.add(PenguraiAntrean.mundur(1)));
      expect(penanda.offlineNilai, isTrue);
      p.hentikan();

      // Belum waktunya → tidak dikirim; setelah jeda → dikirim lagi.
      expect(await p.jalankan(), 0);
      expect(server.panggilan, 1);
      kini = kini.add(const Duration(seconds: 6));
      expect(await p.jalankan(), 0);
      expect(server.panggilan, 2);
      expect((await a.cari('c1'))!.percobaan, 2);
      p.hentikan();
      expect(PenguraiAntrean.mundur(5), const Duration(minutes: 10));
      expect(PenguraiAntrean.mundur(99), const Duration(minutes: 10));
    });

    test('timeout setelah kirim → dicoba lagi otomatis (server tolak duplikat)', () async {
      // Dulu baris ini masuk TINJAU dan menunggu keputusan kasir. Sejak server
      // mengenal client_ref, kiriman ulang aman: yang kedua dibalas 200 dengan
      // data yang sama, bukan transaksi baru.
      var hidup = false;
      final server = _Server((_) => hidup ? (201, {'success': true, 'data': {}}) : DioExceptionType.receiveTimeout);
      final a = await antreanIsi(1);
      final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda());
      await p.jalankan();
      final sesudahTimeout = (await a.cari('c1'))!;
      expect(sesudahTimeout.status, StatusAntrean.menunggu);
      expect(sesudahTimeout.percobaan, 1, reason: 'dijadwalkan ulang, bukan menunggu manusia');
      hidup = true;
      await p.kirimUlang('c1');
      expect((await a.cari('c1'))!.status, StatusAntrean.terkirim);
      p.hentikan();
    });

    test('kiriman ulang dibalas 200 + meta.idempoten: dianggap sudah tercatat', () async {
      final server = _Server((_) => (200, {
        'success': true,
        'data': {'id': 'TRX-9', 'nomor': '26-POS-000041'},
        'meta': {'idempoten': true},
      }));
      final a = await antreanIsi(1);
      final p = PenguraiAntrean(store: a, dio: _dio(server), koneksi: _Penanda());
      await p.jalankan();
      final baris = (await a.cari('c1'))!;
      expect(baris.status, StatusAntrean.terkirim);
      expect(baris.hasil?['nomor'], '26-POS-000041', reason: 'nomor resmi dari jawaban ulang');
      expect(baris.hasil?['id'], 'TRX-9', reason: 'dipakai bon berantai lokal:<ref>');
      expect(baris.hasil?['_idempoten'], isTrue);
      p.hentikan();
    });
  });

  group('AntreanTulis (pengeluaran / stok masuk)', () {
    test('online kirim langsung; offline diantrekan dengan delta stok', () async {
      final antrean = AntreanMemori();
      final penanda = _Penanda();
      final t = AntreanTulis(antrean: antrean, koneksi: penanda, tokoId: 'T1');
      var dikirim = 0;
      final r1 = await t.jalankan(
        jenis: 'STOK_MASUK', path: '/inventory/stok-masuk', body: {'id_produk': 'P1', 'jumlah': 5},
        kirim: (b) async { dikirim++; expect(b['client_ref'], isNotNull); },
        deltaStok: {'P1': 5},
      );
      expect(r1.tertunda, isFalse);
      expect(dikirim, 1);

      penanda.offlineNilai = true;
      final r2 = await t.jalankan(
        jenis: 'STOK_MASUK', path: '/inventory/stok-masuk', body: {'id_produk': 'P1', 'jumlah': 5},
        kirim: (_) async => throw StateError('tidak boleh dipanggil saat offline'),
        deltaStok: {'P1': 5},
      );
      expect(r2.tertunda, isTrue);
      expect(await antrean.deltaStokTertunda(), {'P1': 5});
      expect((await antrean.semua()).single.jenis, 'STOK_MASUK');
    });

    test('server menolak (422) → dilempar, tidak diantrekan', () async {
      final t = AntreanTulis(antrean: AntreanMemori(), koneksi: _Penanda());
      await expectLater(
        t.jalankan(
          jenis: 'PENGELUARAN', path: '/pengeluaran', body: {'nominal': 0},
          kirim: (_) async => throw const ApiException(message: 'Nominal wajib.', statusCode: 422),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  test('NomorLokal: naik per hari, format L-yyMMdd-NNNN', () async {
    final n = NomorLokal(_Storage());
    expect(await n.berikutnya(sekarang: DateTime(2026, 9, 5)), 'L-260905-0001');
    expect(await n.berikutnya(sekarang: DateTime(2026, 9, 5)), 'L-260905-0002');
    expect(await n.berikutnya(sekarang: DateTime(2026, 9, 6)), 'L-260906-0001');
  });
}
