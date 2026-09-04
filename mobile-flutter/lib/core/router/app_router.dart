import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/kasir/presentation/screens/kasir_screen.dart';
import '../../features/laporan/presentation/screens/laporan_screen.dart';
import '../../features/meja/presentation/screens/meja_screen.dart';
import '../../features/pelanggan/presentation/screens/pelanggan_screen.dart';
import '../../features/pengaturan/presentation/screens/pengaturan_screen.dart';
import '../../features/pengeluaran/presentation/screens/pengeluaran_screen.dart';
import '../../features/pesanan/presentation/screens/papan_pesanan_screen.dart';
import '../../features/products/presentation/screens/produk_screen.dart';
import '../../features/riwayat/presentation/screens/riwayat_screen.dart';
import '../../features/sesi/presentation/screens/sesi_screen.dart';
import '../../features/stok/presentation/screens/stok_screen.dart';
import '../../features/toko/presentation/providers/toko_providers.dart';
import '../navigation/main_shell.dart';
import '../widgets/motion.dart';
import '../widgets/splash_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Router aplikasi (go_router).
///
/// Empat cabang bertab hidup di dalam [MainShell] (state tiap tab dijaga saat
/// berpindah). Layar sekunder didorong di atas kerangka lewat navigator akar
/// sehingga bilah bawah menghilang — pola baku Material untuk halaman dalam.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final loggedIn = auth.value != null;

      if (loc == '/splash') {
        if (auth.isLoading) return null;
        return loggedIn ? '/home' : '/login';
      }
      if (!loggedIn && loc != '/login') return '/login';
      if (loggedIn && loc == '/login') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),

      // ---- Tab utama ----
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/kasir', builder: (_, _) => const KasirScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              // Isi cabang menyesuaikan manifest: papan pesanan untuk toko
              // bertahap, riwayat untuk retail (lihat TujuanUtama.aktivitas).
              GoRoute(
                path: '/aktivitas',
                builder: (_, _) => const _CabangAktivitas(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/laporan', builder: (_, _) => const LaporanScreen()),
            ],
          ),
        ],
      ),

      // ---- Layar sekunder (di atas kerangka, bilah bawah tersembunyi) ----
      for (final r in _sekunder)
        GoRoute(
          path: r.$1,
          parentNavigatorKey: _rootKey,
          pageBuilder: (_, state) =>
              halamanBeranimasi<void>(key: state.pageKey, child: r.$2),
        ),
    ],
  );
});

const _sekunder = <(String, Widget)>[
  ('/riwayat', RiwayatScreen()),
  ('/pesanan', PapanPesananScreen()),
  ('/meja', MejaScreen()),
  ('/produk', ProdukScreen()),
  ('/pelanggan', PelangganScreen()),
  ('/pengeluaran', PengeluaranScreen()),
  ('/sesi', SesiScreen()),
  ('/stok', StokScreen()),
  ('/pengaturan', PengaturanScreen()),
];

class _CabangAktivitas extends ConsumerWidget {
  const _CabangAktivitas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifest = ref.watch(activeManifestProvider).valueOrNull;
    final bertahap = manifest?.punyaPapanPesanan ?? false;
    return bertahap ? const PapanPesananScreen() : const RiwayatScreen();
  }
}
