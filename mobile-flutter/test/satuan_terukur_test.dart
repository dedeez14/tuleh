// Penjualan terukur (per kilo / per nominal). Aturannya harus sama persis
// dengan sisi desktop — lihat PENJUALAN-TERUKUR.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/utils/satuan_terukur.dart';

void main() {
  test('satuan terukur dikenali; yang lain diperlakukan seperti biasa', () {
    for (final s in ['kg', 'Kg', ' KG ', 'liter', 'gram', 'ons', 'meter', 'ml']) {
      expect(apakahTerukur(s), isTrue, reason: s);
    }
    for (final s in ['pcs', 'pack', 'porsi', '', null, 'butir']) {
      expect(apakahTerukur(s), isFalse, reason: '$s');
    }
    expect(langkahSatuan('kg'), 0.01);
    expect(langkahSatuan('pcs'), 1, reason: 'barang hitungan: langkah 1');
  });

  test('pembulatan kuantitas mengikuti langkah satuan', () {
    expect(bulatkanKuantitas(0.744, 'kg'), 0.74);
    expect(bulatkanKuantitas(0.746, 'kg'), 0.75);
    expect(bulatkanKuantitas(2.5, 'ons'), 2.5);
    expect(bulatkanKuantitas(255, 'gram'), 260, reason: 'gram melangkah 10');
    expect(bulatkanKuantitas(0.3, 'kg'), 0.3, reason: 'tanpa ekor floating point');
    expect(bulatkanKuantitas(0, 'kg'), 0);
    expect(bulatkanKuantitas(-2, 'kg'), 0);
  });

  test('nominal → kuantitas dibulatkan KE BAWAH agar tak melebihi uang pelanggan', () {
    // Mangga Rp 27.000/kg, pelanggan minta Rp 20.000.
    final qty = kuantitasDariNominal(20000, 27000, 'kg');
    expect(qty, 0.74);
    expect(totalBaris(qty, 27000), 19980);
    expect(totalBaris(qty, 27000) <= 20000, isTrue);

    expect(kuantitasDariNominal(50000, 25000, 'kg'), 2);
  });

  test('nominal di bawah satu langkah ditolak; minimalnya bisa disebutkan', () {
    expect(kuantitasDariNominal(200, 27000, 'kg'), 0);
    expect(minimalNominal(27000, 'kg'), 270);
    expect(minimalNominal(12500, 'kg'), 125);
  });

  test('harga tak sah tidak pernah membagi nol', () {
    expect(kuantitasDariNominal(20000, 0, 'kg'), 0);
    expect(kuantitasDariNominal(20000, -5, 'kg'), 0);
    expect(kuantitasDariNominal(0, 27000, 'kg'), 0);
  });

  test('uang selalu bulat rupiah', () {
    expect(totalBaris(0.74, 27000), 19980);
    expect(totalBaris(0.333, 10000), 3330);
    expect(totalBaris(1.005, 999), 1004);
  });
}
