/// Status PIN persetujuan pengguna sendiri (`GET /keamanan/pin-saya`).
class StatusPin {
  const StatusPin({this.ada = false, this.bolehSetel = false, this.diubahPada});

  final bool ada;

  /// Server mengizinkan pengguna ini menyetel PIN (punya hak batal/refund).
  final bool bolehSetel;
  final String? diubahPada;
}

/// Pemegang hak yang siap dimintai persetujuan (sudah menyetel PIN).
class PemberiOtorisasi {
  const PemberiOtorisasi({required this.id, required this.nama, this.peran});

  final String id;
  final String nama;
  final String? peran;
}

/// Token persetujuan sekali pakai (berlaku 5 menit) untuk satu aksi & transaksi.
class Otorisasi {
  const Otorisasi({required this.token, this.kedaluwarsa, this.pemberiNama});

  final String token;
  final String? kedaluwarsa;
  final String? pemberiNama;
}
