import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../sesi/domain/entities/sesi_rekap.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/laporan_remote_datasource.dart';
import '../../data/repositories/laporan_repository_impl.dart';
import '../../domain/entities/laporan_keuangan.dart';
import '../../domain/entities/penjualan_hari.dart';
import '../../domain/entities/penjualan_produk.dart';
import '../../domain/repositories/laporan_repository.dart';

final laporanRepositoryProvider = Provider<LaporanRepository>(
  (ref) => LaporanRepositoryImpl(LaporanRemoteDataSource(ref.watch(dioProvider))),
);

final laporanKeuanganProvider = FutureProvider<LaporanKeuangan>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(laporanRepositoryProvider).keuangan();
  return r.when(ok: (v) => v, err: (e) => throw e);
});

final penjualanHarianProvider = FutureProvider<List<PenjualanHari>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(laporanRepositoryProvider).penjualanHarian();
  return r.when(ok: (v) => v, err: (e) => throw e);
});

/// Produk terlaris (bagian pelengkap; repository menoleransi server yang
/// belum mengenal endpointnya).
final penjualanProdukProvider = FutureProvider<List<PenjualanProduk>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(laporanRepositoryProvider).penjualanProduk();
  return r.when(ok: (v) => v, err: (e) => throw e);
});

final rekapKasirProvider = FutureProvider<List<SesiRekap>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final r = await ref.watch(laporanRepositoryProvider).rekapKasir();
  return r.when(ok: (v) => v, err: (e) => throw e);
});
