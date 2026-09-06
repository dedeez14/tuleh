import '../storage/secure_storage.dart';

/// Nomor struk sementara untuk transaksi offline: `L-yyMMdd-0007`, naik per
/// perangkat per hari. Nomor resmi dari server diisi setelah sinkron.
class NomorLokal {
  NomorLokal(this._storage);
  final SecureStorage _storage;

  static String _tanggal(DateTime t) {
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${dua(t.year % 100)}${dua(t.month)}${dua(t.day)}';
  }

  Future<String> berikutnya({DateTime? sekarang}) async {
    final t = (sekarang ?? DateTime.now()).toLocal();
    final tgl = _tanggal(t);
    final kunci = 'nomor_lokal_$tgl';
    final n = (int.tryParse(await _storage.bacaNilai(kunci) ?? '') ?? 0) + 1;
    await _storage.tulisNilai(kunci, '$n');
    return 'L-$tgl-${n.toString().padLeft(4, '0')}';
  }
}
