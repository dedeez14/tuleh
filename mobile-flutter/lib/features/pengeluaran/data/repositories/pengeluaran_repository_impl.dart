import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../../domain/entities/pengeluaran.dart';
import '../../domain/repositories/pengeluaran_repository.dart';
import '../datasources/pengeluaran_remote_datasource.dart';

class PengeluaranRepositoryImpl implements PengeluaranRepository {
  PengeluaranRepositoryImpl(this.remote, {required this.antrean});

  final PengeluaranRemoteDataSource remote;
  final AntreanTulis antrean;

  @override
  Future<Result<List<Pengeluaran>>> list(String bulan) async {
    try {
      return Ok(await remote.list(bulan));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<HasilTulis>> tambah({
    required String keterangan,
    required double nominal,
    String? tanggal,
  }) async {
    try {
      final hasil = await antrean.jalankan(
        jenis: 'PENGELUARAN',
        path: '/pengeluaran',
        body: {
          'keterangan': keterangan,
          'nominal': nominal,
          if (tanggal != null && tanggal.isNotEmpty) 'tanggal': tanggal,
        },
        kirim: remote.tambahBody,
      );
      return Ok(hasil);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> hapus(String id) async {
    try {
      await remote.hapus(id);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
