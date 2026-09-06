import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/sesi.dart';
import '../../domain/entities/sesi_rekap.dart';
import '../../domain/repositories/sesi_repository.dart';
import '../datasources/sesi_remote_datasource.dart';

class SesiRepositoryImpl implements SesiRepository {
  SesiRepositoryImpl(this.remote);

  final SesiRemoteDataSource remote;

  @override
  Future<Result<Sesi?>> aktif() async {
    try {
      return Ok(await remote.aktif());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<SesiRekap?>> rekapAktif() async {
    try {
      return Ok(await remote.rekapAktif());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<String?>> aktifId() async {
    try {
      return Ok(await remote.aktifId());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<String?>> firstGudangId() async {
    try {
      return Ok(await remote.firstGudangId());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> buka({
    required double kasAwal,
    required String gudangId,
    String? catatan,
  }) async {
    try {
      await remote.buka(kasAwal: kasAwal, gudangId: gudangId, catatan: catatan);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> bukaBody(Map<String, dynamic> badan) async {
    try {
      await remote.bukaBody(badan);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> tutup({
    required String id,
    required double kasAkhirFisik,
    String? catatan,
  }) async {
    try {
      await remote.tutup(id: id, kasAkhirFisik: kasAkhirFisik, catatan: catatan);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
