import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

/// Server menyaring daftar toko per pengguna (users.pos_toko_id). Daftar yang
/// tersimpan di memori dari akun sebelumnya tidak boleh dipakai akun
/// berikutnya: begitu pengguna berganti (keluar/masuk), daftar diambil ulang.

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

void main() {
  test('daftar toko diambil ulang saat pengguna berganti, bukan dipakai dari memori', () async {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ],
    );
    addTearDown(c.dispose);
    c.listen(tokoListProvider, (_, _) {}); // jaga provider tetap hidup

    await c.read(authControllerProvider.notifier).startDemo();
    final pertama = await c.read(tokoListProvider.future);
    expect(pertama, isNotEmpty);

    // Keluar akun → daftar lama dibuang (provider kembali memuat).
    await c.read(authControllerProvider.notifier).logout();
    expect(c.read(tokoListProvider).isLoading, isTrue,
        reason: 'daftar akun sebelumnya tidak boleh tersisa');

    // Masuk lagi → daftar segar dari server (demo).
    await c.read(authControllerProvider.notifier).startDemo();
    final kedua = await c.read(tokoListProvider.future);
    expect(kedua, isNotEmpty);
    expect(identical(pertama, kedua), isFalse, reason: 'hasil pengambilan baru');
  });
}
