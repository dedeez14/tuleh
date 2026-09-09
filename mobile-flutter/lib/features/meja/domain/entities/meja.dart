/// Meja (untuk dine-in / open bill). `billId != null` = sedang terisi.
class Meja {
  const Meja({
    required this.id,
    required this.nomor,
    this.kode,
    this.billId,
    this.billTotal,
    this.pax,
    this.aktif = true,
  });

  final String id;
  final String nomor;
  final String? kode;
  final String? billId;
  final double? billTotal;
  final int? pax;

  /// false = meja dinonaktifkan (server soft-delete). Hanya tampil di layar
  /// Kelola Meja; peta kasir menyembunyikannya.
  final bool aktif;

  bool get terisi => billId != null && billId!.isNotEmpty;
}
