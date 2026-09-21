import 'package:flutter/material.dart';

import '../../features/toko/domain/entities/toko_manifest.dart';
import 'registri_modul.dart';

// MenuLain kini tinggal di registri_modul.dart bersama peta route_key → rute;
// diekspor ulang agar pemanggil lama (main_shell.dart) tidak perlu berubah.
export 'registri_modul.dart' show MenuLain, ModulApp, registriModul;

/// Tujuan utama aplikasi — yang tampil di bilah navigasi bawah.
///
/// Hanya empat, sesuai anjuran Material: lebih dari itu, label memendek dan
/// pengguna berhenti membacanya. Sisanya masuk lembar "Lainnya".
class Destinasi {
  const Destinasi({
    required this.label,
    required this.ikon,
    required this.ikonAktif,
  });

  final String label;
  final IconData ikon;
  final IconData ikonAktif;
}

/// Cabang ketiga menyesuaikan bidang usaha: toko bertahap memakai papan
/// pesanan (label dari manifest), toko retail memakai riwayat transaksi.
/// Satu cabang dengan isi yang menyesuaikan, bukan tab yang kadang kosong.
class TujuanUtama {
  const TujuanUtama._();

  static Destinasi beranda = const Destinasi(
    label: 'Beranda',
    ikon: Icons.home_outlined,
    ikonAktif: Icons.home_rounded,
  );

  static Destinasi kasir = const Destinasi(
    label: 'Kasir',
    ikon: Icons.point_of_sale_outlined,
    ikonAktif: Icons.point_of_sale_rounded,
  );

  static Destinasi laporan = const Destinasi(
    label: 'Laporan',
    ikon: Icons.insert_chart_outlined_rounded,
    ikonAktif: Icons.insert_chart_rounded,
  );

  static const Destinasi lainnya = Destinasi(
    label: 'Lainnya',
    ikon: Icons.grid_view_outlined,
    ikonAktif: Icons.grid_view_rounded,
  );

  /// Tujuan ketiga untuk manifest tertentu.
  ///
  /// Label bilah bawah sengaja pendek per jenis papan (Dapur/Antrian/Pesanan),
  /// bukan label penuh manifest seperti "Antrian Cukur" yang melipat jadi dua
  /// baris di bilah lima tujuan. Label penuh tetap dipakai judul layarnya.
  static Destinasi aktivitas(TokoManifest? manifest) {
    if (manifest != null && manifest.punyaPapanPesanan) {
      final route = manifest.menuPapan?.routeKey ?? 'proses';
      return Destinasi(
        label: switch (route) {
          'dapur' => 'Dapur',
          'antrian' => 'Antrian',
          _ => 'Pesanan',
        },
        ikon: switch (route) {
          'dapur' => Icons.soup_kitchen_outlined,
          'antrian' => Icons.confirmation_number_outlined,
          _ => Icons.view_kanban_outlined,
        },
        ikonAktif: switch (route) {
          'dapur' => Icons.soup_kitchen_rounded,
          'antrian' => Icons.confirmation_number_rounded,
          _ => Icons.view_kanban_rounded,
        },
      );
    }
    return const Destinasi(
      label: 'Riwayat',
      ikon: Icons.receipt_long_outlined,
      ikonAktif: Icons.receipt_long_rounded,
    );
  }

  /// Menu sekunder — disusun dari manifest toko aktif lewat registri route_key
  /// (dulu daftar tetap di berkas ini; bidang usaha baru dari server tidak pernah
  /// muncul sampai ada rilis).
  static List<MenuLain> menuLain(TokoManifest? manifest) => menuLainDariManifest(manifest);
}
