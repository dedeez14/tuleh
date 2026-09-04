import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/pesanan_remote_datasource.dart';
import '../../data/repositories/pesanan_repository_impl.dart';
import '../../domain/entities/pesanan.dart';
import '../../domain/repositories/pesanan_repository.dart';

final pesananRepositoryProvider = Provider<PesananRepository>(
  (ref) =>
      PesananRepositoryImpl(PesananRemoteDataSource(ref.watch(dioProvider))),
);

/// Pesanan hidup toko aktif. Layar menyegarkannya berkala (polling) lewat
/// `ref.invalidate` — kanal push server belum tersedia (Blueprint §11.6).
final pesananListProvider = FutureProvider.autoDispose<List<Pesanan>>((
  ref,
) async {
  ref.watch(activeTokoIdProvider); // per toko → refresh saat ganti toko
  final r = await ref.watch(pesananRepositoryProvider).list();
  return r.when(ok: (v) => v, err: (e) => throw e);
});

/// Aksi kartu papan (maju tahap / konfirmasi bayar / lunasi). Melempar
/// [ApiException] bila gagal; pemanggil menampilkan pesannya.
class PesananAksi {
  PesananAksi(this._ref);

  final Ref _ref;

  Future<void> transition(
    String id, {
    required String to,
    String? tipePembayaran,
  }) async {
    final r = await _ref
        .read(pesananRepositoryProvider)
        .transition(id, to: to, tipePembayaran: tipePembayaran);
    r.when(ok: (_) {}, err: (e) => throw e);
    _ref.invalidate(pesananListProvider);
  }
}

final pesananAksiProvider = Provider<PesananAksi>((ref) => PesananAksi(ref));
