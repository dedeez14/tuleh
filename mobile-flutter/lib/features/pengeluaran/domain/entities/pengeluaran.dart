/// Kas keluar (pengeluaran) — 1 baris catatan pengeluaran toko.
class Pengeluaran {
  const Pengeluaran({
    required this.id,
    required this.tanggal,
    required this.keterangan,
    required this.nominal,
  });

  final String id;
  final String tanggal; // ISO YYYY-MM-DD
  final String keterangan;
  final double nominal;
}
