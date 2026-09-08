// Pemindai barcode kasir (2.23.1): dua keluhan nyata dari lapangan —
// (1) item masuk berulang saat ponsel ditahan di depan satu barcode, dan
// (2) barcode di luar kotak bidik ikut terbaca.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/widgets/pindai_barcode.dart';

bool _boleh(String kode, DateTime kini, Map<String, DateTime> terlihat) =>
    bolehDiprosesBarcode(kode: kode, kini: kini, terlihat: terlihat);

void main() {
  group('anti-ganda: barcode harus hilang dulu', () {
    test('ditahan terus di depan kamera hanya masuk sekali', () {
      final terlihat = <String, DateTime>{};
      var t = DateTime(2026, 9, 9, 10, 0, 0);
      var diterima = 0;

      // 5 detik menahan barcode: kamera mengirim frame tiap ~33 ms.
      for (var i = 0; i < 150; i++) {
        if (_boleh('899000111', t, terlihat)) diterima++;
        t = t.add(const Duration(milliseconds: 33));
      }
      expect(diterima, 1, reason: 'dulu bertambah tiap 1,5 detik');
    });

    test('menjauh lalu memindai lagi menambah item baru', () {
      final terlihat = <String, DateTime>{};
      final t0 = DateTime(2026, 9, 9, 10, 0, 0);
      expect(_boleh('899000111', t0, terlihat), isTrue);

      // Masih terlihat 1 detik kemudian → belum boleh.
      expect(_boleh('899000111', t0.add(const Duration(seconds: 1)), terlihat), isFalse);

      // Barcode diangkat; 1,3 detik tanpa terlihat, lalu dipindai lagi.
      expect(
        _boleh('899000111', t0.add(const Duration(milliseconds: 2400)), terlihat),
        isTrue,
        reason: 'kasir memang memindai item kedua yang sama',
      );
    });

    test('barcode berbeda tidak saling menghalangi', () {
      final terlihat = <String, DateTime>{};
      final t = DateTime(2026, 9, 9, 10, 0, 0);
      expect(_boleh('AAA', t, terlihat), isTrue);
      expect(_boleh('BBB', t.add(const Duration(milliseconds: 100)), terlihat), isTrue);
      expect(_boleh('AAA', t.add(const Duration(milliseconds: 200)), terlihat), isFalse);
    });

    test('catatan lama dibuang supaya tidak menumpuk', () {
      final terlihat = <String, DateTime>{};
      var t = DateTime(2026, 9, 9, 10, 0, 0);
      for (var i = 0; i < 70; i++) {
        _boleh('kode-$i', t, terlihat);
        t = t.add(const Duration(seconds: 3));
      }
      expect(terlihat.length, lessThan(70));
    });
  });

  group('kotak bidik = jendela pemindaian', () {
    test('persegi di tengah layar, tidak melebihi 300 dp', () {
      final r = kotakBidikBarcode(const Size(400, 800));
      expect(r.center, const Offset(200, 400));
      expect(r.width, closeTo(312 > 300 ? 300 : 312, 0.01));
      expect(r.height, closeTo(r.width * 0.62, 0.01));

      // Layar sempit: ikut menyempit, tidak menempel tepi.
      final sempit = kotakBidikBarcode(const Size(320, 640));
      expect(sempit.width, closeTo(320 * 0.78, 0.01));
      expect(sempit.left, greaterThan(0));
      expect(sempit.right, lessThan(320));
    });
  });
}
