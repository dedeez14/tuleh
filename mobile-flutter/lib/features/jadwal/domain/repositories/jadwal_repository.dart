import '../../../../core/network/api_result.dart';
import '../entities/jadwal.dart';

abstract interface class JadwalRepository {
  Future<Result<List<JadwalSlot>>> daftar(String tanggal, {bool semua});
  Future<Result<JadwalSlot>> detail(String id);
  Future<Result<JadwalSlot>> simpan(IsianJadwal isian);
  Future<Result<JadwalSlot>> ubah(String id, IsianJadwal isian);
  Future<Result<JadwalSlot>> batal(String id);
  Future<Result<PesertaJadwal>> tambahPeserta(String id, String pelangganId);
  Future<Result<PesertaJadwal>> ubahStatusPeserta(String id, String pesertaId, String status);
  Future<Result<void>> lepasPeserta(String id, String pesertaId);
}
