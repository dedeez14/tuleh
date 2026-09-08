// Pencarian & penyaring Riwayat (2.19.0) — padanan filter tanggal/status di
// layar Riwayat desktop, tetapi disaring di perangkat agar tetap jalan offline.

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/transaksi.dart';
import 'package:tuleh_pos/features/riwayat/domain/saring_riwayat.dart';

final _kini = DateTime(2026, 9, 8, 15, 0);

Transaksi _trx({
  required String nomor,
  double total = 18500,
  String? status = 'SELESAI',
  String? metode = 'TUNAI',
  DateTime? waktu,
}) => Transaksi(
  id: nomor,
  nomor: nomor,
  grandTotal: total,
  tanggal: (waktu ?? _kini).toIso8601String(),
  status: status,
  metode: metode,
);

void main() {
  final selesai = _trx(nomor: '26-POS-000041');
  final batal = _trx(nomor: '26-POS-000042', status: 'DIBATALKAN', total: 25000);
  final lokal = _trx(nomor: 'L-260908-0001', status: 'BELUM_SINKRON', total: 7000, metode: 'QRIS');
  final kemarin = _trx(nomor: '26-POS-000040', waktu: DateTime(2026, 9, 7, 10));
  final duaMingguLalu = _trx(nomor: '26-POS-000010', waktu: DateTime(2026, 8, 25, 10));
  final duaBulanLalu = _trx(nomor: '26-POS-000001', waktu: DateTime(2026, 7, 1, 10));
  final semua = [selesai, batal, lokal, kemarin, duaMingguLalu, duaBulanLalu];

  List<String> nomor(List<Transaksi> l) => [for (final t in l) t.nomor];

  test('tanpa saringan: daftar utuh dan urutannya tetap', () {
    expect(nomor(saringRiwayat(semua, sekarang: _kini)), nomor(semua));
  });

  group('status', () {
    test('Selesai menyingkirkan yang dibatalkan dan yang belum sinkron', () {
      final r = saringRiwayat(semua, status: SaringStatus.selesai, sekarang: _kini);
      expect(nomor(r), [
        '26-POS-000041',
        '26-POS-000040',
        '26-POS-000010',
        '26-POS-000001',
      ]);
    });

    test('Dibatalkan cocok untuk status BATAL apa pun bentuknya', () {
      final r = saringRiwayat(
        [batal, _trx(nomor: 'X', status: 'batal'), selesai],
        status: SaringStatus.dibatalkan,
        sekarang: _kini,
      );
      expect(nomor(r), ['26-POS-000042', 'X']);
    });

    test('Belum sinkron hanya struk lokal', () {
      final r = saringRiwayat(semua, status: SaringStatus.belumSinkron, sekarang: _kini);
      expect(nomor(r), ['L-260908-0001']);
    });
  });

  group('rentang tanggal', () {
    test('Hari ini: hanya transaksi hari berjalan (sejak pukul 00:00)', () {
      final r = saringRiwayat(semua, rentang: SaringRentang.hariIni, sekarang: _kini);
      expect(nomor(r), ['26-POS-000041', '26-POS-000042', 'L-260908-0001']);
    });

    test('7 hari mencakup kemarin, bukan dua minggu lalu', () {
      final r = saringRiwayat(semua, rentang: SaringRentang.tujuhHari, sekarang: _kini);
      expect(nomor(r), contains('26-POS-000040'));
      expect(nomor(r), isNot(contains('26-POS-000010')));
    });

    test('30 hari mencakup dua minggu lalu, bukan dua bulan lalu', () {
      final r = saringRiwayat(semua, rentang: SaringRentang.tigaPuluhHari, sekarang: _kini);
      expect(nomor(r), contains('26-POS-000010'));
      expect(nomor(r), isNot(contains('26-POS-000001')));
    });

    test('tanggal rusak/kosong tersaring keluar saat rentang dipakai', () {
      final tanpaTanggal = Transaksi(
        id: 'z',
        nomor: 'Z',
        grandTotal: 1000,
        tanggal: null,
        status: 'SELESAI',
        metode: 'TUNAI',
      );
      expect(
        saringRiwayat([tanpaTanggal], rentang: SaringRentang.hariIni, sekarang: _kini),
        isEmpty,
      );
      expect(
        nomor(saringRiwayat([tanpaTanggal], sekarang: _kini)),
        ['Z'],
        reason: 'tanpa rentang tetap tampil',
      );
    });
  });

  group('kata kunci', () {
    test('cocok sebagian nomor, tanpa peduli huruf besar/kecil', () {
      expect(nomor(saringRiwayat(semua, kueri: '000041', sekarang: _kini)), ['26-POS-000041']);
      expect(nomor(saringRiwayat(semua, kueri: 'l-260908', sekarang: _kini)), ['L-260908-0001']);
    });

    test('cocok metode pembayaran', () {
      expect(nomor(saringRiwayat(semua, kueri: 'qris', sekarang: _kini)), ['L-260908-0001']);
    });

    test('nominal dicari sebagai angka: "Rp 25.000" sama dengan "25000"', () {
      expect(nomor(saringRiwayat(semua, kueri: '25000', sekarang: _kini)), ['26-POS-000042']);
      expect(nomor(saringRiwayat(semua, kueri: 'Rp 25.000', sekarang: _kini)), ['26-POS-000042']);
    });

    test('kueri kosong atau spasi tidak menyaring apa pun', () {
      expect(saringRiwayat(semua, kueri: '   ', sekarang: _kini).length, semua.length);
    });

    test('tidak ada yang cocok → daftar kosong', () {
      expect(saringRiwayat(semua, kueri: 'zzz', sekarang: _kini), isEmpty);
    });
  });

  test('gabungan status + rentang + kueri', () {
    final r = saringRiwayat(
      semua,
      status: SaringStatus.selesai,
      rentang: SaringRentang.tujuhHari,
      kueri: 'tunai',
      sekarang: _kini,
    );
    expect(nomor(r), ['26-POS-000041', '26-POS-000040']);
  });
}
