/// Pesanan hidup (order) di papan KDS / Papan Proses / Antrian —
/// bentuk `GET /orders` MOVERA (sama dengan Mode Demo desktop).
class PesananItem {
  const PesananItem({required this.nama, required this.kuantitas, this.catatan});

  final String nama;
  final num kuantitas;
  final String? catatan;
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

  /// 'LUNAS' | 'BELUM' — nota bayar-saat-ambil / order QR meja belum dibayar.
  final String? bayar;
  final String? pelanggan;
  final num total;
  final DateTime? createdAt;
  final List<PesananItem> items;

  bool get belumBayar => (bayar ?? '').toUpperCase() == 'BELUM';
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
    return Pesanan(
      id: (m['id'] ?? '').toString(),
      stage: (m['stage'] ?? m['status_tahap'] ?? '').toString(),
      nomor: m['nomor']?.toString(),
      noAntrian: m['no_antrian']?.toString(),
      meja: m['meja']?.toString(),
      ronde: ronde == null ? null : int.tryParse('$ronde'),
      bayar: m['bayar']?.toString(),
      pelanggan: m['pelanggan']?.toString(),
      total: _num(m['total']) ?? 0,
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()),
      items: items,
    );
  }

  static num? _num(dynamic v) => v is num ? v : num.tryParse('$v');
}
