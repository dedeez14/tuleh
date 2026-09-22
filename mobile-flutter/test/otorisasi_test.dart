// PIN persetujuan di Android (Tahap B §2c): PIN dikirim sekali, ditukar token sekali pakai,
// tidak pernah disimpan di perangkat.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/akses/akses.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/core/offline/salinan_interceptor.dart';
import 'package:tuleh_pos/core/offline/salinan_store.dart';
import 'package:tuleh_pos/features/keamanan/data/datasources/keamanan_remote_datasource.dart';
import 'package:tuleh_pos/features/keamanan/domain/entities/otorisasi.dart';
import 'package:tuleh_pos/features/keamanan/domain/galat_pin.dart';
import 'package:tuleh_pos/features/keamanan/presentation/providers/keamanan_providers.dart';
import 'package:tuleh_pos/features/auth/domain/entities/user.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/keamanan/presentation/screens/pin_persetujuan_screen.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/screens/pengaturan_screen.dart';

import 'helpers/masa_coba_palsu.dart';

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
    Dio(BaseOptions(baseUrl: 'https://x.test/api', validateStatus: (_) => true))..httpClientAdapter = s;

/// Datasource tiruan untuk tes layar: tanpa jaringan, bisa menahan jawaban
/// (menguji layar yang ditutup saat permintaan masih melayang).
class _DsPalsu extends KeamananRemoteDataSource {
  _DsPalsu({StatusPin? status})
    : status = status ?? const StatusPin(bolehSetel: true),
      super(Dio());

  StatusPin status;

  /// Galat yang dilempar `simpanPin`/`hapusPin`.
  Object? lempar;

  /// Bila diisi, jawaban tertahan sampai completer ini selesai.
  Completer<void>? tahan;

  final dipanggil = <String>[];
  String? pinTerkirim;
  String? pinLamaTerkirim;

  /// Berapa kali server ditanyai — status basi milik akun lain terdeteksi di sini.
  int statusDiminta = 0;

  @override
  Future<StatusPin> statusPin() async {
    statusDiminta += 1;
    return status;
  }

  @override
  Future<void> simpanPin({required String pin, String? pinLama}) async {
    dipanggil.add('simpan');
    pinTerkirim = pin;
    pinLamaTerkirim = pinLama;
    await tahan?.future;
    if (lempar != null) throw lempar!;
    status = StatusPin(ada: true, bolehSetel: status.bolehSetel);
  }

  @override
  Future<void> hapusPin({required String pinLama}) async {
    dipanggil.add('hapus');
    pinLamaTerkirim = pinLama;
    await tahan?.future;
    if (lempar != null) throw lempar!;
    status = StatusPin(bolehSetel: status.bolehSetel);
  }
}

/// Pengguna yang bisa diganti di tengah tes (perangkat POS dipakai bergantian).
class _AuthPalsu extends AuthController {
  _AuthPalsu(this._user);

  User? _user;

  @override
  Future<User?> build() async => _user;

  void ganti(User u) {
    _user = u;
    state = AsyncData(u);
  }
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

/// Penanda koneksi tiruan — mencatat apakah interceptor menyalakan pita offline.
class _Penanda implements PenandaKoneksi {
  bool offlineDitandai = false;
  bool onlineDitandai = false;

  @override
  bool get offline => offlineDitandai;

  @override
  void tandaiOffline({DateTime? ditarikPada}) => offlineDitandai = true;

  @override
  void tandaiOnline() => onlineDitandai = true;
}

Future<void> _buka(WidgetTester t, _DsPalsu ds) async {
  t.view.physicalSize = const Size(420, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [keamananDataSourceProvider.overrideWithValue(ds)],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(builder: (_) => const PinPersetujuanScreen()),
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('buka'));
  await t.pumpAndSettle();
}

void main() {
  test('statusPin membaca ada/boleh_setel; server lama tanpa bidang = belum ada & tak boleh setel', () async {
    final ada = await KeamananRemoteDataSource(_dio(_Server((_) => _json({
      'success': true, 'data': {'ada': true, 'boleh_setel': true, 'diubah_pada': '2026-09-21T10:00:00+07:00'},
    })))).statusPin();
    expect(ada.ada, isTrue);
    expect(ada.bolehSetel, isTrue);
    expect(ada.diubahPada, '2026-09-21T10:00:00+07:00');

    final lama = await KeamananRemoteDataSource(_dio(_Server((_) => _json({'success': true, 'data': {}})))).statusPin();
    expect(lama.ada, isFalse);
    expect(lama.bolehSetel, isFalse);
  });

  test('simpanPin PUT dengan pin_lama hanya bila diisi; hapusPin DELETE', () async {
    final s = _Server((_) => _json({'success': true, 'data': {'ada': true}}));
    final ds = KeamananRemoteDataSource(_dio(s));
    await ds.simpanPin(pin: '2468');
    expect(s.permintaan.last.method, 'PUT');
    expect(s.permintaan.last.data, {'pin': '2468'});
    await ds.simpanPin(pin: '13579', pinLama: '2468');
    expect(s.permintaan.last.data, {'pin': '13579', 'pin_lama': '2468'});
    await ds.hapusPin(pinLama: '2468');
    expect(s.permintaan.last.method, 'DELETE');
    expect(s.permintaan.last.path, '/keamanan/pin-saya');
    expect(s.permintaan.last.data, {'pin_lama': '2468'});
  });

  test('pemberi() memetakan id/nama/peran; otorisasi() mengirim kontrak & mengembalikan token', () async {
    final s = _Server((o) => o.path == '/keamanan/pemberi-otorisasi'
        ? _json({'success': true, 'data': [{'id': 'U1', 'nama': 'Manajer', 'peran': 'Manager'}]})
        : _json({'success': true, 'data': {'token': 'abc.def', 'kedaluwarsa': '2026-09-21T10:05:00+07:00', 'pemberi': {'id': 'U1', 'nama': 'Manajer'}}}));
    final ds = KeamananRemoteDataSource(_dio(s));

    final daftar = await ds.pemberi();
    expect(daftar.single.nama, 'Manajer');
    expect(daftar.single.peran, 'Manager');

    final ot = await ds.otorisasi(pemberiId: 'U1', pin: '2468', aksi: 'transaksi.batal', transaksiId: 'T/1==');
    expect(s.permintaan.last.data, {'pemberi_id': 'U1', 'pin': '2468', 'aksi': 'transaksi.batal', 'transaksi_id': 'T/1=='});
    expect(ot.token, 'abc.def');
    expect(ot.pemberiNama, 'Manajer');
  });

  test('PIN salah (422) & terkunci (429) diteruskan sebagai ApiException berpesan server', () async {
    final salah = _Server((_) => _json({'success': false, 'message': 'PIN salah. Sisa percobaan: 3.'}, 422));
    await expectLater(
      KeamananRemoteDataSource(_dio(salah)).otorisasi(pemberiId: 'U1', pin: '1111', aksi: 'transaksi.batal', transaksiId: 'T1'),
      throwsA(isA<ApiException>().having((e) => e.message, 'pesan', contains('Sisa percobaan'))),
    );
    final kunci = _Server((_) => _json({'success': false, 'message': 'Terlalu banyak PIN salah. Coba lagi dalam 60 detik.'}, 429));
    await expectLater(
      KeamananRemoteDataSource(_dio(kunci)).otorisasi(pemberiId: 'U1', pin: '1111', aksi: 'transaksi.batal', transaksiId: 'T1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
    );
  });

  group('kunci PIN (429)', () {
    test('data.terkunci_detik ikut terbawa galat, sisa detiknya bisa dihitung mundur', () async {
      final s = _Server((_) => _json({
        'success': false,
        'data': {'terkunci_detik': 42},
        'message': 'Terlalu banyak PIN salah. Coba lagi dalam 42 detik.',
        'errors': {'kode': ['PIN_TERKUNCI']},
      }, 429));
      await expectLater(
        KeamananRemoteDataSource(_dio(s)).simpanPin(pin: '1111', pinLama: '2222'),
        throwsA(isA<PinTerkunci>().having((e) => e.detik, 'detik', 42)),
      );
    });

    test('tanpa angka dari server, kalimat server dipakai apa adanya (durasi tak dikarang)', () async {
      final s = _Server((_) => _json({
        'success': false,
        'message': 'Terlalu banyak PIN salah. Coba lagi sebentar.',
        'errors': {'kode': ['PIN_TERKUNCI']},
      }, 429));
      try {
        await KeamananRemoteDataSource(_dio(s)).hapusPin(pinLama: '2222');
        fail('seharusnya melempar');
      } on ApiException catch (e) {
        expect(detikTerkunci(e), 0);
        expect(pesanTerkunci(e), 'Terlalu banyak PIN salah. Coba lagi sebentar.');
      }
    });

    test('pesanTerkunci hanya untuk 429; galat lain dibiarkan pemanggil', () {
      expect(pesanTerkunci(const ApiException(message: 'PIN salah. Sisa percobaan: 3.', statusCode: 422)), isNull);
      expect(
        pesanTerkunci(const PinTerkunci(message: 'apa pun', detik: 7)),
        'Terlalu banyak PIN salah. Coba lagi dalam 7 detik.',
      );
      expect(detikTerkunci(const ApiException(message: 'x', statusCode: 429)), 0);
    });

    test('429 berkode domain BUKAN gangguan: pita offline tidak menyala', () async {
      final penanda = _Penanda();
      final dio = _dio(_Server((_) => _json({
        'success': false,
        'data': {'terkunci_detik': 30},
        'message': 'Terlalu banyak PIN salah. Coba lagi dalam 30 detik.',
        'errors': {'kode': ['PIN_TERKUNCI']},
      }, 429)))
        ..interceptors.add(SalinanInterceptor(store: SalinanMemori(), koneksi: penanda));
      await dio.put<dynamic>('/keamanan/pin-saya', data: const {'pin': '1111'});
      expect(penanda.offlineDitandai, isFalse, reason: 'penolakan domain, bukan server bermasalah');
      expect(penanda.onlineDitandai, isTrue);
    });

    test('429 tanpa kode domain tetap gangguan (rem coba-lagi server)', () async {
      final penanda = _Penanda();
      final dio = _dio(_Server((_) => _json({'success': false, 'message': 'Pelan-pelan'}, 429)))
        ..interceptors.add(SalinanInterceptor(store: SalinanMemori(), koneksi: penanda));
      await dio.put<dynamic>('/x', data: const {});
      expect(penanda.offlineDitandai, isTrue);
    });
  });

  group('status PIN milik pengguna yang sedang masuk', () {
    test('ganti akun / ganti hak → status dimuat ulang, bukan nilai pengguna sebelumnya', () async {
      final ds = _DsPalsu(status: const StatusPin(ada: true, bolehSetel: false));
      final auth = _AuthPalsu(const User(id: 'U1', name: 'Kasir', akses: ['kasir.transaksi']));
      final c = ProviderContainer(overrides: [
        keamananDataSourceProvider.overrideWithValue(ds),
        authControllerProvider.overrideWith(() => auth),
      ]);
      addTearDown(c.dispose);
      // Identitas selesai dimuat dulu: selama auth masih AsyncLoading, kuncinya
      // memang berbeda (dan status ditarik ulang begitu penggunanya diketahui).
      await c.read(authControllerProvider.future);
      c.listen(statusPinProvider, (_, _) {});

      expect((await c.read(statusPinProvider.future)).bolehSetel, isFalse);
      expect(ds.statusDiminta, 1);

      // Akun lain masuk di perangkat yang sama: status lama TIDAK boleh melekat —
      // boleh_setel basi menutup formulir bagi orang yang justru berhak.
      ds.status = const StatusPin(bolehSetel: true);
      auth.ganti(const User(id: 'U2', name: 'Manajer', akses: ['transaksi.batal', 'keamanan.pin']));
      expect((await c.read(statusPinProvider.future)).bolehSetel, isTrue);
      expect(ds.statusDiminta, 2);

      // Hak dicabut pemilik pada akun yang sama.
      ds.status = const StatusPin(bolehSetel: false);
      auth.ganti(const User(id: 'U2', name: 'Manajer', akses: ['kasir.transaksi']));
      expect((await c.read(statusPinProvider.future)).bolehSetel, isFalse);
      expect(ds.statusDiminta, 3);
    });

    test('GET /keamanan/ tidak pernah disalin (status basi = kebingungan yang sama)', () async {
      final store = SalinanMemori();
      final dio = _dio(_Server((_) => _json({'success': true, 'data': {'ada': true, 'boleh_setel': true}})))
        ..interceptors.add(SalinanInterceptor(store: store, koneksi: _Penanda()));
      await dio.get<dynamic>('/keamanan/pin-saya');
      await dio.get<dynamic>('/keamanan/pemberi-otorisasi');
      expect(store.jumlah, 0);
    });
  });

  group('entri Pengaturan → PIN persetujuan saya', () {
    Future<void> bukaPengaturan(WidgetTester t, {required Set<String> akses, required StatusPin status}) async {
      t.view.physicalSize = const Size(420, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final c = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(_Storage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        keamananDataSourceProvider.overrideWithValue(_DsPalsu(status: status)),
        aksesProvider.overrideWithValue(akses),
        ...overrideOffline(),
      ]);
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(authControllerProvider.notifier).startDemo());
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light(), home: const PengaturanScreen()),
      ));
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('tanpa hak keamanan.pin: entri disembunyikan (gagal-tertutup)', (t) async {
      await bukaPengaturan(t, akses: const {'kasir.transaksi'}, status: const StatusPin(bolehSetel: true));
      expect(find.byKey(const Key('entri-pin-persetujuan')), findsNothing);
    });

    testWidgets('punya hak tapi boleh_setel false: entri tetap tampil dengan sebabnya', (t) async {
      await bukaPengaturan(t, akses: const {'keamanan.pin'}, status: const StatusPin(bolehSetel: false));
      expect(find.byKey(const Key('entri-pin-persetujuan')), findsOneWidget);
      expect(find.text('Belum berlaku untuk akun Anda'), findsOneWidget);
    });

    testWidgets('boleh_setel true & PIN sudah ada: subjudul menyebut PIN aktif', (t) async {
      await bukaPengaturan(t, akses: const {'keamanan.pin'}, status: const StatusPin(ada: true, bolehSetel: true));
      expect(find.textContaining('PIN aktif'), findsOneWidget);
    });
  });

  group('layar PIN persetujuan saya', () {
    testWidgets('belum ada PIN: satu isian, tanpa "PIN lama", tanpa tombol hapus', (t) async {
      await _buka(t, _DsPalsu());
      expect(find.textContaining('tanpa kata sandi akun'), findsOneWidget);
      expect(find.text('PIN (4–8 digit)'), findsOneWidget);
      expect(find.text('PIN lama'), findsNothing);
      expect(find.text('Hapus PIN'), findsNothing);
      expect(find.text('Pasang PIN'), findsOneWidget);
    });

    testWidgets('tanpa hak batal/refund (boleh_setel false): alasan ditampilkan, formulir tidak', (t) async {
      await _buka(t, _DsPalsu(status: const StatusPin(bolehSetel: false)));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Pasang PIN'), findsNothing);
      expect(find.textContaining('membatalkan atau merefund'), findsOneWidget);
    });

    testWidgets('pasang PIN: terkirim ke server, status disegarkan, pemberitahuan tampil', (t) async {
      final ds = _DsPalsu();
      await _buka(t, ds);
      await t.enterText(find.byKey(const Key('pin-baru')), '2468');
      await t.tap(find.text('Pasang PIN'));
      await t.pumpAndSettle();
      expect(ds.pinTerkirim, '2468');
      expect(ds.pinLamaTerkirim, isNull);
      expect(find.text('PIN persetujuan tersimpan.'), findsOneWidget);
      expect(find.text('Ganti PIN'), findsOneWidget, reason: 'status disegarkan dari server');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('ganti PIN mengirim pin_lama', (t) async {
      final ds = _DsPalsu(status: const StatusPin(ada: true, bolehSetel: true));
      await _buka(t, ds);
      await t.enterText(find.byKey(const Key('pin-baru')), '13579');
      await t.enterText(find.byKey(const Key('pin-lama')), '2468');
      await t.tap(find.text('Ganti PIN'));
      await t.pumpAndSettle();
      expect(ds.pinTerkirim, '13579');
      expect(ds.pinLamaTerkirim, '2468');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('ganti tanpa isi PIN lama: galat lokal, server tidak dipanggil', (t) async {
      final ds = _DsPalsu(status: const StatusPin(ada: true, bolehSetel: true));
      await _buka(t, ds);
      await t.enterText(find.byKey(const Key('pin-baru')), '13579');
      await t.tap(find.text('Ganti PIN'));
      await t.pumpAndSettle();
      expect(find.text('Isi PIN lama untuk mengganti PIN.'), findsOneWidget);
      expect(ds.dipanggil, isEmpty, reason: 'jatah percobaan PIN di server tak dihabiskan');
    });

    testWidgets('hapus tanpa isi PIN lama: galat lokal, server tidak dipanggil', (t) async {
      final ds = _DsPalsu(status: const StatusPin(ada: true, bolehSetel: true));
      await _buka(t, ds);
      await t.tap(find.text('Hapus PIN'));
      await t.pumpAndSettle();
      expect(find.text('Isi PIN lama untuk menghapus PIN.'), findsOneWidget);
      expect(ds.dipanggil, isEmpty);
      expect(find.text('Hapus PIN persetujuan?'), findsNothing, reason: 'konfirmasi tak perlu dibuka');
    });

    testWidgets('hapus PIN: konfirmasi dulu, lalu pin_lama dikirim', (t) async {
      final ds = _DsPalsu(status: const StatusPin(ada: true, bolehSetel: true));
      await _buka(t, ds);
      await t.enterText(find.byKey(const Key('pin-lama')), '2468');
      await t.tap(find.text('Hapus PIN'));
      await t.pumpAndSettle();
      expect(find.text('Hapus PIN persetujuan?'), findsOneWidget);
      await t.tap(find.byKey(const Key('pin-hapus-ya')));
      await t.pumpAndSettle();
      expect(ds.dipanggil, ['hapus']);
      expect(ds.pinLamaTerkirim, '2468');
      expect(find.text('Pasang PIN'), findsOneWidget, reason: 'kembali ke keadaan belum ada PIN');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('PIN salah: kalimat server tampil; kode mesin tidak pernah terlihat', (t) async {
      final ds = _DsPalsu(status: const StatusPin(ada: true, bolehSetel: true))
        ..lempar = const ApiException(
          message: 'PIN salah. Sisa percobaan: 3.',
          statusCode: 422,
          errors: {'kode': ['PIN_SALAH']},
        );
      await _buka(t, ds);
      await t.enterText(find.byKey(const Key('pin-baru')), '13579');
      await t.enterText(find.byKey(const Key('pin-lama')), '1111');
      await t.tap(find.text('Ganti PIN'));
      await t.pumpAndSettle();
      expect(find.text('PIN salah. Sisa percobaan: 3.'), findsOneWidget);
      expect(find.textContaining('PIN_SALAH'), findsNothing);
    });

    testWidgets('terkunci: hitung mundur berjalan & tombol mati sampai habis', (t) async {
      final ds = _DsPalsu(status: const StatusPin(ada: true, bolehSetel: true))
        ..lempar = const PinTerkunci(
          message: 'Terlalu banyak PIN salah. Coba lagi dalam 2 detik.',
          detik: 2,
          errors: {'kode': ['PIN_TERKUNCI']},
        );
      await _buka(t, ds);
      await t.enterText(find.byKey(const Key('pin-baru')), '13579');
      await t.enterText(find.byKey(const Key('pin-lama')), '1111');
      await t.tap(find.text('Ganti PIN'));
      await t.pump();
      await t.pump();
      expect(find.text('Terlalu banyak PIN salah. Coba lagi dalam 2 detik.'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('pin-simpan'))).onPressed, isNull);

      await t.pump(const Duration(seconds: 1));
      expect(find.text('Terlalu banyak PIN salah. Coba lagi dalam 1 detik.'), findsOneWidget);

      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('Coba lagi dalam'), findsNothing);
      expect(t.widget<FilledButton>(find.byKey(const Key('pin-simpan'))).onPressed, isNotNull);
    });

    testWidgets('layar ditutup saat permintaan melayang: tidak mengaku sukses & tidak meledak', (t) async {
      final tahan = Completer<void>();
      final ds = _DsPalsu()..tahan = tahan;
      await _buka(t, ds);
      await t.enterText(find.byKey(const Key('pin-baru')), '2468');
      await t.tap(find.text('Pasang PIN'));
      await t.pump();

      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('buka'), findsOneWidget, reason: 'layar sudah ditutup');

      tahan.complete();
      await t.pumpAndSettle();
      expect(find.text('PIN persetujuan tersimpan.'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
