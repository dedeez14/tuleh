// Keluhan lapangan: "mode offline, keluar aplikasi lalu buka lagi → tidak bisa
// masuk". Uji ini meniru urutannya: masuk saat online, aplikasi ditutup, lalu
// dibuka lagi TANPA jaringan dengan penyimpanan (token + salinan) yang sama.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/screens/pengaturan_screen.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/salinan_store.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';

import 'helpers/masa_coba_palsu.dart';

/// Penyimpanan aman yang bertahan antar "proses" (dipakai ulang di wadah baru).
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
  @override
  Future<void> clearSession() async {
    m.remove('token');
    m.remove('toko');
  }
}

/// Server yang bisa dimatikan: online membalas /auth/me, offline melempar
/// galat jaringan seperti ponsel tanpa sinyal.
class _Server implements HttpClientAdapter {
  bool online = true;
  final diminta = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add('${o.method} ${o.path}');
    if (!online) {
      throw DioException.connectionError(
        requestOptions: o,
        reason: 'tidak ada jaringan',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': {
          'pos_role': 'KASIR',
          'user': {'id': 'U1', 'name': 'Bu Sari', 'email': 'sari@toko.id'},
          'company': {'nama': 'Warung Bu Sari'},
        },
      }),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Offline tanpa timer pemeriksa ulang (tes tidak boleh meninggalkan Timer).
class _KoneksiOffline extends KoneksiNotifier {
  _KoneksiOffline() : super(jaringan: const Stream.empty());
  @override
  StatusKoneksi build() => const StatusKoneksi(online: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Storage storage;
  late SalinanMemori salinan;
  late _Server server;

  setUp(() {
    storage = _Storage()
      ..m['token'] = 'tok-123'
      ..m['toko'] = 'TOKO-ENC-1';
    salinan = SalinanMemori();
    server = _Server();
  });

  /// Satu "proses aplikasi": wadah baru, penyimpanan & salinan yang sama.
  ProviderContainer bukaAplikasi() {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        salinanStoreProvider.overrideWithValue(salinan),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        koneksiProvider.overrideWith(() => KoneksiNotifier(jaringan: const Stream.empty())),
      ],
    );
    addTearDown(c.dispose);
    c.read(dioProvider).httpClientAdapter = server;
    return c;
  }

  test('buka aplikasi saat online menyalin identitas pengguna', () async {
    final c = bukaAplikasi();
    final user = await c.read(authControllerProvider.future);
    expect(user?.name, 'Bu Sari');
    expect(server.diminta, contains('GET /auth/me'));
  });

  test('KELUHAN: aplikasi ditutup lalu dibuka lagi tanpa jaringan', () async {
    // Sesi pertama: online, identitas tersalin.
    final pertama = bukaAplikasi();
    expect((await pertama.read(authControllerProvider.future))?.name, 'Bu Sari');

    // Aplikasi ditutup; jaringan hilang; aplikasi dibuka lagi.
    server.online = false;
    final kedua = bukaAplikasi();
    final user = await kedua.read(authControllerProvider.future);

    expect(
      user,
      isNotNull,
      reason: 'token masih ada dan identitas sudah tersalin — kasir tidak boleh '
          'dilempar ke layar masuk hanya karena tidak ada sinyal',
    );
    expect(user?.name, 'Bu Sari');
    expect(storage.m['token'], 'tok-123', reason: 'sesi tidak boleh dihapus saat offline');
  });

  test('tanpa salinan identitas (belum pernah online) tetap ke layar masuk', () async {
    server.online = false;
    final c = bukaAplikasi();
    expect(await c.read(authControllerProvider.future), isNull);
  });

  group('penjaga: keluar akun saat offline', () {
    testWidgets('offline → diperingatkan; Batal berarti sesi tetap ada', (t) async {
      late final ProviderContainer c;
      await t.runAsync(() async {
        c = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            salinanStoreProvider.overrideWithValue(salinan),
            masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
            koneksiProvider.overrideWith(_KoneksiOffline.new),
            antreanStoreProvider.overrideWithValue(AntreanMemori()),
          ],
        );
        c.read(dioProvider).httpClientAdapter = server;
        await salinan.tulis('/produk?toko_id=TOKO-ENC-1', '{}', DateTime(2026, 9, 9));
      });
      addTearDown(c.dispose);

      late BuildContext ctx;
      late WidgetRef wref;
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(builder: (context, ref, _) {
              ctx = context;
              wref = ref;
              return const SizedBox.expand();
            }),
          ),
        ),
      ));

      final aksi = keluarDenganPenjagaAntrean(ctx, wref);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));

      expect(find.text('Sedang offline — jangan keluar dulu'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Batal'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await aksi;

      expect(storage.m['token'], 'tok-123', reason: 'sesi tidak boleh hilang');
      expect(await salinan.baca('/produk?toko_id=TOKO-ENC-1'), isNotNull,
          reason: 'salinan offline tidak boleh terhapus');
    });

    testWidgets('"Tetap keluar" tetap dihormati', (t) async {
      late final ProviderContainer c;
      await t.runAsync(() async {
        c = ProviderContainer(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            salinanStoreProvider.overrideWithValue(salinan),
            masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
            koneksiProvider.overrideWith(_KoneksiOffline.new),
            antreanStoreProvider.overrideWithValue(AntreanMemori()),
          ],
        );
        c.read(dioProvider).httpClientAdapter = server;
      });
      addTearDown(c.dispose);

      late BuildContext ctx;
      late WidgetRef wref;
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(builder: (context, ref, _) {
              ctx = context;
              wref = ref;
              return const SizedBox.expand();
            }),
          ),
        ),
      ));

      final aksi = keluarDenganPenjagaAntrean(ctx, wref);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.widgetWithText(TextButton, 'Tetap keluar'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await aksi;

      expect(storage.m['token'], isNull);
    });
  });
}
