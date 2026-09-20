import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';

/// Resolver hak akses TUNGGAL (padanan `akses.js` desktop). Hak akses adalah
/// master data server (katalog `pos_hak_akses` × permission peran, diatur
/// pemilik): login & `/auth/me` mengirim `akses[]`. Aplikasi tidak punya
/// matriks peran; tanpa daftar dari server = tidak ada hak (gagal-tertutup).
/// Server tetap memeriksa ulang setiap permintaan (403) — gerbang di sini hanya
/// menyembunyikan tombol yang pasti ditolak.
bool bisaDenganDaftar(Iterable<String>? akses, String kunci) =>
    akses != null && akses.contains(kunci);

/// Kunci hak pengguna sesi berjalan (kosong bila belum masuk).
final aksesProvider = Provider<Set<String>>((ref) {
  final user = ref.watch(authControllerProvider).valueOrNull;
  return user == null ? const <String>{} : user.akses.toSet();
});

/// `ref.watch(bisaProvider('transaksi.refund'))` — true hanya bila server
/// memberi kunci itu.
final bisaProvider = Provider.family<bool, String>(
  (ref, kunci) => bisaDenganDaftar(ref.watch(aksesProvider), kunci),
);
