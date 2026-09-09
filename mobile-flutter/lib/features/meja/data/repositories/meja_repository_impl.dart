import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../../domain/entities/bill_detail.dart';
import '../../domain/entities/meja.dart';
import '../../domain/repositories/meja_repository.dart';
import '../datasources/meja_remote_datasource.dart';

class MejaRepositoryImpl implements MejaRepository {
  MejaRepositoryImpl(this.remote);

  final MejaRemoteDataSource remote;

  @override
  Future<Result<List<Meja>>> peta() async {
    try {
      return Ok(await remote.peta());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<HasilTulis>> bukaBon(String mejaId, {int pax = 1}) async {
    try {
      await remote.bukaBon(mejaId, pax: pax);
      return const Ok(HasilTulis.langsung);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<BillDetail>> detail(String billId) async {
    try {
      return Ok(await remote.detail(billId));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<HasilTulis>> tambahRonde(
    String billId,
    List<Map<String, dynamic>> items, {
    List<Map<String, dynamic>> tampilan = const [],
  }) async {
    try {
      await remote.tambahRonde(billId, items);
      return const Ok(HasilTulis.langsung);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<HasilTulis>> bayar(String billId, {required String tipe, required double dibayar}) async {
    try {
      await remote.bayar(billId, tipe: tipe, dibayar: dibayar);
      return const Ok(HasilTulis.langsung);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<List<Meja>>> daftarMeja({bool semua = false}) =>
      _jalankan(() => remote.daftarMeja(semua: semua));

  @override
  Future<Result<Meja>> tambahMeja(String nomor) => _jalankan(() => remote.tambahMeja(nomor));

  @override
  Future<Result<Meja>> ubahMeja(String id, String nomor) =>
      _jalankan(() => remote.ubahMeja(id, nomor));

  @override
  Future<Result<Meja>> nonaktifkanMeja(String id) =>
      _jalankan(() => remote.nonaktifkanMeja(id));

  /// Kelola meja hanya online: tidak ada gunanya mengantre perubahan daftar
  /// meja (bentrok nomor & hak akses baru ketahuan di server).
  Future<Result<T>> _jalankan<T>(Future<T> Function() aksi) async {
    try {
      return Ok(await aksi());
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
