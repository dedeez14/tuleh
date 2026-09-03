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
  });

  final String nama;
  final String? alamat;
  final String? telepon;
  final String? email;
  final String? npwp;
  final String? logo;
  final String? strukFooter;
  final bool strukTampilLogo;
}
