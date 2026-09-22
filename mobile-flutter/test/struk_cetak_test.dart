import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/cetak/data/printer_service.dart';
import 'package:tuleh_pos/features/cetak/data/struk_esc_pos.dart';
import 'package:tuleh_pos/features/cetak/data/struk_teks.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/cetak/domain/struk_server.dart';

/// Penyusun struk thermal. Yang diuji adalah perataan kolom dan isi — bagian
/// yang membuat struk terlihat berantakan di kertas bila salah, dan satu-satunya
/// bagian yang bisa diperiksa tanpa printer sungguhan.

Struk _struk({
  List<StrukBaris> baris = const [
    StrukBaris(nama: 'Kopi Susu', kuantitas: 2, harga: 18000),
  ],
  double total = 36000,
  String? metode = 'TUNAI',
  double? dibayar,
  double? kembalian,
  String? catatanKaki,
  String? barcode,
  String? alamat,
  String? telepon,
}) => Struk(
  namaToko: 'Warung Demo',
  alamat: alamat,
  telepon: telepon,
  nomor: 'TRX/0001',
  waktu: DateTime(2026, 9, 4, 14, 5),
  kasir: 'Kasir Demo',
  baris: baris,
  total: total,
  metode: metode,
  dibayar: dibayar,
  kembalian: kembalian,
  catatanKaki: catatanKaki,
  barcode: barcode,
);

void main() {
  // CapabilityProfile.load() membaca aset paket → butuh binding test.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lebar kolom', () {
    test('58 mm: tiap baris tepat 32 karakter, tidak melebihi kertas', () {
      final teks = const StrukEscPos().pratinjau(_struk());
      for (final b in teks.split('\n')) {
        expect(
          b.length,
          lessThanOrEqualTo(32),
          reason: 'baris melebihi lebar kertas: "$b"',
        );
      }
    });

    test('80 mm: batasnya 48 karakter', () {
      final teks = const StrukEscPos(lebar: PaperSize.mm80).pratinjau(_struk());
      for (final b in teks.split('\n')) {
        expect(b.length, lessThanOrEqualTo(48), reason: 'baris: "$b"');
      }
      // Garis pemisah mengisi penuh lebar kertas.
      expect(teks.split('\n').any((b) => b == '-' * 48), isTrue);
    });

    test('nilai selalu rata kanan pada baris label-nilai', () {
      final teks = const StrukEscPos().pratinjau(
        _struk(total: 1250000, dibayar: 1500000, kembalian: 250000),
      );
      for (final b in teks.split('\n')) {
        if (b.startsWith('TOTAL') || b.startsWith('Kembali')) {
          expect(b.length, 32, reason: 'baris harus penuh 32: "$b"');
          expect(b.endsWith(' '), isFalse, reason: 'nilai rata kanan: "$b"');
        }
      }
    });

    test('label kepanjangan dipotong agar nilai tidak terdorong turun', () {
      final teks = const StrukEscPos().pratinjau(
        _struk(
          baris: const [
            StrukBaris(
              nama: 'Paket Servis Besar Turun Mesin Lengkap Sekali',
              kuantitas: 1,
              harga: 3500000,
            ),
          ],
          total: 3500000,
        ),
      );
      final barisNilai = teks
          .split('\n')
          .where((b) => b.contains('Rp 3.500.000'))
          .toList();
      expect(barisNilai, isNotEmpty);
      for (final b in barisNilai) {
        expect(b.length, lessThanOrEqualTo(32));
      }
    });
  });

  group('isi struk', () {
    test('memuat toko, nomor, kasir, item, dan total', () {
      final teks = const StrukEscPos().pratinjau(
        _struk(alamat: 'Jl. Melati 12', telepon: '0227301234'),
      );
      expect(teks, contains('WARUNG DEMO'));
      expect(teks, contains('Jl. Melati 12'));
      expect(teks, contains('Telp 0227301234'));
      expect(teks, contains('TRX/0001'));
      expect(teks, contains('Kasir Demo'));
      expect(teks, contains('Kopi Susu'));
      expect(teks, contains('2 x Rp 18.000'));
      expect(teks, contains('Rp 36.000'));
      expect(teks, contains('04/09/2026 14:05'));
    });

    test('kuantitas pecahan (layanan kiloan) ditulis dengan koma', () {
      final teks = const StrukEscPos().pratinjau(
        _struk(
          baris: const [
            StrukBaris(nama: 'Cuci Kering Lipat', kuantitas: 4.5, harga: 7000),
          ],
          total: 31500,
        ),
      );
      expect(teks, contains('4,5 x Rp 7.000'));
      expect(teks, contains('Rp 31.500'));
    });

    test('barang timbang: satuan ikut tercetak, bukan angka menggantung', () {
      // "0,74 x 27.000" tidak memberi tahu pelanggan 0,74 dari apa.
      const baris = [
        StrukBaris(nama: 'Mangga Harum Manis', kuantitas: 0.74, harga: 27000, satuan: 'kg'),
      ];
      final teks = const StrukEscPos().pratinjau(_struk(baris: baris, total: 19980));
      expect(teks, contains('0,74 kg x Rp 27.000'));

      final polos = const StrukTeks().bangun(_struk(baris: baris, total: 19980));
      expect(polos, contains('0,74 kg x Rp 27.000'));

      // Barang hitungan tetap tanpa satuan: "2 pcs" tidak menambah apa pun.
      expect(const StrukEscPos().pratinjau(_struk()), contains('2 x Rp 18.000'));
    });

    test('kembalian hanya tampil bila ada; catatan kaki bawaan dipakai', () {
      final tanpa = const StrukEscPos().pratinjau(_struk());
      expect(tanpa, isNot(contains('Kembali')));
      expect(tanpa, contains('Terima kasih'));

      final dengan = const StrukEscPos().pratinjau(
        _struk(dibayar: 50000, kembalian: 14000, catatanKaki: 'Sampai jumpa'),
      );
      expect(dengan, contains('Kembali'));
      expect(dengan, contains('Rp 14.000'));
      expect(dengan, contains('Sampai jumpa'));
      expect(dengan, isNot(contains('Terima kasih')));
    });

    test('bidang kosong tidak meninggalkan baris kosong', () {
      final teks = const StrukEscPos().pratinjau(
        _struk(alamat: '', telepon: '   ', metode: ''),
      );
      expect(teks, isNot(contains('Telp')));
      expect(teks, isNot(contains('Bayar')));
    });
  });

  group('perintah ESC/POS', () {
    test('menghasilkan byte cetak yang tidak kosong & diakhiri potong kertas', () async {
      final bytes = await const StrukEscPos().bangun(_struk(barcode: 'TRX/0001'));
      expect(bytes, isNotEmpty);
      // ESC (0x1B) selalu muncul: inisialisasi & pengaturan gaya.
      expect(bytes.contains(0x1B), isTrue);
      // GS (0x1D) dipakai perintah potong kertas & QR.
      expect(bytes.contains(0x1D), isTrue);
    });

    test('struk 80 mm menghasilkan byte berbeda dari 58 mm', () async {
      final a = await const StrukEscPos().bangun(_struk());
      final b = await const StrukEscPos(lebar: PaperSize.mm80).bangun(_struk());
      expect(a.length, isNot(b.length));
    });

    test('struk uji bawaan lengkap & siap dipakai menguji printer', () async {
      final uji = PrinterService.strukUji(namaToko: 'Toko Saya');
      expect(uji.namaToko, 'Toko Saya');
      expect(uji.baris.length, 3);
      expect(uji.total, 174980);
      expect(uji.kembalian, 25020);
      expect(uji.jumlahItem, 4, reason: '2 + 1 + baris timbang dihitung satu');

      final bytes = await const StrukEscPos().bangun(uji);
      expect(bytes, isNotEmpty);

      final teks = const StrukEscPos().pratinjau(uji);
      expect(teks, contains('TOKO SAYA'));
      expect(teks, contains('Uji cetak berhasil'));
      for (final b in teks.split('\n')) {
        expect(b.length, lessThanOrEqualTo(32));
      }
    });
  });

  group('nota refund', () {
    final nota = Struk(
      namaToko: 'Warung Demo',
      nomor: 'RF-000003',
      waktu: DateTime(2026, 9, 20, 10, 15),
      kasir: 'Manager Toko',
      baris: const [StrukBaris(nama: 'Kopi Susu', kuantitas: 1, harga: 18000)],
      total: 18000,
      metode: 'TUNAI',
      judul: 'NOTA REFUND',
      rujukan: 'TRX/0001',
      alasan: 'Rasa tidak sesuai pesanan pelanggan',
      labelTotal: 'TOTAL REFUND',
      catatanKaki: 'Dana telah dikembalikan',
      barcode: 'RF-000003',
    );

    test('teks & pratinjau ESC/POS: judul, transaksi asal, Oleh, TOTAL REFUND, alasan; ≤32 kolom; tanpa Tunai/Kembali', () {
      for (final teks in [const StrukTeks().bangun(nota), const StrukEscPos().pratinjau(nota)]) {
        for (final b in teks.split('\n')) {
          expect(b.length, lessThanOrEqualTo(32), reason: 'baris: "$b"');
        }
        expect(teks, contains('NOTA REFUND'));
        expect(teks, contains('RF-000003'));
        expect(teks, contains('TRX/0001'));
        expect(teks, contains('Oleh'));
        expect(teks, contains('TOTAL REFUND'));
        expect(teks, contains('Dikembalikan via'));
        expect(teks, contains('Alasan: Rasa tidak sesuai'));
        expect(teks, contains('Dana telah dikembalikan'));
        expect(teks, isNot(contains('Tunai ')));
        expect(teks, isNot(contains('Kembali ')));
      }
    });

    test('struk biasa tidak berubah: label TOTAL, Kasir, tanpa Alasan', () {
      final teks = const StrukTeks().bangun(_struk(dibayar: 50000, kembalian: 14000));
      expect(teks, contains('TOTAL'));
      expect(teks, isNot(contains('TOTAL REFUND')));
      expect(teks, contains('Kasir'));
      expect(teks, isNot(contains('Alasan')));
    });

    test('toJson/fromJson mempertahankan judul, rujukan, alasan, labelTotal', () {
      final ulang = Struk.fromJson(nota.toJson());
      expect(ulang.judul, 'NOTA REFUND');
      expect(ulang.rujukan, 'TRX/0001');
      expect(ulang.alasan, nota.alasan);
      expect(ulang.labelTotal, 'TOTAL REFUND');
      expect(Struk.fromJson(_struk().toJson()).labelTotal, 'TOTAL');
    });
  });

  group('uang muka (Fase 3)', () {
    Struk dasar({
      double? uangMuka,
      double? sisa,
      String labelSisa = 'Sisa',
      String? metode,
    }) => Struk(
      namaToko: 'Tuléh Laundry',
      nomor: 'ORD/0001',
      waktu: DateTime(2026, 9, 22, 10),
      total: 28000,
      baris: const [StrukBaris(nama: 'Cuci Kering', kuantitas: 1, harga: 28000)],
      metode: metode,
      uangMuka: uangMuka,
      sisa: sisa,
      labelSisa: labelSisa,
    );

    test('nota DP mencetak Uang muka & Sisa, ≤ 32 kolom, di teks dan ESC/POS', () {
      final s = dasar(uangMuka: 10000, sisa: 18000, metode: 'TUNAI');
      for (final teks in [const StrukTeks().bangun(s), const StrukEscPos().pratinjau(s)]) {
        expect(teks, contains('Uang muka'));
        expect(teks, contains('Sisa'));
        expect(teks, contains('18.000'));
        for (final baris in teks.split('\n')) {
          expect(baris.length, lessThanOrEqualTo(32), reason: baris);
        }
      }
    });

    test('struk lama tanpa uang muka tidak berubah', () {
      final s = dasar(metode: 'TUNAI');
      expect(const StrukTeks().bangun(s), isNot(contains('Uang muka')));
      expect(const StrukTeks().bangun(s), isNot(contains('Sisa')));
    });

    test('JSON bolak-balik menyimpan uangMuka, sisa, labelSisa', () {
      final s = dasar(uangMuka: 10000, sisa: 18000, labelSisa: 'Dibayar saat serah');
      final k = Struk.fromJson(s.toJson());
      expect(k.uangMuka, 10000);
      expect(k.sisa, 18000);
      expect(k.labelSisa, 'Dibayar saat serah');
      final salin = s.salinDengan(nomor: 'ORD/0002');
      expect(salin.uangMuka, 10000);
      expect(salin.sisa, 18000);
      expect(salin.labelSisa, 'Dibayar saat serah');
    });

    test('nomor antrian dicetak di bawah nomor nota (teks & ESC/POS)', () {
      // Untuk laundry/bengkel inilah alasan utama nota dicetak: pelanggan
      // menyebut nomor antriannya saat mengambil barang.
      final s = Struk(
        namaToko: 'Tuléh Laundry',
        nomor: 'ORD/0001',
        noAntrian: 'B-003',
        waktu: DateTime(2026, 9, 22, 10),
        total: 28000,
        baris: const [StrukBaris(nama: 'Cuci Kering', kuantitas: 1, harga: 28000)],
        uangMuka: 10000,
        sisa: 18000,
      );
      for (final teks in [const StrukTeks().bangun(s), const StrukEscPos().pratinjau(s)]) {
        final baris = teks.split('\n');
        final iNomor = baris.indexWhere((b) => b.contains('ORD/0001'));
        final iAntrian = baris.indexWhere((b) => b.contains('No. antrian'));
        expect(iNomor, greaterThanOrEqualTo(0));
        expect(iAntrian, iNomor + 1, reason: 'tepat di bawah nomor nota');
        expect(baris[iAntrian], contains('B-003'));
        for (final b in baris) {
          expect(b.length, lessThanOrEqualTo(32), reason: b);
        }
      }
      // Tanpa nomor antrian (minimarket) tak ada baris tambahan.
      expect(
        const StrukTeks().bangun(dasar(uangMuka: 10000, sisa: 18000)),
        isNot(contains('No. antrian')),
      );
      final k = Struk.fromJson(s.toJson());
      expect(k.noAntrian, 'B-003');
      expect(s.salinDengan(nomor: 'ORD/0002').noAntrian, 'B-003');
    });

    test('label uang muka membawa metode nota, baris "Bayar" tak ikut tercetak', () {
      final s = Struk(
        namaToko: 'Tuléh Laundry',
        nomor: 'ORD/0001',
        waktu: DateTime(2026, 9, 22, 10),
        total: 28000,
        baris: const [StrukBaris(nama: 'Cuci Kering', kuantitas: 1, harga: 28000)],
        uangMuka: 10000,
        sisa: 18000,
        labelUangMuka: 'Uang muka (QRIS)',
      );
      for (final teks in [const StrukTeks().bangun(s), const StrukEscPos().pratinjau(s)]) {
        expect(teks, contains('Uang muka (QRIS)'));
        expect(teks, isNot(contains('Bayar ')));
      }
      expect(Struk.fromJson(s.toJson()).labelUangMuka, 'Uang muka (QRIS)');
      expect(s.salinDengan(nomor: 'X').labelUangMuka, 'Uang muka (QRIS)');
    });

    test('strukDariServer melengkapi QR kaki, diskon, nomor antrian & baris per nominal', () {
      final s = strukDariServer({
        'nomor': 'ORD/9',
        'no_antrian': 'B-007',
        'tanggal': '2026-09-22T10:00:00+07:00',
        'status': 'BELUM LUNAS',
        'subtotal': 30000,
        'total_diskon': 2000,
        'grand_total': 28000,
        'sisa': 28000,
        'items': [
          {'nama': null, 'kuantitas': 1, 'harga': 28000, 'nominal_diminta': 20000},
        ],
      }, namaToko: 'T');
      expect(s.barcode, 'ORD/9', reason: 'QR kaki struk memakai nomor nota');
      expect(s.noAntrian, 'B-007');
      expect(s.diskon, 2000);
      expect(s.baris.single.nama, '-', reason: 'nama kosong tidak jadi "null"');
      expect(s.baris.single.nominalDiminta, 20000);
    });

    test('strukDariServer menjepit sisa negatif & membaca metode huruf kecil', () {
      final s = strukDariServer({
        'nomor': 'POS-9',
        'tanggal': '2026-09-22T12:00:00+07:00',
        'status': 'SELESAI',
        'tipe_pembayaran': 'tunai',
        'grand_total': 28000,
        'dibayar': 30000,
        'kembalian': 2000,
        'items': const [],
      }, namaToko: 'T');
      expect(s.dibayar, 30000, reason: 'metode huruf kecil tetap dikenali TUNAI');

      final aneh = strukDariServer({
        'nomor': 'POS-10',
        'tanggal': '2026-09-22T12:00:00+07:00',
        'status': 'SELESAI',
        'grand_total': 10000,
        'uang_muka': 15000, // data melenceng: DP > grand_total
        'items': const [],
      }, namaToko: 'T');
      expect(aneh.sisa, 0, reason: 'tak pernah negatif');
    });

    test('strukDariServer: nota bayar nanti / uang muka / pelunasan ber-DP / transaksi biasa', () {
      final item = [
        {'nama': 'Cuci Kering', 'kuantitas': 1, 'harga': 28000, 'subtotal': 28000},
      ];
      final nanti = strukDariServer({
        'nomor': 'ORD/1',
        'tanggal': '2026-09-22T10:00:00+07:00',
        'status': 'BELUM LUNAS',
        'tipe_pembayaran': 'BAYAR SAAT AMBIL',
        'grand_total': 28000,
        'dibayar': 0,
        'kembalian': 0,
        'uang_muka': 0,
        'sisa': 28000,
        'items': item,
      }, namaToko: 'T');
      expect(nanti.metode, isNull);
      expect(nanti.uangMuka, isNull);
      expect(nanti.sisa, 28000);
      expect(nanti.dibayar, isNull);

      final dp = strukDariServer({
        'nomor': 'ORD/2',
        'tanggal': '2026-09-22T10:00:00+07:00',
        'status': 'UANG MUKA',
        'tipe_pembayaran': 'QRIS',
        'grand_total': 28000,
        'dibayar': 10000,
        'kembalian': 0,
        'uang_muka': 10000,
        'sisa': 18000,
        'items': item,
      }, namaToko: 'T');
      // Nota UANG MUKA tak boleh mencetak baris "Bayar QRIS" (terbaca seolah
      // lunas); metodenya menempel pada label uang muka, sama dengan desktop.
      expect(dp.metode, isNull);
      expect(dp.labelUangMuka, 'Uang muka (QRIS)');
      expect(dp.uangMuka, 10000);
      expect(dp.sisa, 18000);
      expect(dp.labelSisa, 'Sisa');

      final akhir = strukDariServer({
        'nomor': 'POS-1',
        'tanggal': '2026-09-22T12:00:00+07:00',
        'status': 'SELESAI',
        'tipe_pembayaran': 'TUNAI',
        'grand_total': 28000,
        'dibayar': 28000,
        'kembalian': 0,
        'uang_muka': 10000,
        'items': item,
      }, namaToko: 'T');
      expect(akhir.uangMuka, 10000);
      expect(akhir.sisa, 18000);
      expect(akhir.labelSisa, 'Dibayar saat serah');
      expect(akhir.dibayar, isNull, reason: 'tak ada baris "Tunai" ganda');

      final biasa = strukDariServer({
        'nomor': 'POS-2',
        'tanggal': '2026-09-22T12:00:00+07:00',
        'status': 'SELESAI',
        'tipe_pembayaran': 'TUNAI',
        'grand_total': 28000,
        'dibayar': 30000,
        'kembalian': 2000,
        'items': item,
      }, namaToko: 'T');
      expect(biasa.uangMuka, isNull);
      expect(biasa.dibayar, 30000);
      expect(biasa.kembalian, 2000);
    });

    test('strukDariServer: nominal berupa teks desimal dibaca sebagai angka', () {
      final s = strukDariServer({
        'nomor': 'POS-3',
        'tanggal': '2026-09-22T12:00:00+07:00',
        'status': 'SELESAI',
        'tipe_pembayaran': 'QRIS',
        'grand_total': '28000.00',
        'uang_muka': '10000.00',
        'items': [
          {'nama': 'Cuci Kering', 'kuantitas': '1', 'harga': '28000.00'},
        ],
      }, namaToko: 'T');
      expect(s.total, 28000);
      expect(s.uangMuka, 10000);
      expect(s.sisa, 18000);
      expect(s.kembalian, isNull);
      expect(s.baris.single.harga, 28000);
    });
  });
}
