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

/// Label sengaja diambil dari registri, bukan dari label manifest: tiap route_key
/// punya satu nama tetap yang dikenal app, sehingga menu sekunder tidak ikut
/// berganti nama mengikuti penamaan bebas per bidang usaha (manifest salon
/// menamai `produk` "Layanan & Produk", katalog F&B menamainya "Menu" — label
/// penuh dari manifest tetap dipakai sebagai judul layarnya).
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

/// Rute empat tujuan utama — selalu terjangkau lewat bilah bawah/rail.
const ruteTujuanUtama = {'/home', '/kasir', '/aktivitas', '/laporan'};

/// Fitur khas app di LUAR manifest server (analisis stok UMKM) — selalu di bawah.
const _ekstraApp = [
  MenuLain(
    label: 'Stok',
    deskripsi: 'Stok menipis & saran restok',
    ikon: Icons.warehouse_outlined,
    rute: '/stok',
  ),
];

/// Kapabilitas manifest yang membuka bon meja walau katalog tidak mengirim menu
/// `meja` (katalog `fnb_kot` tidak punya menunya) — paritas `cakupan()` di
/// `pemantau-pesanan.js` desktop.
const _kapabilitasMeja = {'tables_qr', 'tables'};

/// Set inti bila manifest tidak mengirim `menus` (server lama / tanpa manifest).
const _bawaan = ['produk', 'pelanggan', 'sesi', 'pengaturan'];

/// Satu entri registri jadi satu baris menu.
MenuLain _dariModul(ModulApp m) =>
    MenuLain(label: m.label, deskripsi: m.deskripsi, ikon: m.ikon, rute: m.rute);

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
    // Tie-break indeks asli: menu berbentuk string dari server lama semuanya
    // order 0, dan List.sort tidak stabil di atas 32 elemen.
    final urut = [for (var i = 0; i < menus.length; i++) (i, menus[i])]..sort((a, b) {
      final selisih = a.$2.order.compareTo(b.$2.order);
      return selisih != 0 ? selisih : a.$1.compareTo(b.$1);
    });
    kunci.addAll(urut.map((e) => e.$2.routeKey));
  }

  final out = <MenuLain>[];
  final sudah = <String>{};
  // Dedupe kedua, per RUTE: katalog membership mengirim `member` (urutan 3) dan
  // `pelanggan` (urutan 90) yang sama-sama membuka /pelanggan. Kunci pertama
  // menurut urutan manifest yang menang, jadi labelnya "Member".
  final ruteSudah = <String>{};
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
    if (!ruteSudah.add(mod.rute)) continue;
    out.add(_dariModul(mod));
  }

  // Bon meja digerbang kapabilitas, bukan menu — katalog `fnb_kot` tidak
  // mengirim route_key `meja` padahal tokonya memakai meja.
  final modMeja = registriModul['meja']!;
  final kapabilitas = manifest?.capabilities ?? const <String>[];
  if (!ruteSudah.contains(modMeja.rute) && kapabilitas.any(_kapabilitasMeja.contains)) {
    ruteSudah.add(modMeja.rute);
    out.add(_dariModul(modMeja));
  }

  // Pengaturan SELALU ada. Server menyaring `menus` dengan required_permission,
  // dan peran Kasir bawaan tidak punya `pengaturan.lihat` — padahal layar ini
  // memegang setelan PERANGKAT (printer, sinkron, diagnostik) yang justru
  // dibutuhkan kasir dan tidak menyentuh data server.
  final modSetelan = registriModul['pengaturan']!;
  if (ruteSudah.add(modSetelan.rute)) out.add(_dariModul(modSetelan));

  out.addAll(_ekstraApp);

  return out;
}

/// Rute yang punya PINTU untuk manifest ini: empat tujuan utama + setiap kartu
/// di lembar "Lainnya". Dipakai penyegaran identitas (Tahap B §2b) untuk
/// memulangkan pengguna dari layar yang haknya baru saja dicabut — server
/// menyaring `menus` per hak akses, jadi menu yang hilang = pintu yang hilang.
///
/// Rute yang tak pernah muncul di sini (papan pesanan, layar rincian) memang
/// tak punya kartu; penggunanya tidak boleh ikut terusir (lihat `layarTujuan`).
/// Peringatan route_key tak dikenal sengaja dibungkam: daftar ini dihitung tiap
/// penyegaran, bukan saat menggambar menu.
Set<String> rutePunyaPintu(TokoManifest? manifest) => {
  ...ruteTujuanUtama,
  for (final m in menuLainDariManifest(manifest, peringatan: (_) {})) m.rute,
};
