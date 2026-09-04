import 'package:flutter/material.dart';

import '../../features/toko/domain/entities/toko_manifest.dart';

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

  /// Menu sekunder. Meja hanya untuk toko yang memakai bon meja; riwayat
  /// disembunyikan bila sudah jadi tujuan utama.
  static List<MenuLain> menuLain(TokoManifest? manifest) {
    final bertahap = manifest?.punyaPapanPesanan ?? false;
    final pakaiMeja = manifest?.capabilities.contains('tables_qr') ?? false;
    return [
      if (bertahap)
        const MenuLain(
          label: 'Riwayat',
          deskripsi: 'Transaksi selesai & cetak ulang struk',
          ikon: Icons.receipt_long_outlined,
          rute: '/riwayat',
        ),
      if (pakaiMeja)
        const MenuLain(
          label: 'Meja',
          deskripsi: 'Bon meja, ronde pesanan, bayar di akhir',
          ikon: Icons.table_restaurant_outlined,
          rute: '/meja',
        ),
      const MenuLain(
        label: 'Produk',
        deskripsi: 'Katalog barang & layanan',
        ikon: Icons.inventory_2_outlined,
        rute: '/produk',
      ),
      const MenuLain(
        label: 'Stok',
        deskripsi: 'Stok menipis & saran restok',
        ikon: Icons.warehouse_outlined,
        rute: '/stok',
      ),
      const MenuLain(
        label: 'Pelanggan',
        deskripsi: 'Daftar pelanggan toko',
        ikon: Icons.people_alt_outlined,
        rute: '/pelanggan',
      ),
      const MenuLain(
        label: 'Pengeluaran',
        deskripsi: 'Biaya operasional bulan ini',
        ikon: Icons.account_balance_wallet_outlined,
        rute: '/pengeluaran',
      ),
      const MenuLain(
        label: 'Sesi Kasir',
        deskripsi: 'Buka & tutup shift, rekap kas',
        ikon: Icons.savings_outlined,
        rute: '/sesi',
      ),
      const MenuLain(
        label: 'Pengaturan',
        deskripsi: 'Profil usaha, printer, akun',
        ikon: Icons.settings_outlined,
        rute: '/pengaturan',
      ),
    ];
  }
}
