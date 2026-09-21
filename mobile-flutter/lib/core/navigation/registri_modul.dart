import 'package:flutter/material.dart';

import '../../features/toko/domain/entities/toko_manifest.dart';
import '../diagnostik/log_cincin.dart';

/// Registri modul: `route_key` manifest server → layar aplikasi.
///
/// Sebelumnya daftar menu sekunder ditanam di `destinasi.dart` sehingga bidang
/// usaha baru dari server (mis. `jadwal` untuk gym & klinik) tidak pernah muncul
/// sampai ada rilis. Sekarang menu datang dari manifest — app hanya perlu tahu
/// layar mana yang membuka satu route_key. Kunci yang belum punya layar
/// DIABAIKAN dan dicatat, bukan dirender jadi menu yang menabrak rute mati.
class ModulApp {
  const ModulApp({
    required this.label,
    required this.deskripsi,
    required this.ikon,
    required this.rute,
  });

  final String label;
  final String deskripsi;
  final IconData ikon;
  final String rute;
}

/// Menu sekunder di lembar "Lainnya".
class MenuLain {
  const MenuLain({
    required this.label,
    required this.deskripsi,
    required this.ikon,
    required this.rute,
  });

  final String label;
  final String deskripsi;
  final IconData ikon;
  final String rute;
}

/// Label sengaja dari registri, bukan dari manifest: menu sekunder harus bernama
/// sama di semua bidang usaha (manifest salon menamai `produk` "Layanan & Produk",
/// dan itu dipakai sebagai judul layarnya).
const registriModul = <String, ModulApp>{
  'riwayat': ModulApp(
    label: 'Riwayat',
    deskripsi: 'Transaksi selesai & cetak ulang struk',
    ikon: Icons.receipt_long_outlined,
    rute: '/riwayat',
  ),
  'meja': ModulApp(
    label: 'Meja',
    deskripsi: 'Bon meja, ronde pesanan, bayar di akhir',
    ikon: Icons.table_restaurant_outlined,
    rute: '/meja',
  ),
  'produk': ModulApp(
    label: 'Produk',
    deskripsi: 'Katalog barang & layanan',
    ikon: Icons.inventory_2_outlined,
    rute: '/produk',
  ),
  'layanan': ModulApp(
    label: 'Layanan & Produk',
    deskripsi: 'Katalog layanan & barang',
    ikon: Icons.inventory_2_outlined,
    rute: '/produk',
  ),
  'pelanggan': ModulApp(
    label: 'Pelanggan',
    deskripsi: 'Daftar pelanggan toko',
    ikon: Icons.people_alt_outlined,
    rute: '/pelanggan',
  ),
  'member': ModulApp(
    label: 'Member',
    deskripsi: 'Daftar member & kontaknya',
    ikon: Icons.people_alt_outlined,
    rute: '/pelanggan',
  ),
  'jadwal': ModulApp(
    label: 'Jadwal',
    deskripsi: 'Kelas & janji temu hari ini beserta pesertanya',
    ikon: Icons.event_available_outlined,
    rute: '/jadwal',
  ),
  'pengeluaran': ModulApp(
    label: 'Pengeluaran',
    deskripsi: 'Biaya operasional bulan ini',
    ikon: Icons.account_balance_wallet_outlined,
    rute: '/pengeluaran',
  ),
  'sesi': ModulApp(
    label: 'Sesi Kasir',
    deskripsi: 'Buka & tutup shift, rekap kas',
    ikon: Icons.savings_outlined,
    rute: '/sesi',
  ),
  'pengaturan': ModulApp(
    label: 'Pengaturan',
    deskripsi: 'Profil usaha, printer, akun',
    ikon: Icons.settings_outlined,
    rute: '/pengaturan',
  ),
};

/// route_key yang SUDAH menjadi tujuan utama di bilah bawah (lihat `TujuanUtama`).
const _tujuanUtama = {'dashboard', 'home', 'kasir', 'order', 'kamar', 'laporan'};

/// Fitur khas app di LUAR manifest server (analisis stok UMKM) — selalu di bawah.
const _ekstraApp = [
  MenuLain(
    label: 'Stok',
    deskripsi: 'Stok menipis & saran restok',
    ikon: Icons.warehouse_outlined,
    rute: '/stok',
  ),
];

/// Set inti bila manifest tidak mengirim `menus` (server lama / tanpa manifest).
const _bawaan = ['produk', 'pelanggan', 'sesi', 'pengaturan'];

/// Menu sekunder untuk lembar "Lainnya", disusun dari manifest toko aktif.
List<MenuLain> menuLainDariManifest(
  TokoManifest? manifest, {
  void Function(String routeKey)? peringatan,
}) {
  final bertahap = manifest?.punyaPapanPesanan ?? false;
  final catat = peringatan ??
      (String k) => LogCincin.global.catat('Menu manifest route_key "$k" belum punya layar di aplikasi ini.');

  final menus = manifest?.menus ?? const <ManifestMenu>[];
  final kunci = <String>[];
  if (menus.isEmpty) {
    kunci.addAll(_bawaan);
  } else {
    final urut = [...menus]..sort((a, b) => a.order.compareTo(b.order));
    kunci.addAll(urut.map((m) => m.routeKey));
  }

  final out = <MenuLain>[];
  final sudah = <String>{};
  for (final key in kunci) {
    if (_tujuanUtama.contains(key)) continue;
    // Papan pesanan sudah jadi tab ketiga pada toko bertahap; riwayat jadi tab
    // ketiga pada toko retail. Yang bukan tab-nya turun ke lembar Lainnya.
    if (bertahap && TokoManifest.papanRouteKeys.contains(key)) continue;
    if (!bertahap && key == 'riwayat') continue;
    if (!sudah.add(key)) continue;
    final mod = registriModul[key];
    if (mod == null) {
      catat(key);
      continue;
    }
    out.add(MenuLain(label: mod.label, deskripsi: mod.deskripsi, ikon: mod.ikon, rute: mod.rute));
  }
  out.addAll(_ekstraApp);

  return out;
}
