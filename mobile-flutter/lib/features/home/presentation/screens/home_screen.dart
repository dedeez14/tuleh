import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../demo/demo_session.dart';
import '../../../laporan/presentation/providers/laporan_providers.dart';
import '../../../toko/domain/entities/toko.dart';
import '../../../toko/presentation/providers/toko_providers.dart';

/// Beranda — header, pemilih toko, ringkasan bulan ini, aksi utama (Kasir),
/// lalu menu. Hierarki jelas: aksi tersering paling menonjol & mudah dijangkau.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _menu = <_Mod>[
    _Mod('Meja', Icons.table_restaurant_outlined, '/meja'),
    _Mod('Riwayat', Icons.receipt_long_outlined, '/riwayat'),
    _Mod('Laporan', Icons.bar_chart_rounded, '/laporan'),
    _Mod('Produk', Icons.inventory_2_outlined, '/produk'),
    _Mod('Stok', Icons.warehouse_outlined, '/stok'),
    _Mod('Pelanggan', Icons.people_alt_outlined, '/pelanggan'),
    _Mod('Pengeluaran', Icons.account_balance_wallet_outlined, '/pengeluaran'),
    _Mod('Sesi Kasir', Icons.point_of_sale_outlined, '/sesi'),
    _Mod('Pengaturan', Icons.settings_outlined, '/pengaturan'),
  ];

  /// Ikon papan pesanan mengikuti bidang usaha: dapur (KDS) vs antrian vs
  /// papan proses bertahap (laundry, bengkel, doorsmeer, salon).
  static IconData _ikonPapan(String routeKey) => switch (routeKey) {
    'dapur' => Icons.soup_kitchen_outlined,
    'antrian' => Icons.confirmation_number_outlined,
    _ => Icons.view_kanban_outlined,
  };

  static int _menuColumns(double width) {
    if (width >= 920) return 5;
    if (width >= 700) return 4;
    if (width >= 460) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    final tokos = ref.watch(tokoListProvider).valueOrNull ?? const <Toko>[];
    final activeId = ref.watch(activeTokoIdProvider).valueOrNull;

    if (activeId == null && tokos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeTokoIdProvider.notifier).select(tokos.first.id);
      });
    }
    Toko? activeToko;
    for (final t in tokos) {
      if (t.id == activeId) activeToko = t;
    }

    // Menu papan pesanan (KDS / Antrian / Papan Proses) hanya muncul untuk
    // bidang usaha bertahap; label & ikon mengikuti manifest toko aktif.
    final manifest = ref.watch(activeManifestProvider).valueOrNull;
    final menuPapan = manifest?.menuPapan;
    final menu = <_Mod>[
      if (manifest != null && manifest.punyaPapanPesanan)
        _Mod(
          menuPapan?.label ?? 'Papan Pesanan',
          _ikonPapan(menuPapan?.routeKey ?? 'proses'),
          '/pesanan',
        ),
      ..._menu,
    ];

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.primary.withValues(alpha: 0.07),
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0, 0.28, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = _menuColumns(constraints.maxWidth);
              final horizontalPad = constraints.maxWidth >= 700 ? 28.0 : 20.0;
              final tileHeight = constraints.maxWidth < 380 ? 108.0 : 116.0;

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPad,
                  12,
                  horizontalPad,
                  28,
                ),
                children: [
                  _Header(
                    user: user,
                    isDemo: ref.read(demoSessionProvider).active,
                    onLogout: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                  ),
                  const SizedBox(height: 18),
                  if (tokos.isNotEmpty)
                    _TokoChip(
                      toko: activeToko,
                      switchable: tokos.length > 1,
                      onTap: tokos.length > 1
                          ? () => _pickToko(context, ref, tokos, activeId)
                          : null,
                    ),
                  const SizedBox(height: 16),
                  const _RingkasanCard(),
                  const SizedBox(height: 16),
                  _FeaturedKasir(onTap: () => context.push('/kasir')),
                  const SizedBox(height: 24),
                  Text(
                    'Menu',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: menu.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: tileHeight,
                    ),
                    itemBuilder: (_, i) => _ModuleTile(mod: menu[i]),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _pickToko(
    BuildContext context,
    WidgetRef ref,
    List<Toko> tokos,
    String? activeId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Pilih Toko',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            for (final t in tokos)
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(t.nama),
                subtitle: t.bidangUsaha != null ? Text(t.bidangUsaha!) : null,
                trailing: t.id == activeId
                    ? const Icon(Icons.check_circle, color: AppColors.mint600)
                    : null,
                onTap: () {
                  ref.read(activeTokoIdProvider.notifier).select(t.id);
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Mod {
  const _Mod(this.title, this.icon, this.route);
  final String title;
  final IconData icon;
  final String? route;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.onLogout,
    this.isDemo = false,
  });
  final User? user;
  final bool isDemo;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = user?.name ?? 'Kasir';
    final firstName = name.split(' ').first;
    final initials = name
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0] : '')
        .join()
        .toUpperCase();

    return Row(
      children: [
        Container(
          height: 46,
          width: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.mint400.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            initials.isEmpty ? 'K' : initials,
            style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Halo, $firstName 👋',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Penanda demo: data simulasi, bukan data toko sungguhan.
                  if (isDemo) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warn.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'DEMO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: AppColors.warn,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (user?.companyName != null)
                Text(
                  user!.companyName!,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: isDemo ? 'Keluar dari Mode Demo' : 'Keluar',
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    );
  }
}

class _TokoChip extends StatelessWidget {
  const _TokoChip({required this.toko, required this.switchable, this.onTap});
  final Toko? toko;
  final bool switchable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.storefront_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  toko?.nama ?? 'Memuat toko…',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (switchable) ...[
                Text(
                  'Ganti',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.expand_more_rounded, color: cs.primary, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ringkasan bulan ini (omzet + transaksi). Graceful: skeleton saat memuat,
/// sembunyi bila gagal (tak mengganggu beranda).
class _RingkasanCard extends ConsumerWidget {
  const _RingkasanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(laporanKeuanganProvider);
    return k.when(
      error: (_, _) => const SizedBox.shrink(),
      loading: () => _shell(context, omzet: '…', trx: '…'),
      data: (v) =>
          _shell(context, omzet: fmtIDR(v.omset), trx: '${v.jumlahTransaksi}'),
    );
  }

  Widget _shell(
    BuildContext context, {
    required String omzet,
    required String trx,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Expanded(child: _stat(context, 'Omzet bulan ini', omzet)),
          Container(width: 1, height: 38, color: cs.outline),
          const SizedBox(width: 16),
          _stat(context, 'Transaksi', trx),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}

/// Aksi utama — Buka Kasir. Besar, kontras, mudah dijangkau (target sentuh lebar).
class _FeaturedKasir extends StatelessWidget {
  const _FeaturedKasir({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.mint600, AppColors.mint800],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.mint600.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buka Kasir',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Catat penjualan & terima pembayaran',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.mod});
  final _Mod mod;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = mod.route != null;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (active) {
            context.push(mod.route!);
          } else {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text('${mod.title} — segera hadir.')),
              );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.mint400.withValues(alpha: 0.18)
                          : cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      mod.icon,
                      color: active
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                  if (!active)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Icon(
                        Icons.lock_rounded,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                mod.title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
