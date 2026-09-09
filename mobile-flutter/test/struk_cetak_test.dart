import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/cetak/data/printer_service.dart';
import 'package:tuleh_pos/features/cetak/data/struk_esc_pos.dart';
import 'package:tuleh_pos/features/cetak/data/struk_teks.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';

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
}
