/// Modul Jadwal (gym, klinik): satu slot kelas/janji temu beserta pesertanya.
/// Kelas polos imutable — entitas baru tidak memakai freezed supaya repo tidak
/// perlu `build_runner` untuk berkas turunan.
class PesertaJadwal {
  const PesertaJadwal({
    required this.id,
    required this.pelangganId,
    required this.nama,
    required this.status,
    this.telepon,
  });

  final String id;
  final String pelangganId;
  final String nama;
  final String? telepon;

  /// TERDAFTAR | HADIR | BATAL (master status peserta di server).
  final String status;

  bool get hadir => status == 'HADIR';
}

class JadwalSlot {
  const JadwalSlot({
    required this.id,
    required this.nama,
    required this.tanggal,
    required this.jamMulai,
    required this.status,
    this.jamSelesai,
    this.kuota,
    this.sisaKuota,
    this.pesertaCount = 0,
    this.pengajar,
    this.catatan,
    this.peserta = const [],
  });

  final String id;
  final String nama;

  /// 'YYYY-MM-DD' dan 'HH:MM' apa adanya dari server (tanpa zona waktu).
  final String tanggal;
  final String jamMulai;
  final String? jamSelesai;

  /// null = tanpa batas peserta; maka [sisaKuota] juga null.
  final int? kuota;
  final int? sisaKuota;
  final int pesertaCount;
  final String? pengajar;
  final String? catatan;
  final String status;

  /// Hanya terisi dari detail (`GET /jadwal/{id}`) — daftar per hari ringkas.
  final List<PesertaJadwal> peserta;

  bool get aktif => status == 'AKTIF';

  bool get penuh => kuota != null && (sisaKuota ?? 0) <= 0;

  String get rentangJam => jamSelesai == null ? jamMulai : '$jamMulai–$jamSelesai';
}

/// Isian formulir slot — sama untuk buat (POST) dan ubah (PUT, ganti penuh).
class IsianJadwal {
  const IsianJadwal({
    required this.nama,
    required this.tanggal,
    required this.jamMulai,
    this.jamSelesai,
    this.kuota,
    this.pengajar,
    this.catatan,
  });

  final String nama;
  final String tanggal;
  final String jamMulai;
  final String? jamSelesai;
  final int? kuota;
  final String? pengajar;
  final String? catatan;

  Map<String, dynamic> toJson() => {
    'nama': nama,
    'tanggal': tanggal,
    'jam_mulai': jamMulai,
    'jam_selesai': jamSelesai,
    'kuota': kuota,
    'pengajar': pengajar,
    'catatan': catatan,
  };
}
