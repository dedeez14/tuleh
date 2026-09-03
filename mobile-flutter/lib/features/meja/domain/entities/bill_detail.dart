/// Item pada bon (agregat lintas ronde).
class BillItem {
  const BillItem({
    required this.nama,
    required this.kuantitas,
    this.harga,
    required this.subtotal,
  });

  final String nama;
  final double kuantitas;
  final double? harga;
  final double subtotal;
}

/// Detail bon meja (GET /bills/{id}).
class BillDetail {
  const BillDetail({
    required this.id,
    required this.nomor,
    this.label,
    this.pax,
    this.status,
    required this.total,
    required this.items,
  });

  final String id;
  final String nomor;
  final String? label;
  final int? pax;
  final String? status;
  final double total;
  final List<BillItem> items;
}
