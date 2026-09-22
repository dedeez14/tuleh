import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/akses/identitas_segar.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/datasources/keamanan_remote_datasource.dart';
import '../../domain/entities/otorisasi.dart';

final keamananDataSourceProvider = Provider<KeamananRemoteDataSource>(
  (ref) => KeamananRemoteDataSource(ref.watch(dioProvider)),
);

/// Status PIN persetujuan pengguna sendiri — menentukan tampilnya entri
/// Pengaturan. Diambil ulang setiap kali identitas ATAU hak berubah (pola
/// `tokoListProvider`): di perangkat POS yang dipakai bergantian, akun
/// berikutnya tidak boleh mewarisi status akun sebelumnya. Bukan sekadar
/// kosmetik — `boleh_setel` yang basi membuat layar menampilkan penjelasan
/// "belum berlaku" TANPA formulir, jadi orang yang justru berhak tak bisa
/// menyetel PIN sampai aplikasi dijalankan ulang.
final statusPinProvider = FutureProvider<StatusPin>((ref) {
  ref.watch(authControllerProvider.select(
    (a) => '${a.valueOrNull?.id}|${kunciAkses(a.valueOrNull?.akses)}',
  ));
  return ref.watch(keamananDataSourceProvider).statusPin();
});
