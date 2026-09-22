import 'pesanan.dart';

/// Baris keranjang untuk nota bayar-nanti/uang muka. Server menghitung total dari harga katalog; `harga` di sini
/// hanya untuk menghitung batas uang muka di layar (sama dengan hitungan server).
class ItemNota {
  const ItemNota({required this.idProduk, required this.kuantitas, required this.harga});

  final String idProduk;
  final num kuantitas;
  final num harga;
}

/// Hasil `POST /orders`: pesanan + nota siap cetak (bentuk struk server).
class NotaPesanan {
  const NotaPesanan({required this.pesanan, required this.nota});

  final Pesanan pesanan;
  final Map<String, dynamic> nota;
}

/// Hasil transisi: pesanan terbaru + struk transaksi akhir bila transisi itu melunasi.
class HasilTransisi {
  const HasilTransisi({required this.pesanan, this.struk});

  final Pesanan pesanan;
  final Map<String, dynamic>? struk;
}
