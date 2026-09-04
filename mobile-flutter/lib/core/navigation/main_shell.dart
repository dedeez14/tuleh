import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/kasir/presentation/controllers/cart_controller.dart';
import '../../features/toko/presentation/providers/toko_providers.dart';
import 'destinasi.dart';

/// Kerangka utama aplikasi — bilah navigasi Material 3 di bawah (ponsel) atau
/// rail di samping (tablet).
///
/// Sebelumnya setiap perpindahan harus lewat Beranda; di kasir yang dipakai
/// seharian, itu berarti dua ketukan tambahan untuk setiap tugas. Sekarang
/// empat tujuan utama selalu terjangkau ibu jari, sisanya di lembar "Lainnya".
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _lebarRail = 720.0;

  void _pindah(int i) => navigationShell.goBranch(
    i,
    // Ketuk tab yang sedang aktif → kembali ke akar tab itu.
    initialLocation: i == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifest = ref.watch(activeManifestProvider).valueOrNull;
    final jumlahKeranjang = ref.watch(cartCountProvider);

    final tujuan = [
      TujuanUtama.beranda,
      TujuanUtama.kasir,
      TujuanUtama.aktivitas(manifest),
      TujuanUtama.laporan,
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final lebar = c.maxWidth >= _lebarRail;
        if (lebar) {
          return Scaffold(
            body: Row(
              children: [
                _Rail(
                  tujuan: tujuan,
                  terpilih: navigationShell.currentIndex,
                  jumlahKeranjang: jumlahKeranjang,
                  onPilih: _pindah,
                  onLainnya: () => _bukaLainnya(context, ref),
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: _BilahBawah(
            tujuan: tujuan,
            terpilih: navigationShell.currentIndex,
            jumlahKeranjang: jumlahKeranjang,
            onPilih: _pindah,
            onLainnya: () => _bukaLainnya(context, ref),
          ),
        );
      },
    );
  }

  Future<void> _bukaLainnya(BuildContext context, WidgetRef ref) {
    final manifest = ref.read(activeManifestProvider).valueOrNull;
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _LembarLainnya(menu: TujuanUtama.menuLain(manifest)),
    );
  }
}

class _BilahBawah extends StatelessWidget {
  const _BilahBawah({
    required this.tujuan,
    required this.terpilih,
    required this.jumlahKeranjang,
    required this.onPilih,
    required this.onLainnya,
  });

  final List<Destinasi> tujuan;
  final int terpilih;
  final int jumlahKeranjang;
  final ValueChanged<int> onPilih;
  final VoidCallback onLainnya;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: terpilih,
      // "Lainnya" (indeks terakhir) membuka lembar, bukan mengganti tab.
      onDestinationSelected: (i) =>
          i == tujuan.length ? onLainnya() : onPilih(i),
      destinations: [
        for (var i = 0; i < tujuan.length; i++)
          NavigationDestination(
            icon: _ikon(tujuan[i].ikon, i),
            selectedIcon: _ikon(tujuan[i].ikonAktif, i),
            label: tujuan[i].label,
          ),
        NavigationDestination(
          icon: Icon(TujuanUtama.lainnya.ikon),
          selectedIcon: Icon(TujuanUtama.lainnya.ikonAktif),
          label: TujuanUtama.lainnya.label,
        ),
      ],
    );
  }

  /// Lencana jumlah item hanya pada tab Kasir (indeks 1).
  Widget _ikon(IconData ikon, int i) {
    if (i != 1 || jumlahKeranjang == 0) return Icon(ikon);
    return Badge(
      label: Text(jumlahKeranjang > 99 ? '99+' : '$jumlahKeranjang'),
      child: Icon(ikon),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.tujuan,
    required this.terpilih,
    required this.jumlahKeranjang,
    required this.onPilih,
    required this.onLainnya,
  });

  final List<Destinasi> tujuan;
  final int terpilih;
  final int jumlahKeranjang;
  final ValueChanged<int> onPilih;
  final VoidCallback onLainnya;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: terpilih,
      onDestinationSelected: (i) =>
          i == tujuan.length ? onLainnya() : onPilih(i),
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (var i = 0; i < tujuan.length; i++)
          NavigationRailDestination(
            icon: i == 1 && jumlahKeranjang > 0
                ? Badge(
                    label: Text('$jumlahKeranjang'),
                    child: Icon(tujuan[i].ikon),
                  )
                : Icon(tujuan[i].ikon),
            selectedIcon: Icon(tujuan[i].ikonAktif),
            label: Text(tujuan[i].label),
          ),
        NavigationRailDestination(
          icon: Icon(TujuanUtama.lainnya.ikon),
          selectedIcon: Icon(TujuanUtama.lainnya.ikonAktif),
          label: Text(TujuanUtama.lainnya.label),
        ),
      ],
    );
  }
}

class _LembarLainnya extends StatelessWidget {
  const _LembarLainnya({required this.menu});

  final List<MenuLain> menu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Menu lainnya',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: menu.length,
              itemBuilder: (context, i) {
                final m = menu[i];
                return ListTile(
                  leading: Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(m.ikon, size: 21, color: cs.onSecondaryContainer),
                  ),
                  title: Text(
                    m.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(m.deskripsi),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(m.rute);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
