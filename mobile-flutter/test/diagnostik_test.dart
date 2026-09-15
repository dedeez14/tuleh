// Diagnostik (kontrak #1, 2026-09-15): galat & crash → POST /diagnostik
// dengan client_ref (dedupe), aman offline (antre di berkas), tanpa token/PIN
// di badan. Pengaturan → "Kirim laporan ke dukungan" mengirim ekor log.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/constants/app_config.dart';
import 'package:tuleh_pos/core/diagnostik/diagnostik.dart';
import 'package:tuleh_pos/core/diagnostik/log_cincin.dart';
import 'package:tuleh_pos/core/diagnostik/pelapor_diagnostik.dart';
import 'package:tuleh_pos/core/diagnostik/penyamar.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/screens/pengaturan_screen.dart';

import 'helpers/masa_coba_palsu.dart';

class _Server implements HttpClientAdapter {
  _Server(this.status);
  int status;
  final List<RequestOptions> diminta = [];
  final List<Map<String, dynamic>> badan = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add(o);
    if (status == 0) throw DioException.connectionError(requestOptions: o, reason: 'tanpa sinyal');
    badan.add(Map<String, dynamic>.from(o.data as Map));
    return ResponseBody.fromString(
      jsonEncode(status == 202
          ? {'success': true, 'data': {'id': 'D${badan.length}'}, 'meta': null, 'message': '', 'errors': null}
          : {'success': false, 'message': 'x'}),
      status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

PelaporDiagnostik _pelapor(_Server s, PenyimpanDiagnostik simpan, {Future<String?> Function()? token}) => PelaporDiagnostik(
  dio: Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = s,
  simpan: simpan,
  versi: '2.29.0',
  token: token,
  konteksDasar: () => {'layar': '/kasir', 'os': 'android 14', 'perangkat': 'Uji'},
  sekarang: () => DateTime(2026, 9, 15, 10, 30),
);

void main() {
  group('penyamaran', () {
    test('token Bearer, token Sanctum, sandi/PIN di JSON & query disamarkan', () {
      const teks = 'Authorization: Bearer 12|AbCdEfGhIjKlMnOpQrStUvWxYz0123 '
          '{"password":"rahasia123","pin":"4321","token":"abc.def"} '
          'url?token=zzz&toko_id=5 lalu 99|Qwertyuiopasdfghjklzxcvbnm1234';
      final s = samarkan(teks);
      for (final bocor in ['AbCdEfGhIjKlMnOpQrStUvWxYz0123', 'rahasia123', '4321', 'abc.def', 'zzz', 'Qwertyuiopasdfghjklzxcvbnm1234']) {
        expect(s.contains(bocor), isFalse, reason: '$bocor bocor: $s');
      }
      expect(s, contains('toko_id=5'), reason: 'data non-rahasia tetap utuh');
    });
  });

  group('log cincin', () {
    test('kapasitas terbatas, baris lama dibuang, ekor dibatasi karakter, disamarkan', () {
      final log = LogCincin(kapasitas: 3);
      for (var i = 1; i <= 5; i++) {
        log.catat('baris $i');
      }
      expect(log.jumlah, 3);
      expect(log.semua().first, contains('baris 3'));
      log.catat('Bearer rahasia-sekali');
      expect(log.ekor(), isNot(contains('rahasia-sekali')));
      expect(log.ekor(maksKarakter: 40).split('\n').length, lessThan(4));
    });
  });

  group('pelapor', () {
    test('laporan crash: bentuk kontrak, batas ukuran, tanpa token di badan; token hanya di header', () async {
      final server = _Server(202);
      final simpan = PenyimpanDiagnostikMemori();
      final p = _pelapor(server, simpan, token: () async => 'tok-rahasia');
      await p.laporkanGalat(StateError('x' * 5000), StackTrace.fromString('#0 ${'y' * 30000}'), jenis: JenisDiagnostik.crash);
      await p.kirimTertunda();

      expect(server.badan, hasLength(1));
      final b = server.badan.single;
      expect(b['platform'], AppConfig.platform);
      expect(b['versi'], '2.29.0');
      expect(b['jenis'], 'crash');
      expect((b['pesan'] as String).length, lessThanOrEqualTo(BatasDiagnostik.pesan));
      expect((b['stack'] as String).length, lessThanOrEqualTo(BatasDiagnostik.stack));
      expect(b['client_ref'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(b['terjadi_pada'], startsWith('2026-09-15T10:30:00'));
      expect((b['konteks'] as Map)['layar'], '/kasir');
      expect(utf8.encode(jsonEncode(b['konteks'])).length, lessThanOrEqualTo(BatasDiagnostik.konteksByte));
      expect(jsonEncode(b).contains('tok-rahasia'), isFalse);
      expect(server.diminta.single.headers['Authorization'], 'Bearer tok-rahasia');
      expect(server.diminta.single.headers[AppConfig.versionHeader], '2.29.0');
      expect(server.diminta.single.path, '/diagnostik');
      expect(simpan.isi, isEmpty, reason: 'diterima 202 → keluar dari antrean');
    });

    test('galat yang sama dalam satu sesi hanya dilaporkan sekali', () async {
      final server = _Server(202);
      final p = _pelapor(server, PenyimpanDiagnostikMemori());
      final st = StackTrace.fromString('#0 main');
      await p.laporkanGalat(Exception('sama'), st);
      await p.laporkanGalat(Exception('sama'), st);
      await p.kirimTertunda();
      expect(server.badan, hasLength(1));
    });

    test('tanpa sinyal / 503: laporan tetap antre (client_ref sama saat dikirim ulang)', () async {
      final server = _Server(0);
      final simpan = PenyimpanDiagnostikMemori();
      final p = _pelapor(server, simpan);
      await p.laporkanGalat(Exception('offline'), null);
      await p.kirimTertunda();
      expect(simpan.isi, hasLength(1));
      final ref = simpan.isi.single['client_ref'];

      server.status = 503;
      await p.kirimTertunda();
      expect(simpan.isi, hasLength(1));

      server.status = 202;
      await p.kirimTertunda();
      expect(simpan.isi, isEmpty);
      expect(server.badan.last['client_ref'], ref);
      expect(server.badan.first['client_ref'], ref);
    });

    test('ditolak permanen (422) dibuang agar antrean tidak tersumbat', () async {
      final server = _Server(422);
      final simpan = PenyimpanDiagnostikMemori();
      final p = _pelapor(server, simpan);
      await p.laporkanGalat(Exception('rusak'), null);
      await p.kirimTertunda();
      expect(simpan.isi, isEmpty);
    });

    test('banjir galat dibatasi maksAntrean', () async {
      final simpan = PenyimpanDiagnostikMemori();
      final p = PelaporDiagnostik(
        dio: Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = _Server(0),
        simpan: simpan,
        versi: '1',
        maksAntrean: 3,
      );
      for (var i = 0; i < 10; i++) {
        await p.laporkanGalat(Exception('galat $i'), null);
      }
      await p.kirimTertunda();
      expect(simpan.isi.length, 3);
      expect(simpan.isi.last['pesan'], contains('galat 9'));
    });

    test('penyimpanan berkas bertahan antar "proses" & berkas rusak tidak melempar', () async {
      final dir = await Directory.systemTemp.createTemp('tuleh-diag-');
      addTearDown(() => dir.delete(recursive: true));
      final a = PenyimpanDiagnostikBerkas(dir: dir);
      await a.tulis([{'client_ref': 'r1'}]);
      expect(await PenyimpanDiagnostikBerkas(dir: dir).baca(), [{'client_ref': 'r1'}]);
      await File('${dir.path}/antrean_diagnostik.json').writeAsString('{rusak');
      expect(await a.baca(), isEmpty);
    });

    test('token Mode Demo tidak dikirim; token asli dipakai', () async {
      final storage = _Storage()..m['token'] = 'demo-token';
      expect(await tokenDiagnostik(storage)(), isNull);
      storage.m['token'] = 'tok-1';
      expect(await tokenDiagnostik(storage)(), 'tok-1');
    });
  });

  test('penangkap galat global: FlutterError → error, PlatformDispatcher → crash, debugPrint → log', () async {
    final server = _Server(202);
    final simpan = PenyimpanDiagnostikMemori();
    final pelapor = _pelapor(server, simpan);
    final flutterBawaan = FlutterError.onError;
    final platformBawaan = PlatformDispatcher.instance.onError;
    final cetakBawaan = debugPrint;
    addTearDown(() {
      FlutterError.onError = flutterBawaan;
      PlatformDispatcher.instance.onError = platformBawaan;
      debugPrint = cetakBawaan;
    });
    FlutterError.onError = (_) {}; // bawaan uji dibungkam agar tidak menggagalkan uji
    pasangPenangkapGalat(pelapor);

    FlutterError.reportError(FlutterErrorDetails(exception: StateError('layar rusak'), stack: StackTrace.current, library: 'widgets'));
    expect(PlatformDispatcher.instance.onError!(Exception('async lolos'), StackTrace.current), isTrue);
    debugPrint('pesan debug Bearer rahasia-xyz');
    await pelapor.kirimTertunda();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pelapor.kirimTertunda();

    final jenis = {for (final b in server.badan) b['pesan']: b['jenis']};
    expect(jenis.entries.firstWhere((e) => '${e.key}'.contains('layar rusak')).value, 'error');
    expect(jenis.entries.firstWhere((e) => '${e.key}'.contains('async lolos')).value, 'crash');
    expect(LogCincin.global.ekor(), contains('pesan debug'));
    expect(LogCincin.global.ekor(), isNot(contains('rahasia-xyz')));
  });

  testWidgets('Pengaturan → "Kirim laporan ke dukungan": ekor log terkirim, nomor laporan tampil', (t) async {
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final server = _Server(202);
    final pelapor = _pelapor(server, PenyimpanDiagnostikMemori());
    LogCincin.global.catat('HTTP POST /transaksi/checkout → 500 (120 ms)');

    final c = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(_Storage()),
      masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      pelaporDiagnostikProvider.overrideWithValue(pelapor),
      ...overrideOffline(),
    ]);
    addTearDown(c.dispose);
    await t.runAsync(() => c.read(authControllerProvider.notifier).startDemo());

    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.light(), home: const PengaturanScreen()),
    ));
    await t.pump(const Duration(milliseconds: 100));

    await t.tap(find.byKey(const Key('entri-kirim-laporan')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('laporan-catatan')), 'Struk tidak keluar');
    await t.tap(find.widgetWithText(FilledButton, 'Kirim'));
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('nomor laporan #D1'), findsOneWidget);
    final b = server.badan.single;
    expect(b['jenis'], 'log');
    expect(b['pesan'], 'Struk tidak keluar');
    expect(b['stack'], contains('/transaksi/checkout → 500'));
    // Mode Demo: tidak ada kontak CS dari server → tidak ada tombol karangan.
    expect(find.byKey(const Key('entri-hubungi-cs')), findsNothing);
  });
}

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {};
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<void> writeToken(String? v) async => v == null || v.isEmpty ? m.remove('token') : m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async => v == null || v.isEmpty ? m.remove('toko') : m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
}
