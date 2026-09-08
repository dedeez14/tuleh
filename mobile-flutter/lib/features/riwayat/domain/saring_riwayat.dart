import 'entities/transaksi.dart';

/// Penyaring daftar Riwayat: status transaksi.
enum SaringStatus {
  semua('Semua'),
  selesai('Selesai'),
  dibatalkan('Dibatalkan'),
  belumSinkron('Belum sinkron');

  const SaringStatus(this.label);
  final String label;
}

/// Rentang tanggal yang sering ditanyakan kasir/pemilik.
enum SaringRentang {
  semua('Semua tanggal', null),
  hariIni('Hari ini', 0),
  tujuhHari('7 hari', 6),
  tigaPuluhHari('30 hari', 29);

  const SaringRentang(this.label, this.mundurHari);
  final String label;

  /// Berapa hari ke belakang dari hari ini; null = tanpa batas.
  final int? mundurHari;
}

bool _dibatalkan(Transaksi t) =>
    (t.status ?? '').toUpperCase().contains('BATAL');

bool _cocokStatus(Transaksi t, SaringStatus s) => switch (s) {
  SaringStatus.semua => true,
  SaringStatus.dibatalkan => _dibatalkan(t),
  SaringStatus.belumSinkron => t.status == 'BELUM_SINKRON',
  SaringStatus.selesai => !_dibatalkan(t) && t.status != 'BELUM_SINKRON',
};

/// Angka saja dari teks: "Rp 18.500" dan "18500" sama-sama jadi "18500",
/// sehingga kasir bisa mencari transaksi lewat nominalnya.
String _angka(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

bool _cocokKata(Transaksi t, String kueri) {
  final q = kueri.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (t.nomor.toLowerCase().contains(q)) return true;
  if ((t.metode ?? '').toLowerCase().contains(q)) return true;
  final angka = _angka(q);
  if (angka.isNotEmpty && t.grandTotal.round().toString().contains(angka)) {
    return true;
  }
  return false;
}

bool _cocokRentang(Transaksi t, SaringRentang r, DateTime sekarang) {
  final mundur = r.mundurHari;
  if (mundur == null) return true;
  final waktu = DateTime.tryParse(t.tanggal ?? '');
  if (waktu == null) return false;
  final awal = DateTime(
    sekarang.year,
    sekarang.month,
    sekarang.day,
  ).subtract(Duration(days: mundur));
  return !waktu.isBefore(awal);
}

/// Saring daftar riwayat sesuai kueri, status, dan rentang tanggal.
/// Fungsi murni — urutan asal dipertahankan.
List<Transaksi> saringRiwayat(
  List<Transaksi> list, {
  String kueri = '',
  SaringStatus status = SaringStatus.semua,
  SaringRentang rentang = SaringRentang.semua,
  DateTime? sekarang,
}) {
  final kini = sekarang ?? DateTime.now();
  return [
    for (final t in list)
      if (_cocokStatus(t, status) &&
          _cocokRentang(t, rentang, kini) &&
          _cocokKata(t, kueri))
        t,
  ];
}
