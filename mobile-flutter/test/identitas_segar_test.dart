// Tahap B §2b: hak akses, peran, dan menu toko berubah di SERVER saat aplikasi
// sedang terbuka. `/auth/me` karena itu dipanggil ulang saat aplikasi kembali
// ke depan (jeda 60 detik) dan sesudah 403 — tanpa kasir perlu keluar-masuk.
//
// Pelajaran dari kembarannya di desktop (Task 7, ditinjau dua kali):
//  - jalur paksa (403) punya jeda SENDIRI: layar yang polling (papan pesanan,
//    meja, stok) kena 403 setiap putaran, dan tanpa jeda itu setiap penolakan
//    memanggil /auth/me lagi;
//  - hak berubah → manifest dimuat ulang SEBELUM menu dinilai: server menyaring
//    menu per hak akses sedangkan `manifest_version` tidak bergerak;
//  - hanya layar yang KEHILANGAN pintunya yang dipulangkan ke Beranda; layar
//    tanpa kartu (papan pesanan) tidak pernah ikut terusir;
//  - jawaban gagal/offline tidak pernah menghapus hak, manifest, atau sesi.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/akses/akses.dart';
import 'package:tuleh_pos/core/akses/identitas_segar.dart';
import 'package:tuleh_pos/core/navigation/registri_modul.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/router/app_router.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/auth/presentation/widgets/identitas_gate.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/home/presentation/screens/home_screen.dart';
import 'package:tuleh_pos/features/jadwal/presentation/screens/jadwal_screen.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko_manifest.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {'token': 'tkn', 'toko': 'T1'};
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<void> writeToken(String? v) async =>
      v == null || v.isEmpty ? m.remove('token') : m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async =>
      v == null || v.isEmpty ? m.remove('toko') : m['toko'] = v;
  @override
  Future<String?> readAkunTerakhir() async => m['akun'] ?? 'U1';
  @override
  Future<void> writeAkunTerakhir(String? v) async =>
      v == null ? m.remove('akun') : m['akun'] = v;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async =>
      v == null ? m.remove(k) : m[k] = v;
  @override
  Future<void> clearSession() async {
    m.remove('token');
    m.remove('toko');
  }
}

/// Server tiruan: hak akses & menu manifest bisa diubah di tengah uji, persis
/// seperti pemilik yang mengubah peran dari ERP saat aplikasi terbuka.
class _Server implements HttpClientAdapter {
  _Server({List<String>? akses, List<String>? menus})
    : akses = akses ?? ['kasir.transaksi'],
      menus = menus ?? ['jadwal', 'produk'];

  List<String> akses;
  List<String> menus;

  /// Menu manifest per toko (toko yang tak terdaftar memakai [menus]).
  final menusToko = <String, List<String>>{};

  /// Menahan jawaban manifest toko tertentu sampai completer-nya selesai —
  /// untuk menguji apa yang terjadi bila keadaan berubah selagi permintaan
  /// masih di jalan.
  final tahanManifest = <String, Completer<void>>{};

  /// Jumlah panggilan /auth/me — inti pengujian jeda.
  int panggilan = 0;
  int manifestDiminta = 0;

  /// Server gangguan (5xx) untuk /auth/me dan manifest.
  bool identitasGagal = false;
  bool manifestGagal = false;

  /// Jalur yang dijawab 403 (hak dicabut pemilik).
  String? tolak;

  ResponseBody _json(Object body, [int code = 200]) => ResponseBody.fromString(
    jsonEncode(body),
    code,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    if (o.path == tolak) {
      return _json({'success': false, 'message': 'Tidak berhak.'}, 403);
    }
    if (o.path == '/auth/me') {
      panggilan++;
      if (identitasGagal) {
        return _json({'success': false, 'message': 'Server sibuk.'}, 503);
      }
      return _json({
        'success': true,
        'data': {
          'user': {'id': 'U1', 'name': 'Pengguna Uji'},
          'akses': akses,
        },
      });
    }
    if (o.path == '/tokos') {
      return _json({
        'success': true,
        'data': [
          {'id': 'T1', 'kode': 'TK-001', 'nama': 'Toko Uji'},
        ],
      });
    }
    if (o.path.endsWith('/manifest')) {
      manifestDiminta++;
      // /tokos/{id}/manifest
      final idToko = o.path.split('/')[2];
      await tahanManifest[idToko]?.future;
      if (manifestGagal) {
        return _json({'success': false, 'message': 'Server sibuk.'}, 503);
      }
      final daftar = menusToko[idToko] ?? menus;
      return _json({
        'success': true,
        'data': {
          'vertical_code': 'ritel',
          'menus': [
            for (var i = 0; i < daftar.length; i++)
              {
                'id': daftar[i],
                'label': daftar[i],
                'route_key': daftar[i],
                'order': i,
              },
          ],
          'capabilities': <String>[],
          'lifecycle': {'states': <String>[]},
        },
      });
    }
    return _json({'success': true, 'data': <dynamic>[]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Wadah dengan Dio POLOS (tanpa interceptor salinan): yang diuji di sini
  /// jalur identitasnya, bukan lapisan offline — salinan /auth/me justru akan
  /// menutupi jawaban gagal yang sengaja dibuat.
  ProviderContainer wadahPolos(_Server server, {_Storage? storage}) {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage ?? _Storage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ...overrideOffline(),
        dioProvider.overrideWith(
          (ref) =>
              Dio(
                  BaseOptions(
                    baseUrl: 'https://x.test/api',
                    validateStatus: (_) => true,
                  ),
                )
                ..httpClientAdapter = server,
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Wadah dengan rantai Dio SUNGGUHAN (header, token, 401/402/403) — adapter
  /// saja yang diganti.
  ProviderContainer wadahPenuh(_Server server, {_Storage? storage}) {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage ?? _Storage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ...overrideOffline(),
      ],
    );
    addTearDown(c.dispose);
    c.read(dioProvider).httpClientAdapter = server;
    return c;
  }

  group('AuthController.segarkanIdentitas', () {
    test('memperbarui hak; jeda 60 detik; paksa melewatinya', () async {
      final server = _Server();
      final c = wadahPolos(server);

      await c.read(authControllerProvider.future);
      expect(server.panggilan, 1, reason: 'masuk otomatis');
      expect(c.read(bisaProvider('transaksi.batal')), isFalse);

      final auth = c.read(authControllerProvider.notifier);
      server.akses = ['kasir.transaksi', 'transaksi.batal'];
      final t0 = DateTime(2026, 9, 21, 10);

      expect(await auth.segarkanIdentitas(sekarang: t0), isTrue,
          reason: 'hak berubah → pemanggil perlu memuat ulang menu');
      expect(server.panggilan, 2);
      expect(c.read(bisaProvider('transaksi.batal')), isTrue,
          reason: 'hak baru langsung terpakai');

      await auth.segarkanIdentitas(sekarang: t0.add(const Duration(seconds: 30)));
      expect(server.panggilan, 2, reason: 'masih dalam jeda 60 detik');

      expect(
        await auth.segarkanIdentitas(sekarang: t0.add(const Duration(seconds: 61))),
        isFalse,
        reason: 'hak sama → tak perlu menggambar ulang',
      );
      expect(server.panggilan, 3);

      await auth.segarkanIdentitas(paksa: true, sekarang: t0.add(const Duration(seconds: 62)));
      expect(server.panggilan, 4, reason: 'paksa (cabang 403) melewati jeda');
    });

    test('jalur paksa punya jeda sendiri: 403 beruntun tak membanjiri /auth/me', () async {
      final server = _Server();
      final c = wadahPolos(server);
      await c.read(authControllerProvider.future);
      final auth = c.read(authControllerProvider.notifier);
      final t0 = DateTime(2026, 9, 21, 10);

      // 403 pertama harus SEGERA menyegarkan — kasir tak menunggu jeda apa pun.
      await auth.segarkanIdentitas(paksa: true, sekarang: t0);
      expect(server.panggilan, 2);

      // Layar yang polling tiap 4–10 detik kena 403 berkali-kali.
      for (final detik in [4, 8, 12, 20, 29]) {
        await auth.segarkanIdentitas(paksa: true, sekarang: t0.add(Duration(seconds: detik)));
      }
      expect(server.panggilan, 2, reason: 'jeda paksa 30 detik menahan banjir');

      await auth.segarkanIdentitas(paksa: true, sekarang: t0.add(const Duration(seconds: 31)));
      expect(server.panggilan, 3);
    });

    test('/auth/me gagal (server sibuk/offline) tidak menghapus hak maupun sesi', () async {
      final server = _Server(akses: ['kasir.transaksi', 'transaksi.refund']);
      final storage = _Storage();
      final c = wadahPolos(server, storage: storage);
      await c.read(authControllerProvider.future);
      expect(c.read(bisaProvider('transaksi.refund')), isTrue);

      server.identitasGagal = true;
      final t0 = DateTime(2026, 9, 21, 10);
      expect(await c.read(authControllerProvider.notifier).segarkanIdentitas(sekarang: t0), isFalse);

      expect(server.panggilan, 2, reason: 'dicoba sekali');
      expect(c.read(authControllerProvider).valueOrNull?.id, 'U1', reason: 'tetap masuk');
      expect(c.read(bisaProvider('transaksi.refund')), isTrue,
          reason: 'amplop kosong bukan bukti hak dicabut');
      expect(storage.m['token'], 'tkn', reason: 'sesi tidak boleh dibersihkan');
      expect(c.read(sessionExpiredProvider), isFalse);

      // Gagal pun distempel: perangkat tanpa sinyal tidak mencoba tiap resume.
      await c.read(authControllerProvider.notifier).segarkanIdentitas(
            sekarang: t0.add(const Duration(seconds: 30)),
          );
      expect(server.panggilan, 2);
    });

    test('Mode Demo tidak pernah memanggil server', () async {
      final server = _Server();
      final c = wadahPolos(server);
      await c.read(authControllerProvider.notifier).startDemo();
      final sebelum = server.panggilan;
      await c.read(authControllerProvider.notifier).segarkanIdentitas(
            paksa: true,
            sekarang: DateTime(2026, 9, 21, 10),
          );
      expect(server.panggilan, sebelum);
    });
  });

  group('penanda 403', () {
    test('403 ber-token menaikkan hakDitolak; /auth/me & tanpa token tidak', () async {
      final server = _Server();
      final storage = _Storage();
      final c = wadahPenuh(server, storage: storage);
      await c.read(authControllerProvider.future);
      final dio = c.read(dioProvider);

      server.tolak = '/jadwal';
      await dio.get<dynamic>('/jadwal');
      expect(c.read(hakDitolakProvider), 1);

      // Tanpa ini, 403 dari /auth/me memicu /auth/me lagi — tak berujung.
      server.tolak = '/auth/me';
      await dio.get<dynamic>('/auth/me');
      expect(c.read(hakDitolakProvider), 1, reason: 'tanpa rekursi 403 → /auth/me → 403');

      storage.m.remove('token');
      server.tolak = '/jadwal';
      await dio.get<dynamic>('/jadwal');
      expect(c.read(hakDitolakProvider), 1, reason: 'permintaan tanpa token bukan hak dicabut');
    });
  });

  group('manifest & pintu layar', () {
    test('muat ulang manifest yang gagal tetap menyajikan manifest lama', () async {
      final server = _Server(menus: ['jadwal', 'produk']);
      // Dio polos: lewat rantai sungguhan, 5xx pada GET dijawab dari salinan
      // offline — yang diuji di sini justru cabang GAGALnya.
      final c = wadahPolos(server);
      await c.read(authControllerProvider.future);
      // Manifest bergantung pada toko aktif; tanpa listener, provider yang
      // dibangun saat toko masih dimuat tak pernah dibangun ulang sendiri.
      await c.read(activeTokoIdProvider.future);
      c.listen(activeManifestProvider, (_, _) {});
      final awal = await c.read(activeManifestProvider.future);
      expect(awal.menus.map((m) => m.routeKey), ['jadwal', 'produk']);

      server.manifestGagal = true;
      expect(await c.read(activeManifestProvider.notifier).segarkan(), isFalse);
      final sesudah = c.read(activeManifestProvider).valueOrNull;
      expect(sesudah?.menus.map((m) => m.routeKey), ['jadwal', 'produk'],
          reason: 'menu bawaan yang lebih lebar dari peran tak boleh menggantikannya');
      expect(c.read(activeManifestProvider).hasError, isFalse);

      server.manifestGagal = false;
      server.menus = ['produk'];
      expect(await c.read(activeManifestProvider.notifier).segarkan(), isTrue);
      expect(c.read(activeManifestProvider).valueOrNull?.menus.map((m) => m.routeKey), ['produk']);
    });

    test('toko berganti selagi segarkan berjalan: manifest toko lama tak menimpa yang baru', () async {
      final server = _Server()
        ..menusToko['T1'] = ['jadwal']
        ..menusToko['T2'] = ['produk'];
      final c = wadahPolos(server);
      await c.read(authControllerProvider.future);
      await c.read(activeTokoIdProvider.future);
      c.listen(activeManifestProvider, (_, _) {});
      expect(
        (await c.read(activeManifestProvider.future)).menus.map((m) => m.routeKey),
        ['jadwal'],
      );

      // Manifest T1 ditahan di jalan, lalu pengguna pindah toko — persis
      // tombol "Pindah ke …" pada 409 atau pemilih toko di Beranda.
      final tahan = Completer<void>();
      server.tahanManifest['T1'] = tahan;
      final segar = c.read(activeManifestProvider.notifier).segarkan();
      await c.read(activeTokoIdProvider.notifier).select('T2');
      expect(
        (await c.read(activeManifestProvider.future)).menus.map((m) => m.routeKey),
        ['produk'],
      );

      tahan.complete();
      expect(await segar, isFalse, reason: 'jawaban toko lama diabaikan');
      expect(
        c.read(activeManifestProvider).valueOrNull?.menus.map((m) => m.routeKey),
        ['produk'],
        reason: 'menu toko lama tak boleh dipakai menilai pintu toko baru',
      );
    });

    test('segarkan yang melayang saat notifier dibuang: false, tanpa galat liar', () async {
      final server = _Server(menus: ['jadwal']);
      final c = wadahPolos(server);
      await c.read(authControllerProvider.future);
      await c.read(activeTokoIdProvider.future);
      c.listen(activeManifestProvider, (_, _) {});
      await c.read(activeManifestProvider.future);

      final tahan = Completer<void>();
      server.tahanManifest['T1'] = tahan;
      final notifier = c.read(activeManifestProvider.notifier);
      final segar = notifier.segarkan();

      c.dispose();
      tahan.complete();
      // Tanpa penjaga "sudah dibuang", `state =` di sini melempar StateError di
      // dalam future yang tidak di-await (`IdentitasGate._segarkan`).
      expect(await segar, isFalse);
      expect(await notifier.segarkan(), isFalse, reason: 'panggilan sesudahnya juga aman');
    });

    test('rutePunyaPintu & layarTujuan: hanya yang kehilangan pintu yang pulang', () {
      TokoManifest manifest(List<String> keys) => TokoManifest(
        menus: [for (final k in keys) ManifestMenu(id: k, label: k, routeKey: k)],
      );
      final sebelum = rutePunyaPintu(manifest(['jadwal', 'produk']));
      final sesudah = rutePunyaPintu(manifest(['produk']));

      expect(sebelum, contains('/jadwal'));
      expect(sesudah, isNot(contains('/jadwal')));
      expect(sesudah, containsAll(['/home', '/kasir', '/aktivitas', '/laporan', '/pengaturan']));

      expect(layarTujuan('/jadwal', sesudah, sebelum), '/home');
      expect(layarTujuan('/produk', sesudah, sebelum), isNull);
      expect(layarTujuan('/home', sesudah, sebelum), isNull);
      // Papan pesanan tak pernah punya kartu → dibuka lewat tab, jangan diusir.
      expect(layarTujuan('/pesanan', sesudah, sebelum), isNull);
      // Manifest gagal dimuat (daftar kosong) → jangan mengusir siapa pun.
      expect(layarTujuan('/jadwal', const <String>{}, sebelum), isNull);
    });

    test('kunciAkses: urutan server tak dijamin, kosong berbeda dari ada isinya', () {
      expect(kunciAkses(['b', 'a']), kunciAkses(['a', 'b']));
      expect(kunciAkses(const <String>[]) == kunciAkses(['a']), isFalse);
    });
  });

  group('IdentitasGate', () {
    Future<ProviderContainer> pasang(WidgetTester t, _Server server, {String? mulaiDi}) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final c = wadahPenuh(server);
      await t.runAsync(() async {
        await c.read(authControllerProvider.future);
        // Urutannya penting: manifest yang dibangun saat toko aktif masih
        // dimuat menunggu pembangunan ulang yang tak pernah datang selama
        // belum ada yang mengawasinya.
        await c.read(activeTokoIdProvider.future);
        await c.read(activeManifestProvider.future);
      });

      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: c.read(routerProvider),
            builder: (context, child) =>
                IdentitasGate(child: child ?? const SizedBox.shrink()),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      if (mulaiDi != null) {
        c.read(routerProvider).go(mulaiDi);
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }
      return c;
    }

    String layar(ProviderContainer c) =>
        c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

    /// Tunggu rantai async gerbang (auth/me → manifest → pindah layar) selesai.
    Future<void> tenang(WidgetTester t) async {
      for (var i = 0; i < 20; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('403 → hak dicabut: layar yang kehilangan pintu pulang ke Beranda', (t) async {
      final server = _Server(akses: ['kasir.transaksi', 'jadwal.lihat']);
      final c = await pasang(t, server, mulaiDi: '/jadwal');
      expect(find.byType(JadwalScreen), findsOneWidget);
      final panggilanAwal = server.panggilan;

      // Pemilik mencabut hak jadwal: server menyaring menunya dari manifest.
      server.akses = ['kasir.transaksi'];
      server.menus = ['produk'];
      c.read(hakDitolakProvider.notifier).state++;
      await tenang(t);

      expect(server.panggilan, panggilanAwal + 1, reason: 'sekali saja sesudah 403');
      expect(layar(c), '/home');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(c.read(bisaProvider('jadwal.lihat')), isFalse);
    });

    testWidgets('hak sama → layar dibiarkan, manifest tak ditarik ulang', (t) async {
      final server = _Server(akses: ['kasir.transaksi', 'jadwal.lihat']);
      final c = await pasang(t, server, mulaiDi: '/jadwal');
      final manifestAwal = server.manifestDiminta;

      c.read(hakDitolakProvider.notifier).state++;
      await tenang(t);

      expect(server.manifestDiminta, manifestAwal,
          reason: 'hak tak berubah → tak perlu menarik manifest');
      expect(layar(c), '/jadwal');
    });

    testWidgets('kembali ke depan memanggil /auth/me sekali', (t) async {
      final server = _Server();
      final c = await pasang(t, server);
      final awal = server.panggilan;

      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await tenang(t);

      expect(server.panggilan, awal + 1);
      expect(layar(c), '/home');
    });
  });
}
