import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../cetak/presentation/screens/printer_screen.dart';
import '../../../toko/domain/entities/toko.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import 'profil_usaha_screen.dart';

/// Layar Pengaturan — profil pengguna, toko aktif, versi app, keluar.
class PengaturanScreen extends ConsumerWidget {
  const PengaturanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    final version = ref.watch(appVersionProvider);
    final tokos = ref.watch(tokoListProvider).valueOrNull ?? const <Toko>[];
    final activeId = ref.watch(activeTokoIdProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;

    Toko? activeToko;
    for (final t in tokos) {
      if (t.id == activeId) activeToko = t;
    }

    final name = user?.name ?? 'Pengguna';
    final initials = name
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isNotEmpty ? w[0] : '')
        .join()
        .toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.mint400.withValues(alpha: 0.2),
                    child: Text(initials.isEmpty ? 'U' : initials,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: cs.primary)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                        if (user?.email != null)
                          Text(user!.email!,
                              style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.6))),
                        if (user?.role != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.mint400.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(user!.role!,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(Icons.badge_outlined, color: cs.primary),
              title: const Text('Profil Usaha'),
              subtitle: const Text('Nama, alamat, kontak, struk'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfilUsahaScreen()),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(Icons.print_outlined, color: cs.primary),
              title: const Text('Printer Struk'),
              subtitle: const Text('Printer thermal Bluetooth & uji cetak'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrinterScreen()),
              ),
            ),
          ),
          _tile(context, Icons.storefront_outlined, 'Toko aktif',
              activeToko?.nama ?? '—'),
          _tile(context, Icons.info_outline_rounded, 'Versi aplikasi', version),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger.withValues(alpha: 0.12),
              foregroundColor: AppColors.danger,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => _konfirmasiKeluar(context, ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(label),
        trailing: Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.75))),
      ),
    );
  }

  Future<void> _konfirmasiKeluar(BuildContext context, WidgetRef ref) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari Tuléh?'),
        content: const Text('Anda perlu masuk kembali untuk memakai aplikasi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ya == true) {
      ref.read(authControllerProvider.notifier).logout();
    }
  }
}
