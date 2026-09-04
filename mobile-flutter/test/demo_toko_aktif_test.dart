import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_client.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/demo/demo_session.dart';
import 'helpers/masa_coba_palsu.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';

/// Regresi: Mode Demo harus menghormati toko yang dipilih pengguna.
///
/// Sebelumnya DemoInterceptor dipasang di DEPAN interceptor yang menambahkan
/// `toko_id`, dan karena `handler.resolve` menghentikan rantai, semua data demo
/// jatuh ke toko pertama — pengguna memilih Barbershop tapi kasir menampilkan
/// katalog minimarket. Test ini memanggil Dio sungguhan lewat provider,
/// bukan mesin demo langsung, supaya urutan interceptor ikut teruji.

class _FakeStorage extends SecureStorage {
  _FakeStorage(this.toko) : super(const FlutterSecureStorage());
  final String toko;
  @override
  Future<String?> readToken() async => 'demo-token';
  @override
  Future<String?> readActiveTokoId() async => toko;
}

void main() {
  Future<List<dynamic>> produkUntuk(String toko) async {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage(toko)),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ],
    );
    addTearDown(c.dispose);
    c.read(demoSessionProvider).start();
    final res = await c.read(dioProvider).get<dynamic>('/produk');
    return (res.data as Map)['data'] as List;
  }

  test('produk demo mengikuti toko aktif dari storage, bukan selalu toko pertama',
      () async {
    final salon = await produkUntuk('TOKO-6');
    expect(salon, isNotEmpty);
    expect(
      salon.every((p) => '${p['id']}'.startsWith('SLN-')),
      isTrue,
      reason: 'toko salon harus memberi katalog SLN-, bukan minimarket',
    );

    final bengkel = await produkUntuk('TOKO-4');
    expect(bengkel.every((p) => '${p['id']}'.startsWith('BKL-')), isTrue);
  });

  test('sesi aktif & pesanan demo juga ter-scope per toko', () async {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage('TOKO-6')),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ],
    );
    addTearDown(c.dispose);
    c.read(demoSessionProvider).start();
    final dio = c.read(dioProvider);

    final orders = ((await dio.get<dynamic>('/orders')).data as Map)['data'] as List;
    expect(orders, isNotEmpty);
    expect(orders.every((o) => '${o['no_antrian']}'.startsWith('S-')), isTrue,
        reason: 'antrian salon berprefix S');

    final sesi = ((await dio.get<dynamic>('/sesi/aktif')).data as Map)['data'] as Map;
    expect(sesi['status'], 'BUKA');
  });

  test('tanpa demo aktif, interceptor demo tidak mencampuri permintaan', () async {
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_FakeStorage('TOKO-6')),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(demoSessionProvider).active, isFalse);
    // Tidak ada jaringan di test → permintaan gagal, tapi bukan karena demo.
    final res = await c
        .read(dioProvider)
        .get<dynamic>('/produk')
        .then((r) => r.statusCode, onError: (_) => -1);
    expect(res, isNot(200));
  });
}
