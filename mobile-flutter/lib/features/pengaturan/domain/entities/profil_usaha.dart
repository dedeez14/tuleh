import '../../../products/domain/entities/pilihan_produk.dart';

/// Profil usaha (toko) + pengaturan struk.
class ProfilUsaha {
  const ProfilUsaha({
    required this.nama,
    this.alamat,
    this.telepon,
    this.email,
    this.npwp,
    this.logo,
    this.strukFooter,
    this.strukTampilLogo = true,
    this.satuanBawaan,
  });

  final String nama;
  final String? alamat;
  final String? telepon;
  final String? email;
  final String? npwp;
  final String? logo;
  final String? strukFooter;
  final bool strukTampilLogo;

  /// Satuan bawaan produk baru (master data per usaha, server 2026-09-15).
  /// null = belum diatur → produk baru wajib memilih satuan. Id-nya terenkripsi
  /// NON-deterministik: cocokkan ke daftar `/satuan` lewat `kode`, bukan `id`.
  final SatuanPilihan? satuanBawaan;
}
