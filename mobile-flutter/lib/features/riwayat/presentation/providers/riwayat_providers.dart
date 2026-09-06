import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/offline/antrean.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/riwayat_remote_datasource.dart';
import '../../data/repositories/riwayat_repository_impl.dart';
import '../../domain/entities/transaksi.dart';
import '../../domain/entities/transaksi_detail.dart';
import '../../domain/repositories/riwayat_repository.dart';

final riwayatRepositoryProvider = Provider<RiwayatRepository>(
  (ref) => RiwayatRepositoryImpl(RiwayatRemoteDataSource(ref.watch(dioProvider))),
);

/// Daftar transaksi toko aktif (refetch saat toko berganti).
final riwayatListProvider = FutureProvider<List<Transaksi>>((ref) async {
  final tokoId = ref.watch(activeTokoIdProvider).valueOrNull;
  ref.watch(antreanVersiProvider);
  final result = await ref.watch(riwayatRepositoryProvider).list();
  final server = result.when(ok: (v) => v, err: (e) => throw e);
  // Transaksi offline yang belum terkirim ikut tampil (nomor lokal, ditandai)
  // agar kasir melihat penjualannya utuh; setelah terkirim, server yang punya.
  List<TransaksiTertunda> tertunda = const [];
  try {
    tertunda = await ref.watch(antreanStoreProvider).transaksiTertunda(tokoId: tokoId);
  } catch (_) {
    // penyimpanan offline bermasalah — daftar server tetap tampil
  }
  return [
    for (final t in tertunda)
      Transaksi(
        id: '$awalanIdLokal${t.clientRef}',
        nomor: t.nomorLokal,
        grandTotal: t.grandTotal,
        tanggal: t.waktuKlien.toIso8601String(),
        status: statusBelumSinkron,
        metode: t.tipePembayaran,
      ),
    ...server,
  ];
});

/// Id transaksi lokal di daftar riwayat: `lokal:` + client_ref.
const awalanIdLokal = 'lokal:';

/// Status buatan untuk transaksi yang masih menunggu dikirim.
const statusBelumSinkron = 'BELUM_SINKRON';

/// Detail satu transaksi (by id) untuk tampilan struk.
final transaksiDetailProvider =
    FutureProvider.family<TransaksiDetail, String>((ref, id) async {
  // Transaksi lokal (belum terkirim): detail dari struk yang tersimpan.
  if (id.startsWith(awalanIdLokal)) {
    final t = await ref
        .watch(antreanStoreProvider)
        .transaksiLokal(id.substring(awalanIdLokal.length));
    if (t == null) {
      throw const ApiException(
        message: 'Transaksi ini sudah terkirim ke server. Buka dari daftar Riwayat.',
        statusCode: 404,
      );
    }
    final struk = Struk.fromJson(
      Map<String, dynamic>.from(jsonDecode(t.strukJson) as Map),
    );
    return TransaksiDetail(
      id: id,
      nomor: t.nomorLokal,
      tanggal: t.waktuKlien.toIso8601String(),
      status: statusBelumSinkron,
      tipePembayaran: t.tipePembayaran,
      subtotal: t.grandTotal,
      totalDiskon: 0,
      totalPajak: 0,
      grandTotal: t.grandTotal,
      dibayar: t.dibayar,
      kembalian: struk.kembalian ?? 0,
      items: [
        for (final b in struk.baris)
          TrxItem(
            nama: b.nama,
            kuantitas: b.kuantitas.toDouble(),
            harga: b.harga,
            subtotal: b.subtotal,
          ),
      ],
    );
  }
  final result = await ref.watch(riwayatRepositoryProvider).detail(id);
  return result.when(ok: (v) => v, err: (e) => throw e);
});
