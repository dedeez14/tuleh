// Registri route_key → rute (padanan registri-modul.js desktop). Menu sekunder
// disusun dari manifest server, bukan dari daftar yang ditanam di aplikasi.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/navigation/registri_modul.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko_manifest.dart';

TokoManifest _man(
  List<String> keys, {
  List<String> states = const ['SELESAI'],
  List<String> capabilities = const [],
}) => TokoManifest(
  menus: [
    for (var i = 0; i < keys.length; i++)
      ManifestMenu(id: keys[i], label: 'Label ${keys[i]}', routeKey: keys[i], order: i + 1),
  ],
  lifecycleStates: states,
  capabilities: capabilities,
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
    expect(menu.map((m) => m.rute), ['/pelanggan', '/jadwal', '/pengaturan', '/stok']);
    expect(registriModul['jadwal']!.rute, '/jadwal');
  });

  test('membership katalog asli: member & pelanggan menuju layar yang sama, satu baris saja', () {
    // Katalog `membership` (pos-katalog.json) mengirim `member` urutan 3 DAN
    // `pelanggan` urutan 90 — keduanya membuka /pelanggan.
    final menu = menuLainDariManifest(
      _man(['dashboard', 'kasir', 'member', 'jadwal', 'riwayat', 'sesi', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan']),
    );
    expect(menu.map((m) => m.rute), [
      '/pelanggan', '/jadwal', '/sesi', '/pengeluaran', '/pengaturan', '/stok',
    ]);
    expect(menu.first.label, 'Member', reason: 'route_key pertama menurut urutan manifest yang menang');
  });

  test('F&B: katalog tanpa menu meja tetap dapat baris Meja dari kapabilitas', () {
    // Katalog `fnb_kot` tidak punya menu `meja`, tetapi tokonya memakai bon meja
    // (capability `tables_qr`). Meja duduk sebelum fitur ekstra app.
    final menu = menuLainDariManifest(
      _man(
        ['dashboard', 'kasir', 'antrian', 'produk', 'inventory', 'riwayat', 'sesi', 'pelanggan', 'pengeluaran', 'laporan', 'pengaturan'],
        states: ['ANTRIAN', 'SELESAI'],
        capabilities: ['tables_qr'],
      ),
    );
    expect(menu.where((m) => m.rute == '/meja'), hasLength(1));
    expect(menu.map((m) => m.rute), [
      '/produk', '/riwayat', '/sesi', '/pelanggan', '/pengeluaran', '/pengaturan', '/meja', '/stok',
    ]);
    // Paritas desktop (pemantau-pesanan.js): `tables` juga membuka bon meja.
    expect(
      menuLainDariManifest(_man(['kasir', 'pengaturan'], capabilities: ['tables'])).map((m) => m.rute),
      ['/pengaturan', '/meja', '/stok'],
    );
  });

  test('manifest yang sudah punya route_key meja tidak dapat baris Meja dobel', () {
    final menu = menuLainDariManifest(
      _man(['kasir', 'meja', 'produk', 'pengaturan'], capabilities: ['tables_qr']),
    );
    expect(menu.where((m) => m.rute == '/meja'), hasLength(1));
    expect(menu.map((m) => m.rute), ['/meja', '/produk', '/pengaturan', '/stok']);
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

  test('Pengaturan selalu ada walau manifest tidak mengirimnya (peran Kasir)', () {
    // Server menyaring `menus` dengan required_permission: peran Kasir bawaan
    // tanpa `pengaturan.lihat` tidak menerima menunya, padahal layar itu
    // memegang setelan PERANGKAT (printer, sinkron) yang dipakai kasir.
    final menu = menuLainDariManifest(_man(['kasir', 'produk', 'sesi']));
    expect(menu.where((m) => m.rute == '/pengaturan'), hasLength(1));
    expect(menu.map((m) => m.rute), ['/produk', '/sesi', '/pengaturan', '/stok']);
  });

  test('manifest yang sudah mengirim pengaturan: satu baris, di posisi manifest', () {
    final menu = menuLainDariManifest(_man(['kasir', 'pengaturan', 'produk', 'sesi']));
    expect(menu.where((m) => m.rute == '/pengaturan'), hasLength(1));
    expect(menu.map((m) => m.rute), ['/pengaturan', '/produk', '/sesi', '/stok']);
  });

  test('setiap rute registri terdaftar di router (tak ada menu ke halaman mati)', () {
    final sumber = File('lib/core/router/app_router.dart').readAsStringSync();
    for (final m in [...registriModul.values.map((e) => e.rute), '/stok']) {
      expect(sumber, contains("'$m'"), reason: 'rute $m belum ada di app_router.dart');
    }
  });
}
