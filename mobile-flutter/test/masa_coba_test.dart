import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/demo/demo_session.dart';
import 'package:tuleh_pos/features/demo/domain/masa_coba.dart';

import 'helpers/masa_coba_palsu.dart';

/// Masa coba Mode Demo 7 hari, dihitung dengan waktu server — padanan
/// frontend/tests/masa-coba.test.js (desktop).

class _FakeStorage extends SecureStorage {
  _FakeStorage() : super(const FlutterSecureStorage());
  final Map<String, String> _m = {};
  @override
  Future<String?> readToken() async => _m['token'];
  @override
  Future<void> writeToken(String? v) async =>
      v == null ? _m.remove('token') : _m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => _m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async =>
      v == null ? _m.remove('toko') : _m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => _m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async =>
      v == null ? _m.remove(k) : _m[k] = v;
  @override
  Future<void> clearSession() async {
    _m.remove('token');
    _m.remove('toko');
  }
}

final t0 = DateTime.utc(2026, 9, 5, 3);
DateTime hari(num n) => t0.add(Duration(minutes: (n * 24 * 60).round()));

void main() {
  group('logika murni', () {
    test('mulai pertama kali WAJIB waktu server', () {
      final tanpa = MasaCoba.periksa(
        catatan: null,
        waktuServer: null,
        perangkat: t0,
        mulaiBaru: true,
      );
      expect(tanpa.kode, KodeMasaCoba.butuhKoneksi);

      final dengan = MasaCoba.periksa(
        catatan: null,
        waktuServer: t0,
        perangkat: hari(-30), // jam perangkat ngawur → diabaikan
        mulaiBaru: true,
      );
      expect(dengan.kode, KodeMasaCoba.aktif);
      expect(dengan.sisaHari, 7);
      expect(dengan.catatan!.mulai, t0);
    });

    test('hari ke-1 sampai ke-7 aktif, hari ke-7 penuh berakhir', () {
      final cat = CatatanMasaCoba(mulai: t0, serverTerakhir: t0);
      StatusMasaCoba pada(num h) => MasaCoba.periksa(
        catatan: cat,
        waktuServer: hari(h),
        perangkat: hari(h),
      );
      expect(pada(0.5).sisaHari, 7);
      expect(pada(6.5).sisaHari, 1);
      expect(pada(7).kode, KodeMasaCoba.berakhir);
      expect(pada(7).sisaHari, 0);
    });

    test('offline: jam perangkat dimundurkan tidak memperpanjang', () {
      var cat = CatatanMasaCoba(mulai: t0, serverTerakhir: t0);
      // Terlihat server pada hari ke-6 → serverTerakhir maju & disimpan.
      final h6 = MasaCoba.periksa(
        catatan: cat,
        waktuServer: hari(6),
        perangkat: hari(6),
      );
      expect(h6.catatan!.serverTerakhir, hari(6));
      cat = h6.catatan!;

      final curang = MasaCoba.periksa(
        catatan: cat,
        waktuServer: null,
        perangkat: hari(1),
      );
      expect(curang.sumberWaktu, 'server_terakhir');
      expect(curang.sisaHari, 1);

      final maju = MasaCoba.periksa(
        catatan: cat,
        waktuServer: null,
        perangkat: hari(9),
      );
      expect(maju.kode, KodeMasaCoba.berakhir);
    });

    test('pemeriksaan biasa pada perangkat yang belum pernah demo → aktif', () {
      final r = MasaCoba.periksa(
        catatan: null,
        waktuServer: null,
        perangkat: t0,
      );
      expect(r.kode, KodeMasaCoba.aktif);
      expect(r.belumMulai, isTrue);
      expect(r.catatan, isNull);
    });
  });

  group('layanan (server tiruan + penyimpanan memori)', () {
    test('membaca header Date server dan menyimpan catatan', () async {
      final svc = MasaCobaPalsu(waktuServer: t0);
      expect(await svc.waktuServer(), t0);

      final st = await svc.periksa(mulaiBaru: true);
      expect(st.kode, KodeMasaCoba.aktif);
      expect(st.sisaHari, 7);

      // Pemeriksaan berikutnya membaca catatan yang sama.
      final lagi = await svc.periksa();
      expect(lagi.belumMulai, isFalse);
      expect(lagi.sisaHari, 7);
    });

    test('server tak terjangkau saat pertama kali → butuh koneksi', () async {
      final svc = MasaCobaPalsu(offline: true);
      expect(await svc.waktuServer(), isNull);
      final st = await svc.periksa(mulaiBaru: true);
      expect(st.kode, KodeMasaCoba.butuhKoneksi);
    });
  });

  group('startDemo dijaga masa coba', () {
    test('masa coba berakhir → AsyncError(MasaCobaException), demo tidak aktif', () async {
      final storage = _FakeStorage();
      // Catatan lama: mulai 10 hari sebelum waktu server tiruan.
      await storage.tulisNilai('demo_mulai', hari(-10).toIso8601String());
      await storage.tulisNilai('demo_server_terakhir', hari(-10).toIso8601String());
      final c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          masaCobaServiceProvider.overrideWithValue(
            MasaCobaPalsu(waktuServer: t0, storage: storage),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(authControllerProvider.notifier).startDemo();
      final st = c.read(authControllerProvider);
      expect(st, isA<AsyncError<dynamic>>());
      expect(st.error, isA<MasaCobaException>());
      expect((st.error as MasaCobaException).status.kode, KodeMasaCoba.berakhir);
      expect(c.read(demoSessionProvider).active, isFalse,
          reason: 'mesin demo tidak boleh dinyalakan');
    });

    test('masa coba aktif → demo berjalan seperti biasa', () async {
      final storage = _FakeStorage();
      final c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          masaCobaServiceProvider.overrideWithValue(
            MasaCobaPalsu(waktuServer: t0, storage: storage),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authControllerProvider.notifier).startDemo();
      expect(c.read(authControllerProvider).valueOrNull, isNotNull);
      expect(c.read(demoSessionProvider).active, isTrue);
      expect(await storage.bacaNilai('demo_mulai'), t0.toIso8601String());
    });
  });
}
