import 'refund.dart';

/// Baris item pada detail transaksi.
class TrxItem {
  const TrxItem({
    required this.nama,
    required this.kuantitas,
    required this.harga,
    required this.subtotal,
    this.satuan,
    this.nominalDiminta,
    this.id,
    this.qtyRefund = 0,
    this.qtyBisaRefund = 0,
  });

  final String nama;
  final double kuantitas;
  final double harga;
  final double subtotal;

  /// Satuan dari server — cetak ulang struk lama tetap menyebut "0,74 Kg".
  final String? satuan;

  /// Rupiah yang diminta pelanggan pada baris per nominal (server
  /// 2026-09-14: `nominal_diminta`); null untuk baris biasa / server lama.
  final double? nominalDiminta;

  /// Id baris (terenkripsi) untuk refund per item; null di server lama / struk lokal.
  final String? id;

  /// Jumlah yang sudah direfund dan sisa yang masih bisa direfund (server 2026-09-13).
  final double qtyRefund;
  final double qtyBisaRefund;
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
    this.totalRefund = 0,
    this.nilaiBersih,
    this.refunds = const [],
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

  /// Total dana yang sudah dikembalikan & nilai bersih (grand_total − refund); null bila server lama.
  final double totalRefund;
  final double? nilaiBersih;
  final List<Refund> refunds;

  bool get adaSisaRefund => items.any((i) => i.qtyBisaRefund > 0);
}
