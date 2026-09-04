/// Isi struk yang akan dicetak ke printer thermal.
/// Sengaja bebas dari detail transport (ESC/POS) agar bisa diuji sebagai data.
class StrukBaris {
  const StrukBaris({
    required this.nama,
    required this.kuantitas,
    required this.harga,
  });

  final String nama;
  final num kuantitas;
  final double harga;

  double get subtotal => harga * kuantitas;
}

class Struk {
  const Struk({
    required this.namaToko,
    required this.nomor,
    required this.waktu,
    required this.baris,
    required this.total,
    this.alamat,
    this.telepon,
    this.kasir,
    this.metode,
    this.dibayar,
    this.kembalian,
    this.catatanKaki,
    this.barcode,
    this.logoUrl,
  });

  final String namaToko;
  final String? alamat;
  final String? telepon;
  final String nomor;
  final DateTime waktu;
  final String? kasir;
  final List<StrukBaris> baris;
  final double total;
  final String? metode;
  final double? dibayar;
  final double? kembalian;
  final String? catatanKaki;

  /// Isi barcode/QR di kaki struk (mis. nomor nota untuk pelacakan).
  final String? barcode;

  /// URL logo toko untuk kepala struk (null = tanpa logo).
  final String? logoUrl;

  int get jumlahItem =>
      baris.fold<int>(0, (s, b) => s + b.kuantitas.round());
}
