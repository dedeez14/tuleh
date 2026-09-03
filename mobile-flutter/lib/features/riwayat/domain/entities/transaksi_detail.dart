/// Baris item pada detail transaksi.
class TrxItem {
  const TrxItem({
    required this.nama,
    required this.kuantitas,
    required this.harga,
    required this.subtotal,
  });

  final String nama;
  final double kuantitas;
  final double harga;
  final double subtotal;
}

/// Detail transaksi lengkap (`/transaksi/{id}`) — dipakai tampilan struk.
class TransaksiDetail {
  const TransaksiDetail({
    required this.id,
    required this.nomor,
    this.tanggal,
    this.status,
    this.pelanggan,
    this.kasir,
    this.tipePembayaran,
    required this.subtotal,
    required this.totalDiskon,
    required this.totalPajak,
    required this.grandTotal,
    required this.dibayar,
    required this.kembalian,
    required this.items,
  });

  final String id;
  final String nomor;
  final String? tanggal;
  final String? status;
  final String? pelanggan;
  final String? kasir;
  final String? tipePembayaran;
  final double subtotal;
  final double totalDiskon;
  final double totalPajak;
  final double grandTotal;
  final double dibayar;
  final double kembalian;
  final List<TrxItem> items;
}
