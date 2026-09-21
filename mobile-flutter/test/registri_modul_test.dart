// Registri route_key → rute (padanan registri-modul.js desktop). Menu sekunder
// disusun dari manifest server, bukan dari daftar yang ditanam di aplikasi.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/navigation/registri_modul.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko_manifest.dart';

TokoManifest _man(List<String> keys, {List<String> states = const ['SELESAI']}) => TokoManifest(
  menus: [
    for (var i = 0; i < keys.length; i++)
      ManifestMenu(id: keys[i], label: 'Label ${keys[i]}', routeKey: keys[i], order: i + 1),
  ],
  lifecycleStates: states,
);

void main() {
  test('retail: menu sekunder dari manifest, tujuan utama & riwayat (tab ketiga) dilewati', () {
    final menu = menuLainDariManifest(
      _man(['dashboard', 'kasir', 'produk', 'inventory', 'riwayat', 'sesi', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan']),
    );
    expect(menu.map((m) => m.rute), [
      '/produk', '/sesi', '/pelanggan', '/pengeluaran', '/pengaturan', '/stok',
    ]);
    expect(menu.first.label, 'Produk', reason: 'label registri, bukan label manifest');
  });

  test('toko bertahap: papan jadi tab ketiga sehingga riwayat turun ke Lainnya', () {
    final menu = menuLainDariManifest(
      _man(['dashboard', 'kasir', 'antrian', 'layanan', 'riwayat', 'sesi', 'pengaturan'], states: ['ANTRIAN', 'SELESAI']),
    );
    expect(menu.map((m) => m.rute), ['/produk', '/riwayat', '/sesi', '/pengaturan', '/stok']);
    expect(menu.any((m) => m.rute == '/pesanan'), isFalse, reason: 'papan sudah jadi tujuan utama');
  });

  test('membership: route_key jadwal & member punya rute', () {
    final menu = menuLainDariManifest(_man(['dashboard', 'kasir', 'member', 'jadwal', 'riwayat', 'laporan']));
    expect(menu.map((m) => m.rute), ['/pelanggan', '/jadwal', '/stok']);
    expect(registriModul['jadwal']!.rute, '/jadwal');
  });

  test('route_key tak dikenal diabaikan & dicatat, bukan menu yang menabrak rute mati', () {
    final dicatat = <String>[];
    final menu = menuLainDariManifest(
      _man(['kasir', 'teleportasi', 'inventory', 'pengaturan']),
      peringatan: dicatat.add,
    );
    expect(menu.map((m) => m.rute), ['/pengaturan', '/stok']);
    expect(dicatat, ['teleportasi', 'inventory']);
  });

  test('manifest tanpa menus (server lama): set inti + fitur ekstra app', () {
    expect(
      menuLainDariManifest(const TokoManifest()).map((m) => m.rute),
      ['/produk', '/pelanggan', '/sesi', '/pengaturan', '/stok'],
    );
    expect(menuLainDariManifest(null).map((m) => m.rute).last, '/stok');
  });

  test('setiap rute registri terdaftar di router (tak ada menu ke halaman mati)', () {
    final sumber = File('lib/core/router/app_router.dart').readAsStringSync();
    for (final m in [...registriModul.values.map((e) => e.rute), '/stok']) {
      expect(sumber, contains("'$m'"), reason: 'rute $m belum ada di app_router.dart');
    }
  });
}
