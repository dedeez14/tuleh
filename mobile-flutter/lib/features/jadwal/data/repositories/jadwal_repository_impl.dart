import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../domain/entities/jadwal.dart';
import '../../domain/repositories/jadwal_repository.dart';
import '../datasources/jadwal_remote_datasource.dart';

class JadwalRepositoryImpl implements JadwalRepository {
  JadwalRepositoryImpl(this.remote);

  final JadwalRemoteDataSource remote;

  Future<Result<T>> _bungkus<T>(Future<T> Function() aksi) async {
    try {
      return Ok(await aksi());
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<List<JadwalSlot>>> daftar(String tanggal, {bool semua = false}) =>
      _bungkus(() => remote.daftar(tanggal, semua: semua));

  @override
  Future<Result<JadwalSlot>> detail(String id) => _bungkus(() => remote.detail(id));

  @override
  Future<Result<JadwalSlot>> simpan(IsianJadwal isian) => _bungkus(() => remote.simpan(isian));

  @override
  Future<Result<JadwalSlot>> ubah(String id, IsianJadwal isian) => _bungkus(() => remote.ubah(id, isian));

  @override
  Future<Result<JadwalSlot>> batal(String id) => _bungkus(() => remote.batal(id));

  @override
  Future<Result<PesertaJadwal>> tambahPeserta(String id, String pelangganId) =>
      _bungkus(() => remote.tambahPeserta(id, pelangganId));

  @override
  Future<Result<PesertaJadwal>> ubahStatusPeserta(String id, String pesertaId, String status) =>
      _bungkus(() => remote.ubahStatusPeserta(id, pesertaId, status));

  @override
  Future<Result<void>> lepasPeserta(String id, String pesertaId) =>
      _bungkus(() => remote.lepasPeserta(id, pesertaId));
}
