import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/datasources/toko_remote_datasource.dart';
import '../../data/repositories/toko_repository_impl.dart';
import '../../domain/entities/toko.dart';
import '../../domain/entities/toko_manifest.dart';
import '../../domain/repositories/toko_repository.dart';

final tokoRepositoryProvider = Provider<TokoRepository>(
  (ref) => TokoRepositoryImpl(TokoRemoteDataSource(ref.watch(dioProvider))),
);

/// Daftar toko yang menjadi hak pengguna (dari server, tidak pernah disimpan
/// di perangkat). Server menyaringnya per pengguna (users.pos_toko_id), jadi
/// daftar WAJIB diambil ulang setiap kali pengguna berganti — tanpa ini,
/// keluar lalu masuk dengan akun lain di proses yang sama masih menampilkan
/// toko akun sebelumnya, dan setiap buka sesi di sana ditolak server.
final tokoListProvider = FutureProvider<List<Toko>>((ref) async {
  ref.watch(authControllerProvider.select((a) => a.valueOrNull?.id));
  final result = await ref.watch(tokoRepositoryProvider).list();
  return result.when(ok: (v) => v, err: (e) => throw e);
});

/// Toko aktif (id) — sumber kebenaran di secure storage; dipakai interceptor
/// Dio (toko_id) sehingga data (produk, dll.) otomatis ter-scope toko.
class ActiveTokoNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.watch(secureStorageProvider).readActiveTokoId();

  Future<void> select(String id) async {
    await ref.read(secureStorageProvider).writeActiveTokoId(id);
    state = AsyncData(id);
  }
}

final activeTokoIdProvider =
    AsyncNotifierProvider<ActiveTokoNotifier, String?>(ActiveTokoNotifier.new);

/// Manifest toko aktif — menentukan menu & alur yang tampil (papan pesanan
/// hanya untuk bidang usaha bertahap). Kosong bila toko belum dipilih atau
/// server belum menyediakan endpoint manifest.
class ManifestNotifier extends AsyncNotifier<TokoManifest> {
  /// Notifier ini sudah dibuang (mis. `ref.invalidate(activeManifestProvider)`
  /// dari tombol "Coba lagi" papan pesanan). Sesudah itu `ref` dan `state`
  /// TIDAK boleh disentuh: [segarkan] yang sedang melayang akan melempar
  /// `StateError` di dalam future yang tidak di-await, dan galatnya tak
  /// tertangkap siapa pun. Disetel ulang di setiap `build()` karena penyegaran
  /// biasa (toko aktif berganti) memanggil pembuang milik build sebelumnya
  /// pada instance yang sama.
  bool _mati = false;

  @override
  Future<TokoManifest> build() async {
    _mati = false;
    ref.onDispose(() => _mati = true);
    final id = ref.watch(activeTokoIdProvider).valueOrNull;
    if (id == null || id.isEmpty) return const TokoManifest();
    final r = await ref.watch(tokoRepositoryProvider).manifest(id);
    return r.when(ok: (v) => v, err: (e) => throw e);
  }

  /// Tarik ulang manifest toko aktif TANPA membuang yang sekarang bila gagal.
  ///
  /// Dipakai penyegaran identitas (Tahap B §2b): server menyaring `menus` per
  /// hak akses, jadi hak berubah = menu berubah walau `manifest_version` tidak
  /// bergerak. Berbeda dari `ref.invalidate`, kegagalan di sini tidak
  /// meninggalkan layar dengan galat atau menu bawaan yang lebih lebar dari
  /// peran — manifest lama tetap berlaku sampai server terjangkau lagi.
  ///
  /// Toko dirujuk dengan id TERSIMPAN (yang sudah terbukti diterima server),
  /// bukan hasil pencocokan id antar-jawaban: `encrypt_id` memakai IV acak
  /// sehingga toko yang sama punya id berbeda di tiap jawaban.
  ///
  /// Mengembalikan true bila manifest baru berhasil dipasang — false juga
  /// bila toko aktif keburu berganti atau notifier-nya sudah dibuang.
  Future<bool> segarkan() async {
    if (_mati) return false;
    final id = ref.read(activeTokoIdProvider).valueOrNull;
    if (id == null || id.isEmpty) return false;
    final r = await ref.read(tokoRepositoryProvider).manifest(id);
    // Toko aktif bisa BERGANTI selama perjalanan (tap "Pindah ke …" pada 409,
    // pemilih toko di Beranda). Manifest toko lama yang datang belakangan tak
    // boleh menimpa toko yang baru — gerbang identitas lalu menilai pintu
    // layar memakai menu toko yang salah.
    if (_mati) return false;
    if (ref.read(activeTokoIdProvider).valueOrNull != id) return false;
    return r.when(
      ok: (v) {
        state = AsyncData(v);
        return true;
      },
      err: (_) => false,
    );
  }
}

final activeManifestProvider =
    AsyncNotifierProvider<ManifestNotifier, TokoManifest>(ManifestNotifier.new);
