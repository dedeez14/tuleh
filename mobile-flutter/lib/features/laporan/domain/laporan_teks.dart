import '../../../core/utils/format.dart';
import '../../sesi/domain/entities/sesi_rekap.dart';
import 'entities/laporan_keuangan.dart';
import 'entities/penjualan_hari.dart';

/// Ringkasan laporan sebagai teks siap kirim (WhatsApp/catatan).
///
/// Padanan `ringkasTeks()` di desktop: judul tebal ala WhatsApp (`*…*`),
/// angka dalam rupiah, lalu omzet harian dan rekap kasir bila ada. Fungsi
/// murni — tidak menyentuh jaringan atau widget, jadi mudah diuji.
String laporanTeks({
  required String namaToko,
  required LaporanKeuangan keuangan,
  List<PenjualanHari> harian = const [],
  List<SesiRekap> rekap = const [],
  int maksHari = 8,
  int maksSesi = 3,
}) {
  final b = StringBuffer()
    ..writeln('*Laporan $namaToko*')
    ..writeln('Periode: ${keuangan.bulan}')
    ..writeln()
    ..writeln('Omzet: ${fmtIDR(keuangan.omset)}')
    ..writeln('Transaksi: ${fmtQty(keuangan.jumlahTransaksi)}')
    ..writeln('Pengeluaran: ${fmtIDR(keuangan.pengeluaran)}')
    ..writeln('Laba: ${fmtIDR(keuangan.laba)}');

  final rata = keuangan.jumlahTransaksi > 0
      ? keuangan.omset / keuangan.jumlahTransaksi
      : 0.0;
  if (rata > 0) b.writeln('Rata-rata per transaksi: ${fmtIDR(rata)}');

  final hari = harian.length > maksHari
      ? harian.sublist(harian.length - maksHari)
      : harian;
  if (hari.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*Omzet harian*');
    for (final h in hari) {
      b.writeln(
        '${fmtTanggalPendek(h.tanggal)}: ${fmtIDR(h.totalOmzet)}'
        ' (${fmtQty(h.jumlahTransaksi)} trx)',
      );
    }
  }

  final sesi = rekap.take(maksSesi).toList();
  if (sesi.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*Rekap kasir*');
    for (final s in sesi) {
      final d = s.selisih; // null = kas fisik belum dihitung
      final kas = d == null
          ? ''
          : d == 0
          ? ' · kas pas'
          : ' · kas ${d > 0 ? 'lebih' : 'kurang'} ${fmtIDR(d.abs())}';
      final tutup = s.status.toUpperCase() == 'TUTUP';
      b.writeln(
        '${s.nomor} · ${s.kasir}: ${fmtIDR(s.totalPenjualan)}'
        '${tutup ? kas : ' · masih buka'}',
      );
    }
  }

  b
    ..writeln()
    ..write('_via aplikasi Tuléh_');
  return b.toString();
}
