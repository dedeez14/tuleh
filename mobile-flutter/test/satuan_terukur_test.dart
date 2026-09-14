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

  test('label kuantitas: satuan hanya ikut pada barang terukur', () {
    expect(labelKuantitas(0.74, 'kg'), '0,74 kg');
    expect(labelKuantitas(1.5, 'Liter'), '1,5 Liter');
    expect(labelKuantitas(2, 'pcs'), '2', reason: 'barang hitungan tanpa satuan');
    expect(labelKuantitas(3, null), '3');
  });

  // Server 2026-09-14 mengirim perilaku jual per produk (mode jual master,
  // satuan terukur, bidang usaha toko) — padanan test JS satuan-terukur.test.js.
  test('perilaku jual dari server menang atas tebakan nama satuan', () {
    final karung = PerilakuJual.dari(
      satuan: 'Karung', modeJual: 'UKUR', desimal: true, bolehNominal: false, langkah: 0.5,
    );
    expect(karung.terukur, isTrue, reason: 'satuan tak dikenal tetap terukur bila server bilang UKUR');
    expect(karung.bolehNominal, isFalse);
    expect(karung.langkah, 0.5);
    expect(karung.bulatkan(1.3), 1.5);
    expect(karung.label(1.5), '1,5 Karung');

    final kgSatuan = PerilakuJual.dari(
      satuan: 'kg', modeJual: 'SATUAN', desimal: false, bolehNominal: false, langkah: 1,
    );
    expect(kgSatuan.terukur, isFalse, reason: 'produk kg yang dipaksa per satuan tidak membuka lembar ukuran');
    expect(kgSatuan.label(2), '2');

    final laundry = PerilakuJual.dari(
      satuan: 'Kg', modeJual: 'UKUR_NOMINAL', desimal: true, bolehNominal: true, langkah: 0.01,
    );
    expect(laundry.bolehNominal, isTrue);
    // Sama dengan server PosModeJualProduk::kuantitasDariNominal: Rp 20.000 @ Rp 7.000/kg → 2,85 kg.
    expect(laundry.dariNominal(20000, 7000), 2.85);
    expect(totalBaris(2.85, 7000), 19950);
  });

  test('produk tanpa mode_jual (server lama) memakai tabel satuan; ekor float tak menjatuhkan satu langkah', () {
    expect(PerilakuJual.dari(satuan: 'kg').terukur, isTrue);
    expect(PerilakuJual.dari(satuan: 'pcs').bolehNominal, isFalse);
    expect(PerilakuJual.dari(satuan: 'kg').bolehNominal, isTrue);
    final ons = PerilakuJual.dari(
      satuan: 'ons', modeJual: 'UKUR_NOMINAL', desimal: true, bolehNominal: true, langkah: 0.1,
    );
    expect(ons.dariNominal(3000, 10000), 0.3, reason: '0.3 / 0.1 = 2.9999999999999996 tetap 3 langkah');
    expect(bulatkanKuantitas(0.3, 'ons', keBawah: true), 0.3);
  });

  test('mode terukur tanpa langkah sah jatuh ke 1; mode SATUAN tak pernah boleh nominal', () {
    final tanpaLangkah = PerilakuJual.dari(satuan: 'Ikat', modeJual: 'UKUR', desimal: true, langkah: 0);
    expect(tanpaLangkah.langkah, 1);
    final aneh = PerilakuJual.dari(satuan: 'Pcs', modeJual: 'SATUAN', desimal: false, bolehNominal: true);
    expect(aneh.bolehNominal, isFalse, reason: 'nominal hanya untuk barang terukur');
    expect(aneh.langkah, 1);
  });
}
