import '../storage/secure_storage.dart';
import 'perangkat_sinkron.dart';

/// Nomor struk sementara untuk transaksi offline: `L-yyMMdd-0007`, naik per
/// perangkat per hari. Nomor resmi dari server diisi setelah sinkron.
///
/// [awalanPerangkat] (Fase 4) = beri awalan 4 karakter id perangkat sinkron:
/// `L-3B9D-260924-0007`. Hitungan harian direset per perangkat, jadi tanpa
/// awalan dua perangkat (atau pasang ulang) di hari yang sama menghasilkan
/// nomor kembar dan pencarian `GET /transaksi?q=L-…` ambigu.
class NomorLokal {
  NomorLokal(this._storage, {this.awalanPerangkat = false});
  final SecureStorage _storage;
  final bool awalanPerangkat;

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
    final urut = n.toString().padLeft(4, '0');
    if (!awalanPerangkat) return 'L-$tgl-$urut';
    final awalan = awalanDariIdPerangkat(await idPerangkatSinkron(_storage));
    return awalan.isEmpty ? 'L-$tgl-$urut' : 'L-$awalan-$tgl-$urut';
  }
}
