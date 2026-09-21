import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../kasir/domain/metode_pembayaran.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/pengaturan_remote_datasource.dart';
import '../../data/repositories/pengaturan_repository_impl.dart';
import '../../domain/entities/pengaturan_pembayaran.dart';
import '../../domain/entities/profil_usaha.dart';
import '../../domain/repositories/pengaturan_repository.dart';

final pengaturanRepositoryProvider = Provider<PengaturanRepository>(
  (ref) => PengaturanRepositoryImpl(PengaturanRemoteDataSource(ref.watch(dioProvider))),
);

final profilUsahaProvider = FutureProvider<ProfilUsaha>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(pengaturanRepositoryProvider).profilUsaha();
  return r.when(ok: (v) => v, err: (e) => throw e);
});

/// QRIS statis + rekening untuk layar bayar. Gagal memuat → dianggap kosong
/// (kasir tetap bisa memproses bayar; hanya panduannya yang tak tampil).
final pengaturanPembayaranProvider = FutureProvider<PengaturanPembayaran>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(pengaturanRepositoryProvider).pembayaran();
  return r.when(ok: (v) => v, err: (_) => PengaturanPembayaran.kosong);
});

/// Metode pembayaran aktif dari server (master data). Gagal memuat / server
/// lama → daftar bawaan, supaya kasir tetap bisa menyelesaikan transaksi.
final metodePembayaranProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(activeTokoIdProvider);
  try {
    final kode = await ref.watch(pengaturanRepositoryProvider).metodePembayaran();
    return kode.isEmpty ? metodePembayaranBawaan : kode;
  } catch (_) {
    return metodePembayaranBawaan;
  }
});
