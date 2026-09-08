// Ringkasan laporan sebagai teks siap kirim (2.18.0) — padanan ringkasTeks()
// di desktop.

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/laporan/domain/entities/laporan_keuangan.dart';
import 'package:tuleh_pos/features/laporan/domain/entities/penjualan_hari.dart';
import 'package:tuleh_pos/features/laporan/domain/laporan_teks.dart';
import 'package:tuleh_pos/features/sesi/domain/entities/sesi_rekap.dart';

const _keuangan = LaporanKeuangan(
  bulan: 'September 2026',
  omset: 12500000,
  jumlahTransaksi: 250,
  pengeluaran: 2500000,
  laba: 10000000,
);

SesiRekap _sesi({
  String nomor = 'SK-00008',
  String status = 'TUTUP',
  double? selisih = 0,
}) => SesiRekap(
  nomor: nomor,
  status: status,
  kasir: 'Kasir Demo',
  waktuBuka: '2026-09-08T08:00:00+07:00',
  waktuTutup: '2026-09-08T21:00:00+07:00',
  kasAwal: 200000,
  totalTunai: 500000,
  totalTransfer: 0,
  totalQris: 250000,
  totalPenjualan: 750000,
  jumlahTransaksi: 20,
  kasAkhirSistem: 700000,
  kasAkhirFisik: selisih == null ? null : 700000 + selisih,
  selisih: selisih,
);

void main() {
  test('ringkasan memuat judul, angka utama, dan rata-rata per transaksi', () {
    final teks = laporanTeks(namaToko: 'Minimarket Demo', keuangan: _keuangan);
    expect(teks, startsWith('*Laporan Minimarket Demo*'));
    expect(teks, contains('Periode: September 2026'));
    expect(teks, contains('Omzet: ${'Rp 12.500.000'}'));
    expect(teks, contains('Transaksi: 250'));
    expect(teks, contains('Pengeluaran: Rp 2.500.000'));
    expect(teks, contains('Laba: Rp 10.000.000'));
    expect(teks, contains('Rata-rata per transaksi: Rp 50.000'));
    expect(teks, endsWith('_via aplikasi Tuléh_'));
    // Tanpa data harian/rekap, bagiannya tidak dicetak.
    expect(teks, isNot(contains('Omzet harian')));
    expect(teks, isNot(contains('Rekap kasir')));
  });

  test('tanpa transaksi: baris rata-rata dilewati (tidak ada bagi nol)', () {
    final teks = laporanTeks(
      namaToko: 'Toko Sepi',
      keuangan: const LaporanKeuangan(
        bulan: 'September 2026',
        omset: 0,
        jumlahTransaksi: 0,
        pengeluaran: 0,
        laba: 0,
      ),
    );
    expect(teks, contains('Transaksi: 0'));
    expect(teks, isNot(contains('Rata-rata')));
  });

  test('omzet harian dipotong ke hari terakhir sesuai maksHari', () {
    final harian = [
      for (var i = 1; i <= 12; i++)
        PenjualanHari(
          tanggal: '2026-09-${i.toString().padLeft(2, '0')}T00:00:00+07:00',
          jumlahTransaksi: i,
          totalOmzet: i * 100000,
        ),
    ];
    final teks = laporanTeks(
      namaToko: 'X',
      keuangan: _keuangan,
      harian: harian,
      maksHari: 3,
    );
    expect(teks, contains('*Omzet harian*'));
    expect(teks, contains('10 Sep: Rp 1.000.000 (10 trx)'));
    expect(teks, contains('12 Sep: Rp 1.200.000 (12 trx)'));
    expect(teks, isNot(contains('9 Sep')), reason: 'hanya 3 hari terakhir');
  });

  test('rekap kasir: kas pas / lebih / kurang, sesi masih buka, kas belum dihitung', () {
    final teks = laporanTeks(
      namaToko: 'X',
      keuangan: _keuangan,
      rekap: [
        _sesi(),
        _sesi(nomor: 'SK-00009', selisih: -15000),
        _sesi(nomor: 'SK-00010', selisih: 20000),
      ],
    );
    expect(teks, contains('*Rekap kasir*'));
    expect(teks, contains('SK-00008 · Kasir Demo: Rp 750.000 · kas pas'));
    expect(teks, contains('SK-00009 · Kasir Demo: Rp 750.000 · kas kurang Rp 15.000'));
    expect(teks, contains('SK-00010 · Kasir Demo: Rp 750.000 · kas lebih Rp 20.000'));

    final buka = laporanTeks(
      namaToko: 'X',
      keuangan: _keuangan,
      rekap: [_sesi(status: 'BUKA', selisih: null)],
    );
    expect(buka, contains('· masih buka'));

    final belumHitung = laporanTeks(
      namaToko: 'X',
      keuangan: _keuangan,
      rekap: [_sesi(selisih: null)],
    );
    expect(belumHitung, contains('SK-00008 · Kasir Demo: Rp 750.000\n'));
    expect(belumHitung, isNot(contains('kas ')));
  });

  test('jumlah sesi dibatasi maksSesi (yang terbaru saja)', () {
    final teks = laporanTeks(
      namaToko: 'X',
      keuangan: _keuangan,
      rekap: [for (var i = 1; i <= 5; i++) _sesi(nomor: 'SK-0000$i')],
      maksSesi: 2,
    );
    expect(teks, contains('SK-00001'));
    expect(teks, contains('SK-00002'));
    expect(teks, isNot(contains('SK-00003')));
  });
}
