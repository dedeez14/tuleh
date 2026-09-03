import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
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
  Future<Result<void>> bukaBon(String mejaId) async {
    try {
      await remote.bukaBon(mejaId);
      return const Ok(null);
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
  Future<Result<void>> tambahRonde(String billId, List<Map<String, dynamic>> items) async {
    try {
      await remote.tambahRonde(billId, items);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<void>> bayar(String billId, {required String tipe, required double dibayar}) async {
    try {
      await remote.bayar(billId, tipe: tipe, dibayar: dibayar);
      return const Ok(null);
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
