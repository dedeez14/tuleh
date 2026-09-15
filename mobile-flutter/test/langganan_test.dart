// Langganan (kontrak #2 & #3, 2026-09-15): endpoint tulis menjawab 402 saat
// langganan diblokir → layar "Langganan berakhir" dengan tautan dari server,
// transaksi TIDAK diantrekan. Banner peringatan memakai ambang dari server
// (`ambang_peringatan_hari`) — tidak ada angka ambang di aplikasi.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/pengurai.dart';
import 'package:tuleh_pos/core/offline/salinan_store.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/domain/entities/user.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/demo_engine.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/langganan/domain/langganan.dart';
import 'package:tuleh_pos/features/langganan/presentation/langganan_gate.dart';
import 'package:tuleh_pos/features/langganan/presentation/langganan_providers.dart';

import 'helpers/masa_coba_palsu.dart';

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> m = {'token': 'tok-A'};
  @override
  Future<String?> readToken() async => m['token'];
  @override
  Future<String?> readActiveTokoId() async => m['toko'];
  @override
  Future<String?> readAkunTerakhir() async => m['akun'];
  @override
  Future<void> writeAkunTerakhir(String? v) async => v == null ? m.remove('akun') : m['akun'] = v;
  @override
  Future<String?> bacaNilai(String k) async => m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? m.remove(k) : m[k] = v;
}

class _Server implements HttpClientAdapter {
  _Server({this.status = const {}});
  Map<String, dynamic> status;
  bool langgananDiblokir = true;
  final diminta = <String>[];

  ResponseBody _json(Object body, int code) => ResponseBody.fromString(
    jsonEncode(body),
    code,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
  );

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    diminta.add('${o.method} ${o.path}');
    if (o.path == '/auth/me') {
      return _json({'success': true, 'data': {'user': {'id': 'A', 'name': 'Sari'}}}, 200);
    }
    if (o.path == '/langganan/status') return _json({'success': true, 'data': status}, 200);
    if (o.path == '/kontak-cs') {
      return _json({'success': true, 'data': {'sumber': 'CS_PUSAT', 'nama': 'CS Tuléh', 'wa_link': 'https://wa.me/620000?text=x'}}, 200);
    }
    if (o.method != 'GET' && langgananDiblokir) {
      return _json({
        'success': false,
        'data': null,
        'message': 'Langganan usaha Anda berakhir. Perpanjang untuk menyimpan transaksi.',
        'errors': {'langganan': ['BERAKHIR']},
        'meta': {'langganan': {'status': 'KEDALUWARSA', 'perpanjang_url': 'https://contoh.test/perpanjang'}},
      }, 402);
    }
    return _json({'success': true, 'data': {'id': 'S1'}}, 201);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StatusLangganan dari server', () {
    StatusLangganan s(Map<String, dynamic> j) => StatusLangganan.fromJson(j);

    test('ambang dari server menentukan banner; tanpa ambang tidak ada hitung mundur', () {
      expect(s({'status': 'AKTIF', 'sisa_hari': 5, 'ambang_peringatan_hari': 7}).perluPeringatan, isTrue);
      expect(s({'status': 'AKTIF', 'sisa_hari': 8, 'ambang_peringatan_hari': 7}).perluPeringatan, isFalse);
      expect(s({'status': 'AKTIF', 'sisa_hari': 30, 'ambang_peringatan_hari': 30}).perluPeringatan, isTrue);
      expect(s({'status': 'AKTIF', 'sisa_hari': 1}).perluPeringatan, isFalse, reason: 'ambang tidak dikarang aplikasi');
      expect(s({'status': 'TRIAL', 'sisa_hari': null, 'ambang_peringatan_hari': 7}).perluPeringatan, isFalse,
          reason: 'tanpa tenggat');
      expect(s({'status': 'GRACE', 'sisa_hari': 0}).perluPeringatan, isTrue);
      expect(s({'status': 'KEDALUWARSA', 'blokir_tulis': true}).berakhir, isTrue);
      expect(s({'status': 'kedaluwarsa', 'blokir_tulis': true}).blokirTulis, isTrue);
      expect(s({'status': 'AKTIF', 'ambang_peringatan_hari': '14', 'sisa_hari': '3'}).perluPeringatan, isTrue);
    });

    test('URL/nama kosong = belum diisi (null), bukan string kosong', () {
      final st = s({'status': 'AKTIF', 'perpanjang_url': '', 'plan_nama': ' '});
      expect(st.perpanjangUrl, isNull);
      expect(st.planNama, isNull);
      final k = KontakCs.fromJson({'nama': '', 'wa_link': ''});
      expect(k.ada, isFalse);
    });

    test('LanggananTerkunci dari amplop 402', () {
      final t = LanggananTerkunci.dariAmplop({
        'message': 'Berakhir.',
        'meta': {'langganan': {'status': 'kedaluwarsa', 'perpanjang_url': 'https://x.test/p'}},
      }, pesanBawaan: 'bawaan');
      expect(t.pesan, 'Berakhir.');
      expect(t.perpanjangUrl, 'https://x.test/p');
      expect(t.status, 'KEDALUWARSA');
      final kosong = LanggananTerkunci.dariAmplop({'message': '', 'meta': null}, pesanBawaan: 'bawaan');
      expect(kosong.pesan, 'bawaan');
      expect(kosong.perpanjangUrl, isNull);
    });
  });

  group('402 di jalur tulis', () {
    late _Server server;
    late AntreanMemori antrean;

    ProviderContainer wadah() {
      final c = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(_Storage()),
        salinanStoreProvider.overrideWithValue(SalinanMemori()),
        antreanStoreProvider.overrideWithValue(antrean),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        koneksiProvider.overrideWith(() => KoneksiNotifier(jaringan: const Stream.empty())),
      ]);
      addTearDown(c.dispose);
      c.read(dioProvider).httpClientAdapter = server;
      return c;
    }

    setUp(() {
      server = _Server(status: {'status': 'KEDALUWARSA', 'blokir_tulis': true, 'perpanjang_url': 'https://contoh.test/dari-status'});
      antrean = AntreanMemori();
    });

    test('interceptor mengisi layar kunci dari amplop server', () async {
      final c = wadah();
      await c.read(dioProvider).post<dynamic>('/transaksi/checkout', data: const {});
      final kunci = c.read(langgananTerkunciProvider);
      expect(kunci, isNotNull);
      expect(kunci!.perpanjangUrl, 'https://contoh.test/perpanjang');
      expect(kunci.pesan, contains('Perpanjang'));
    });

    test('antrean yang dikirim saat langganan diblokir: tetap MENUNGGU, putaran berhenti', () async {
      await antrean.antrekan(PesanAntrean(
        urut: 0, clientRef: 'c1', jenis: 'CHECKOUT', path: '/transaksi/checkout',
        body: const {}, dibuat: DateTime(2026, 9, 15), pemilik: null,
      ));
      final c = wadah();
      await c.read(penguraiProvider).jalankan();
      final baris = (await antrean.cari('c1'))!;
      expect(baris.status, StatusAntrean.menunggu);
      expect(baris.galatTerakhir, contains('Langganan'));
      expect(c.read(langgananTerkunciProvider), isNotNull);
    });
  });

  group('layar & pita', () {
    Future<ProviderContainer> pompa(
      WidgetTester t, {
      required Widget anak,
      Map<String, dynamic> status = const {'status': 'AKTIF'},
      LanggananTerkunci? kunci,
      List<Uri>? dibuka,
      _Server? server,
    }) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final srv = server ?? _Server(status: status);
      final c = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(_Storage()),
        salinanStoreProvider.overrideWithValue(SalinanMemori()),
        antreanStoreProvider.overrideWithValue(AntreanMemori()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        koneksiProvider.overrideWith(() => KoneksiNotifier(jaringan: const Stream.empty())),
        authControllerProvider.overrideWith(_AuthMasuk.new),
        pembukaTautanProvider.overrideWithValue((uri) async {
          dibuka?.add(uri);
          return true;
        }),
      ]);
      addTearDown(c.dispose);
      c.read(dioProvider).httpClientAdapter = srv;
      if (kunci != null) c.read(langgananTerkunciProvider.notifier).state = kunci;
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light(), home: anak),
      ));
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await t.pump(const Duration(milliseconds: 50));
      }
      return c;
    }

    testWidgets('402 → layar "Langganan berakhir"; tombol membuka URL dari server', (t) async {
      final dibuka = <Uri>[];
      await pompa(
        t,
        anak: const LanggananGate(child: Text('ISI APLIKASI')),
        kunci: const LanggananTerkunci(pesan: 'Langganan berakhir kemarin.', perpanjangUrl: 'https://contoh.test/perpanjang'),
        dibuka: dibuka,
      );
      expect(find.text('Langganan berakhir'), findsOneWidget);
      expect(find.text('Langganan berakhir kemarin.'), findsOneWidget);
      expect(find.text('ISI APLIKASI'), findsNothing);
      await t.tap(find.byKey(const Key('langganan-perpanjang')));
      await t.pump();
      expect(dibuka.single.toString(), 'https://contoh.test/perpanjang');
      // Kontak CS juga dari server.
      expect(find.text('Hubungi CS Tuléh'), findsOneWidget);
    });

    testWidgets('tanpa URL dari server: tidak mengarang tautan', (t) async {
      await pompa(
        t,
        anak: const LanggananGate(child: Text('ISI APLIKASI')),
        status: const {'status': 'KEDALUWARSA', 'blokir_tulis': true},
        kunci: const LanggananTerkunci(pesan: 'Berakhir.'),
      );
      expect(find.byKey(const Key('langganan-perpanjang')), findsNothing);
      expect(find.byKey(const Key('langganan-tanpa-tautan')), findsOneWidget);
    });

    testWidgets('"Tutup & lihat data" melepas layar kunci', (t) async {
      final c = await pompa(
        t,
        anak: const LanggananGate(child: Text('ISI APLIKASI')),
        kunci: const LanggananTerkunci(pesan: 'Berakhir.'),
      );
      await t.tap(find.text('Tutup & lihat data'));
      await t.pump();
      expect(c.read(langgananTerkunciProvider), isNull);
      expect(find.text('ISI APLIKASI'), findsOneWidget);
    });

    testWidgets('periksa lagi: status sudah aktif → kunci dilepas', (t) async {
      final srv = _Server(status: const {'status': 'AKTIF', 'blokir_tulis': false});
      final c = await pompa(
        t,
        anak: const LanggananGate(child: Text('ISI APLIKASI')),
        kunci: const LanggananTerkunci(pesan: 'Berakhir.'),
        server: srv,
      );
      await t.tap(find.text('Saya sudah memperpanjang — periksa lagi'));
      for (var i = 0; i < 8; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(c.read(langgananTerkunciProvider), isNull);
      expect(find.text('ISI APLIKASI'), findsOneWidget);
    });

    testWidgets('pita: tampil bila sisa hari ≤ ambang server', (t) async {
      await pompa(
        t,
        anak: const Scaffold(body: PitaLangganan(child: Text('ISI'))),
        status: const {'status': 'AKTIF', 'sisa_hari': 3, 'ambang_peringatan_hari': 7, 'perpanjang_url': 'https://contoh.test/p'},
      );
      expect(find.byKey(const Key('pita-langganan')), findsOneWidget);
      expect(find.text('Langganan berakhir dalam 3 hari.'), findsOneWidget);
      expect(find.text('Perpanjang'), findsOneWidget);
    });

    testWidgets('pita: tidak tampil bila server tidak mengirim ambang', (t) async {
      await pompa(
        t,
        anak: const Scaffold(body: PitaLangganan(child: Text('ISI'))),
        status: const {'status': 'AKTIF', 'sisa_hari': 3},
      );
      expect(find.byKey(const Key('pita-langganan')), findsNothing);
    });
  });

  test('mesin demo menjawab /langganan/status, /kontak-cs, /diagnostik tanpa nilai karangan', () {
    final e = DemoEngine();
    final st = e.handle(method: 'GET', path: '/langganan/status', query: const {});
    expect(st.status, 200);
    final data = (st.body['data'] as Map).cast<String, dynamic>();
    expect(data['perpanjang_url'], isNull);
    expect(data.containsKey('ambang_peringatan_hari'), isTrue);
    expect(StatusLangganan.fromJson(data).perluPeringatan, isFalse);
    final cs = e.handle(method: 'GET', path: '/kontak-cs', query: const {});
    expect(KontakCs.fromJson((cs.body['data'] as Map).cast<String, dynamic>()).ada, isFalse);
    final d = e.handle(method: 'POST', path: '/diagnostik', query: const {}, body: const {'jenis': 'log'});
    expect(d.status, 202);
    expect((d.body['data'] as Map)['id'], isNotNull);
  });
}

class _AuthMasuk extends AuthController {
  @override
  Future<User?> build() async => const User(id: 'A', name: 'Sari');
}
