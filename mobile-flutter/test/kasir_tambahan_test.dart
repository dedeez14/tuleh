import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/nomor_lokal.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/cetak/data/struk_teks.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';
import 'package:tuleh_pos/features/kasir/data/checkout_repository.dart';
import 'package:tuleh_pos/features/kasir/data/datasources/transaction_remote_datasource.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/keranjang_meta.dart';
import 'package:tuleh_pos/features/pelanggan/domain/entities/pelanggan.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';

import 'helpers/masa_coba_palsu.dart';

/// Tambahan keranjang (2.11.0): pelanggan, diskon transaksi, catatan —
/// kontrak checkout sama dengan desktop (items.*.diskon_persen, id_pelanggan,
/// catatan); total & struk memperhitungkan potongan; mesin demo ikut.

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<void> writeToken(String? v) async => v == null ? m.remove('token') : m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async => v == null ? m.remove('toko') : m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
}

ProviderContainer _wadah() => ProviderContainer(
  overrides: [
    secureStorageProvider.overrideWithValue(_Storage()),
    masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
    ...overrideOffline(),
  ],
);

class _Penanda implements PenandaKoneksi {
  @override
  bool get offline => false;
  @override
  void tandaiOffline({DateTime? ditarikPada}) {}
  @override
  void tandaiOnline() {}
}

class _Server implements HttpClientAdapter {
  Map<String, dynamic>? badan;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    badan = Map<String, dynamic>.from(o.data as Map);
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': {'nomor': '26-POS-000041', 'kembalian': 0}}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

const _kopi = Product(id: 'P1', nama: 'Kopi', harga: 18000, stok: 10);
const _roti = Product(id: 'P2', nama: 'Roti', harga: 15000);

Struk _strukKosong(String n, double total) =>
    Struk(namaToko: 'X', nomor: n, waktu: DateTime(2026), baris: const [], total: total);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('KeranjangMeta', () {
    test('hitungPotongan & total akhir; reset saat keranjang kosong', () {
      expect(hitungPotongan(51000, 10), 5100);
      expect(hitungPotongan(12500, 7), 875);
      expect(hitungPotongan(1000, 0), 0);

      final c = _wadah();
      addTearDown(c.dispose);
      c.listen(keranjangMetaProvider, (_, _) {});
      final cart = c.read(cartControllerProvider.notifier);
      cart.add(_kopi);
      cart.add(_kopi);
      cart.add(_roti);
      expect(c.read(cartTotalProvider), 51000);
      final meta = c.read(keranjangMetaProvider.notifier);
      meta.aturDiskon(10);
      meta.pilihPelanggan(const Pelanggan(id: 'C1', nama: 'Budi'));
      meta.aturCatatan('  tanpa es ');
      expect(c.read(cartGrandTotalProvider), 45900);
      expect(c.read(keranjangMetaProvider).catatan, 'tanpa es');
      expect(c.read(keranjangMetaProvider).kosong, isFalse);

      cart.clear();
      expect(c.read(keranjangMetaProvider).kosong, isTrue, reason: 'ikut kosong');
      expect(c.read(cartGrandTotalProvider), 0);
    });

    test('aturDiskon dijepit 0–100', () {
      final c = _wadah();
      addTearDown(c.dispose);
      c.read(keranjangMetaProvider.notifier).aturDiskon(150);
      expect(c.read(keranjangMetaProvider).diskonPersen, 100);
      c.read(keranjangMetaProvider.notifier).aturDiskon(-5);
      expect(c.read(keranjangMetaProvider).diskonPersen, 0);
    });
  });

  test('CheckoutRepository mengirim diskon_persen per item, id_pelanggan, catatan', () async {
    final server = _Server();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = server;
    final repo = CheckoutRepository(
      remote: TransactionRemoteDataSource(dio),
      antrean: AntreanMemori(),
      nomorLokal: NomorLokal(_Storage()),
      koneksi: _Penanda(),
      tokoId: 'T1',
    );
    await repo.bayar(
      items: const [CartItem(product: _kopi, qty: 2), CartItem(product: _roti, qty: 1)],
      metode: 'QRIS',
      dibayar: 45900,
      total: 45900,
      buatStruk: (n, _) => _strukKosong(n, 45900),
      diskonPersen: 10,
      idPelanggan: 'C1',
      catatan: 'tanpa es',
    );
    final b = server.badan!;
    expect((b['items'] as List).every((i) => (i as Map)['diskon_persen'] == 10), isTrue);
    expect(b['id_pelanggan'], 'C1');
    expect(b['catatan'], 'tanpa es');

    await repo.bayar(
      items: const [CartItem(product: _roti, qty: 1)],
      metode: 'TUNAI',
      dibayar: 20000,
      total: 15000,
      buatStruk: (n, _) => _strukKosong(n, 15000),
    );
    final polos = server.badan!;
    expect((polos['items'] as List).first, isNot(contains('diskon_persen')));
    expect(polos.containsKey('id_pelanggan'), isFalse);
    expect(polos.containsKey('catatan'), isFalse);
  });

  test('DemoEngine: diskon per item mengurangi total, pelanggan & catatan tercatat', () {
    final engine = DemoEngine();
    const toko = {'toko_id': 'TOKO-1'};
    final produk = (engine.handle(method: 'GET', path: '/produk', query: toko).body['data'] as List).first as Map;
    final pelanggan = (engine.handle(method: 'GET', path: '/pelanggan', query: toko).body['data'] as List).first as Map;
    final harga = (produk['harga_jual'] as num).toDouble();
    final r = engine.handle(
      method: 'POST',
      path: '/transaksi/checkout',
      query: toko,
      body: {
        'items': [{'id_produk': produk['id'], 'kuantitas': 2, 'harga': harga, 'diskon_persen': 25}],
        'tipe_pembayaran': 'QRIS',
        'dibayar': harga * 2 * 0.75,
        'id_pelanggan': pelanggan['id'],
        'catatan': 'bungkus',
      },
    );
    expect(r.body['success'], isTrue);
    final d = r.body['data'] as Map;
    expect(d['total_diskon'], harga * 2 * 0.25);
    expect(d['grand_total'], harga * 2 * 0.75);
    expect(d['subtotal'], harga * 2);
    expect(d['pelanggan'], pelanggan['nama']);
    expect(d['catatan'], 'bungkus');
  });

  test('StrukTeks & JSON memuat pelanggan dan diskon', () {
    final s = Struk(
      namaToko: 'Toko', nomor: 'N1', waktu: DateTime(2026, 9, 7, 9),
      baris: const [StrukBaris(nama: 'Kopi', kuantitas: 2, harga: 18000)],
      total: 32400, metode: 'QRIS', pelanggan: 'Budi', diskon: 3600,
    );
    final teks = const StrukTeks().bangun(s);
    expect(teks, contains('Pelanggan                   Budi'));
    expect(teks, contains('Subtotal               Rp 36.000'));
    expect(teks, contains('Diskon                 -Rp 3.600'));
    expect(teks, contains('TOTAL                  Rp 32.400'));
    final ulang = Struk.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(ulang.pelanggan, 'Budi');
    expect(ulang.diskon, 3600);
  });
}
