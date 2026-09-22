/// Pesanan hidup (order) di papan KDS / Papan Proses / Antrian —
/// bentuk `GET /orders` MOVERA (sama dengan Mode Demo desktop).
class PesananItem {
  const PesananItem({required this.nama, required this.kuantitas, this.catatan});

  final String nama;
  final num kuantitas;
  final String? catatan;
}

/// Satu uang masuk pesanan (Fase 3): DP saat pesan, PELUNASAN saat serah.
class PembayaranPesanan {
  const PembayaranPesanan({required this.jenis, required this.jumlah, this.tipePembayaran, this.waktu, this.kasir});

  final String jenis;
  final num jumlah;
  final String? tipePembayaran;
  final DateTime? waktu;
  final String? kasir;

  factory PembayaranPesanan.fromJson(Map<String, dynamic> m) => PembayaranPesanan(
        jenis: (m['jenis'] ?? '').toString(),
        jumlah: Pesanan._num(m['jumlah']) ?? 0,
        tipePembayaran: m['tipe_pembayaran']?.toString(),
        waktu: DateTime.tryParse((m['waktu'] ?? '').toString()),
        kasir: m['kasir']?.toString(),
      );
}

class Pesanan {
  const Pesanan({
    required this.id,
    required this.stage,
    this.nomor,
    this.noAntrian,
    this.meja,
    this.ronde,
    this.bayar,
    this.pelanggan,
    this.total = 0,
    this.dibayar = 0,
    this.sisa = 0,
    this.pembayaran = const [],
    this.createdAt,
    this.items = const [],
  });

  final String id;
  final String stage;
  final String? nomor;
  final String? noAntrian;

  /// Label meja untuk tiket bon dine-in (identitasnya meja, bukan nomor antrian).
  final String? meja;
  final int? ronde;

  /// 'LUNAS' | 'BELUM' | 'DP' | 'BON' — nota bayar-saat-ambil, uang muka,
  /// bon meja, atau order QR meja yang belum dibayar.
  final String? bayar;
  final String? pelanggan;
  final num total;

  /// Uang yang sudah masuk (DP + pelunasan) dan tagihan yang tersisa.
  final num dibayar;
  final num sisa;
  final List<PembayaranPesanan> pembayaran;
  final DateTime? createdAt;
  final List<PesananItem> items;

  bool get belumBayar => (bayar ?? '').toUpperCase() == 'BELUM';

  bool get adalahDp => (bayar ?? '').toUpperCase() == 'DP';

  /// Masih punya tagihan (tombol Lunasi): nota bayar-nanti & uang muka. BON dilunasi lewat bill.
  bool get perluDilunasi => belumBayar || adalahDp;
  bool get menungguBayar => stage == 'MENUNGGU_BAYAR';
  bool get dariMeja => meja != null && meja!.isNotEmpty;

  /// Identitas yang ditampilkan besar di kartu: meja, nomor antrian, atau nomor order.
  String get label => dariMeja ? meja! : (noAntrian ?? nomor ?? '');

  factory Pesanan.fromJson(Map<String, dynamic> m) {
    final rawItems = m['items'];
    final items = <PesananItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(
            PesananItem(
              nama: (e['nama'] ?? e['name'] ?? '').toString(),
              kuantitas: _num(e['kuantitas'] ?? e['qty']) ?? 0,
              catatan: e['catatan']?.toString(),
            ),
          );
        }
      }
    }
    final ronde = m['ronde'];
    final rawBayar = m['pembayaran'];
    final pembayaran = <PembayaranPesanan>[
      if (rawBayar is List)
        for (final e in rawBayar)
          if (e is Map) PembayaranPesanan.fromJson(Map<String, dynamic>.from(e)),
    ];
    final bayar = m['bayar']?.toString();
    final total = _num(m['total']) ?? 0;
    // Server lama tanpa `sisa`: nota BELUM = seluruh total; lainnya nol.
    final sisa = _num(m['sisa']) ?? ((bayar ?? '').toUpperCase() == 'BELUM' ? total : 0);
    return Pesanan(
      id: (m['id'] ?? '').toString(),
      stage: (m['stage'] ?? m['status_tahap'] ?? '').toString(),
      nomor: m['nomor']?.toString(),
      noAntrian: m['no_antrian']?.toString(),
      meja: m['meja']?.toString(),
      ronde: ronde == null ? null : int.tryParse('$ronde'),
      bayar: bayar,
      pelanggan: m['pelanggan']?.toString(),
      total: total,
      dibayar: _num(m['dibayar']) ?? 0,
      sisa: sisa,
      pembayaran: pembayaran,
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
      items: items,
    );
  }

  static num? _num(dynamic v) => v is num ? v : num.tryParse('$v');
}
