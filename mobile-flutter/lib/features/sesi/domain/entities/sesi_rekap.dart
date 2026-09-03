/// Rekap sesi kasir (dari GET /sesi/aktif atau /sesi/{id}/rekap).
/// Berisi ringkasan kas & penjualan selama sesi berjalan.
class SesiRekap {
  const SesiRekap({
    required this.nomor,
    required this.status,
    required this.kasir,
    required this.waktuBuka,
    required this.waktuTutup,
    required this.kasAwal,
    required this.totalTunai,
    required this.totalTransfer,
    required this.totalQris,
    required this.totalPenjualan,
    required this.jumlahTransaksi,
    required this.kasAkhirSistem,
    required this.kasAkhirFisik,
    required this.selisih,
  });

  final String nomor;
  final String status; // BUKA / TUTUP
  final String kasir;
  final String? waktuBuka;
  final String? waktuTutup;
  final double kasAwal;
  final double totalTunai;
  final double totalTransfer;
  final double totalQris;
  final double totalPenjualan;
  final int jumlahTransaksi;

  /// Kas seharusnya = kas_awal + total_tunai (dihitung server).
  final double kasAkhirSistem;
  final double? kasAkhirFisik;
  final double? selisih;

  bool get isBuka => status.toUpperCase() == 'BUKA';

  factory SesiRekap.fromJson(Map<String, dynamic> m) {
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    double? dn(dynamic v) => v == null ? null : d(v);
    return SesiRekap(
      nomor: (m['nomor'] ?? m['no'] ?? '-').toString(),
      status: (m['status'] ?? '-').toString(),
      kasir: (m['kasir'] ?? '-').toString(),
      waktuBuka: m['waktu_buka']?.toString(),
      waktuTutup: m['waktu_tutup']?.toString(),
      kasAwal: d(m['kas_awal']),
      totalTunai: d(m['total_tunai']),
      totalTransfer: d(m['total_transfer']),
      totalQris: d(m['total_qris']),
      totalPenjualan: d(m['total_penjualan']),
      jumlahTransaksi: (m['jumlah_transaksi'] is num)
          ? (m['jumlah_transaksi'] as num).toInt()
          : int.tryParse('${m['jumlah_transaksi'] ?? ''}') ?? 0,
      kasAkhirSistem: d(m['kas_akhir_sistem']),
      kasAkhirFisik: dn(m['kas_akhir_fisik']),
      selisih: dn(m['selisih']),
    );
  }
}
