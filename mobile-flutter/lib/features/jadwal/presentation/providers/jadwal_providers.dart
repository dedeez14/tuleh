import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/akses/akses.dart';
import '../../../../core/network/api_client.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/datasources/jadwal_remote_datasource.dart';
import '../../data/repositories/jadwal_repository_impl.dart';
import '../../domain/entities/jadwal.dart';
import '../../domain/repositories/jadwal_repository.dart';

final jadwalRepositoryProvider = Provider<JadwalRepository>(
  (ref) => JadwalRepositoryImpl(JadwalRemoteDataSource(ref.watch(dioProvider))),
);

/// Tanggal yang sedang dilihat, 'YYYY-MM-DD' waktu LOKAL (bukan toIso8601String
/// yang membawa jam & zona) — pola sama dengan pengeluaranBulanProvider.
String tanggalKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final tanggalJadwalProvider = StateProvider<String>((ref) => tanggalKey(DateTime.now()));

/// Slot hari yang dilihat. Yang berhak menata jadwal ikut melihat slot BATAL
/// (`semua=1`) — tanpa itu slot yang dibatalkan hilang dari Android padahal
/// desktop menampilkannya tercoret, sehingga pembatalan tampak seperti data
/// yang lenyap dan slot yang sama dibuat dua kali.
final jadwalHariProvider = FutureProvider<List<JadwalSlot>>((ref) async {
  ref.watch(activeTokoIdProvider);
  final tanggal = ref.watch(tanggalJadwalProvider);
  final semua = ref.watch(bisaProvider('jadwal.kelola'));
  final r = await ref.watch(jadwalRepositoryProvider).daftar(tanggal, semua: semua);
  return r.when(ok: (v) => v, err: (e) => throw e);
});

final jadwalDetailProvider = FutureProvider.family<JadwalSlot, String>((ref, id) async {
  final r = await ref.watch(jadwalRepositoryProvider).detail(id);
  return r.when(ok: (v) => v, err: (e) => throw e);
});
