import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/offline/antrean.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../../../../core/offline/koneksi.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../../core/offline/rujukan_lokal.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/sesi_remote_datasource.dart';
import '../../data/repositories/sesi_repository_impl.dart';
import '../../domain/entities/sesi.dart';
import '../../domain/entities/sesi_rekap.dart';
import '../../domain/repositories/sesi_repository.dart';

final sesiRepositoryProvider = Provider<SesiRepository>(
  (ref) => SesiRepositoryImpl(SesiRemoteDataSource(ref.watch(dioProvider))),
);

/// Sesi yang dibuka saat offline dan belum terkirim (fase 3): client_ref,
/// waktu dibuka, kas awal. Null bila tidak ada.
typedef SesiLokalTertunda = ({String clientRef, DateTime dibuka, double kasAwal});

final sesiLokalTertundaProvider = FutureProvider<SesiLokalTertunda?>((ref) async {
  ref.watch(antreanVersiProvider);
  final toko = ref.watch(activeTokoIdProvider).valueOrNull;
  for (final p in await ref.watch(antreanStoreProvider).semua()) {
    if (p.jenis != 'SESI_BUKA' || p.status == StatusAntrean.terkirim) continue;
    if (toko != null && p.tokoId != null && p.tokoId != toko) continue;
    final kas = p.body['kas_awal'];
    return (
      clientRef: p.clientRef,
      dibuka: p.dibuat,
      kasAwal: kas is num ? kas.toDouble() : double.tryParse('$kas') ?? 0,
    );
  }
  return null;
});

/// Sesi kasir aktif — sumber kebenaran untuk gating checkout.
/// Bila server tidak punya sesi tetapi ada SESI_BUKA yang menunggu di antrean,
/// sesi lokal `lokal:<ref>` dipakai agar kasir bisa terus melayani offline.
class ActiveSesiNotifier extends AsyncNotifier<Sesi?> {
  @override
  Future<Sesi?> build() async {
    ref.watch(activeTokoIdProvider); // sesi per toko → refresh saat ganti toko
    final lokal = ref.watch(sesiLokalTertundaProvider.select((v) => v.valueOrNull));
    Sesi? server;
    try {
      server = (await ref.watch(sesiRepositoryProvider).aktif())
          .when(ok: (s) => s, err: (e) => throw e);
    } on ApiException {
      if (lokal == null) rethrow;
    }
    if (server != null) return server;
    if (lokal != null) return _sesiLokal(lokal);
    return null;
  }

  static Sesi _sesiLokal(SesiLokalTertunda l) => Sesi(
    id: rujukanLokal(l.clientRef),
    nomor: 'Sesi offline',
    dibukaPada: l.dibuka.toIso8601String(),
  );

  bool get sesiLokal => adalahRujukanLokal(state.valueOrNull?.id);

  /// Buka sesi (kas awal). Gudang diambil otomatis (gudang pertama toko).
  /// Saat offline, permintaan diantrekan (dikirim sebelum transaksi di
  /// belakangnya) dan sesi lokal langsung aktif. Mengembalikan true bila
  /// tertunda. Lempar [ApiException] bila gagal (ditangani pemanggil).
  Future<bool> buka(double kasAwal) async {
    final repo = ref.read(sesiRepositoryProvider);
    var offline = ref.read(koneksiProvider.notifier).offline;
    String? gudang;
    try {
      gudang = (await repo.firstGudangId()).when(ok: (v) => v, err: (e) => throw e);
    } on ApiException catch (e) {
      if (!e.isJaringan) rethrow;
      offline = true; // /gudang belum tersalin & server tak terjangkau → diisi pengurai
    }
    if ((gudang == null || gudang.isEmpty) && !offline) {
      // Aplikasi tidak punya layar gudang (dibuat admin di tatreport.com), jadi
      // pesannya harus menyebut jalan keluarnya — bukan sekadar "tidak ada".
      throw const ApiException(
        message: 'Usaha ini belum punya gudang, jadi sesi kasir belum bisa '
            'dibuka. Minta admin Tuléh membuatkan gudang lebih dulu.',
      );
    }
    final hasil = await ref.read(antreanTulisProvider).jalankan(
      jenis: 'SESI_BUKA',
      path: '/sesi/buka',
      body: {
        'kas_awal': kasAwal,
        if (gudang != null && gudang.isNotEmpty) 'gudang_id': gudang,
      },
      kirim: (badan) async =>
          (await repo.bukaBody(badan)).when(ok: (_) {}, err: (e) => throw e),
    );
    if (hasil.tertunda) {
      ref.read(antreanVersiProvider.notifier).state++;
      state = AsyncData(_sesiLokal((
        clientRef: hasil.clientRef!,
        dibuka: DateTime.now(),
        kasAwal: kasAwal,
      )));
      return true;
    }
    state = await AsyncValue.guard(
      () async => (await repo.aktif()).when(ok: (s) => s, err: (e) => throw e),
    );
    return false;
  }

  /// Tutup sesi aktif dengan kas akhir fisik. Id diambil dari daftar (BUKA).
  /// Ditahan selama masih ada data toko ini yang belum terkirim: rekap server
  /// baru benar setelah antrean kosong.
  Future<void> tutup({required double kasAkhirFisik, String? catatan}) async {
    final repo = ref.read(sesiRepositoryProvider);
    final toko = ref.read(activeTokoIdProvider).valueOrNull;
    final belum = (await ref.read(antreanStoreProvider).semua())
        .where((p) => p.status != StatusAntrean.terkirim)
        .where((p) => toko == null || p.tokoId == null || p.tokoId == toko)
        .length;
    if (belum > 0) {
      throw ApiException(
        message: '$belum data belum terkirim ke server (transaksi, pengeluaran, '
            'atau bon). Sambungkan internet, buka Pengaturan → Sinkronisasi, '
            'dan tunggu sampai kosong sebelum menutup sesi.',
      );
    }
    final id = (await repo.aktifId()).when(ok: (v) => v, err: (e) => throw e);
    if (id == null || id.isEmpty) {
      throw const ApiException(message: 'Sesi aktif tidak ditemukan.');
    }
    (await repo.tutup(id: id, kasAkhirFisik: kasAkhirFisik, catatan: catatan))
        .when(ok: (_) {}, err: (e) => throw e);
    state = const AsyncData(null);
  }
}

final activeSesiProvider =
    AsyncNotifierProvider<ActiveSesiNotifier, Sesi?>(ActiveSesiNotifier.new);

/// Rekap sesi aktif (kas & penjualan). Ikut menyegar saat sesi buka/tutup.
final sesiRekapProvider = FutureProvider<SesiRekap?>((ref) async {
  ref.watch(activeTokoIdProvider);
  ref.watch(activeSesiProvider);
  final r = await ref.watch(sesiRepositoryProvider).rekapAktif();
  return r.when(ok: (v) => v, err: (e) => throw e);
});
