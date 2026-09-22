/// Baris dokumen refund (`refunds[].items[]` pada struk / respons POST refund).
class RefundItem {
  const RefundItem({
    required this.nama,
    required this.kuantitas,
    required this.total,
    this.itemId,
    this.satuan,
    this.kembaliStok = true,
  });

  /// Id baris transaksi asal (terenkripsi) — server 2026-09-20; null di server lama.
  final String? itemId;
  final String nama;
  final String? satuan;
  final double kuantitas;
  final double total;
  final bool kembaliStok;
}

/// Dokumen refund bernomor atas satu transaksi (server 2026-09-13).
class Refund {
  const Refund({
    required this.id,
    required this.nomor,
    required this.total,
    this.tanggal,
    this.metode,
    this.metodeNama,
    this.alasan,
    this.oleh,
    this.disetujuiOleh,
    this.subtotal = 0,
    this.totalPajak = 0,
    this.items = const [],
  });

  final String id;
  final String nomor;
  final String? tanggal;
  final String? metode;
  final String? metodeNama;
  final String? alasan;
  final String? oleh;

  /// Nama pemegang hak yang menyetujui lewat PIN (server `disetujui_oleh`);
  /// null bila pelakunya memang berhak sendiri.
  final String? disetujuiOleh;
  final double subtotal;
  final double totalPajak;
  final double total;
  final List<RefundItem> items;
}

/// Satu baris yang diminta refund: id baris struk + jumlah.
class BarisRefund {
  const BarisRefund({required this.id, required this.kuantitas});
  final String id;
  final double kuantitas;
}

/// Permintaan refund dari lembar refund → `POST /transaksi/{id}/refund`.
/// `clientRef` idempoten: pengulangan setelah timeout mengembalikan dokumen yang sama.
class PermintaanRefund {
  const PermintaanRefund({
    required this.baris,
    required this.metode,
    required this.alasan,
    required this.clientRef,
    required this.waktuKlien,
    this.kembaliStok = true,
    this.otorisasiToken,
  });

  final List<BarisRefund> baris;
  final String metode;
  final String alasan;
  final bool kembaliStok;
  final String clientRef;
  final DateTime waktuKlien;

  /// Token persetujuan sekali pakai bila kasir tak punya hak refund sendiri
  /// (§2c). Server MEMBAKARNYA walau refund lalu ditolak — jangan dipakai lagi.
  final String? otorisasiToken;

  Map<String, dynamic> toJson() => {
    'items': [for (final b in baris) {'id': b.id, 'kuantitas': b.kuantitas}],
    'metode': metode,
    'alasan': alasan,
    'kembali_stok': kembaliStok,
    'client_ref': clientRef,
    'waktu_klien': waktuKlien.toIso8601String(),
    if (otorisasiToken != null) 'otorisasi_token': otorisasiToken,
  };
}
