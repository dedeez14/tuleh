import 'package:flutter/foundation.dart';
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
import '../widgets/motion.dart';
import '../widgets/splash_screen.dart';

/// Router aplikasi (go_router). Redirect berbasis status auth; jembatan
/// Riverpod → Listenable agar router menyegar saat login/logout/auto-login.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final loggedIn = auth.value != null;

      // Splash menunggu auto-login selesai, lalu arahkan.
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
      GoRoute(
        path: '/home',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const HomeScreen()),
      ),
      GoRoute(
        path: '/kasir',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const KasirScreen()),
      ),
      GoRoute(
        path: '/riwayat',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const RiwayatScreen()),
      ),
      GoRoute(
        path: '/laporan',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const LaporanScreen()),
      ),
      GoRoute(
        path: '/meja',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const MejaScreen()),
      ),
      // Satu layar untuk KDS dapur / Antrian / Papan Proses — kolom dari manifest.
      GoRoute(
        path: '/pesanan',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const PapanPesananScreen()),
      ),
      GoRoute(
        path: '/produk',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const ProdukScreen()),
      ),
      GoRoute(
        path: '/pelanggan',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const PelangganScreen()),
      ),
      GoRoute(
        path: '/pengeluaran',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const PengeluaranScreen()),
      ),
      GoRoute(
        path: '/sesi',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const SesiScreen()),
      ),
      GoRoute(
        path: '/stok',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const StokScreen()),
      ),
      GoRoute(
        path: '/pengaturan',
        pageBuilder: (_, state) =>
            halamanBeranimasi<void>(key: state.pageKey, child: const PengaturanScreen()),
      ),
    ],
  );
});
