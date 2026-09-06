import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/offline/antrean.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../../core/offline/sinkronisasi_screen.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/tema_provider.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../cetak/presentation/screens/printer_screen.dart';
import '../../../pemantau/presentation/pemantau_providers.dart';
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
          const _SaklarPemantau(),
          const _EntriSinkronisasi(),
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
          const _EntriTema(),
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
      if (!context.mounted) return;
      await keluarDenganPenjagaAntrean(context, ref);
    }
  }
}

/// Keluar akun ditahan bila masih ada transaksi yang belum terkirim: antrean
/// milik akun ini tidak boleh dikirim dengan token akun lain, dan
/// menghapusnya berarti menghapus penjualan yang sudah terjadi.
Future<void> keluarDenganPenjagaAntrean(BuildContext context, WidgetRef ref) async {
  RingkasAntrean ringkas;
  try {
    ringkas = await ref.read(antreanStoreProvider).ringkas();
  } catch (_) {
    ringkas = const RingkasAntrean();
  }
  if (!context.mounted) return;
  if (ringkas.total == 0) {
    await ref.read(authControllerProvider.notifier).logout();
    return;
  }
  final keSinkron = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Masih ada yang belum terkirim'),
      content: Text(
        '${ringkas.menunggu} transaksi menunggu dikirim'
        '${ringkas.tinjau > 0 ? ' dan ${ringkas.tinjau} perlu ditinjau' : ''}. '
        'Sambungkan internet lalu sinkronkan dulu sebelum keluar, agar '
        'penjualan tidak hilang.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nanti')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buka Sinkronisasi')),
      ],
    ),
  );
  if (keSinkron == true && context.mounted) {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const SinkronisasiScreen()),
    );
  }
}

/// Entri Pengaturan → Sinkronisasi dengan jumlah antrean.
/// Pilihan tampilan: ikuti sistem, terang, gelap.
class _EntriTema extends ConsumerWidget {
  const _EntriTema();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tema = ref.watch(temaProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.brightness_6_outlined, color: cs.primary),
        title: const Text('Tampilan'),
        subtitle: Text(labelTema(tema)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Tampilan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
                RadioGroup<ThemeMode>(
                  groupValue: tema,
                  onChanged: (v) {
                    if (v != null) ref.read(temaProvider.notifier).pilih(v);
                    Navigator.of(ctx).pop();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final m in ThemeMode.values)
                        RadioListTile<ThemeMode>(value: m, title: Text(labelTema(m))),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntriSinkronisasi extends ConsumerWidget {
  const _EntriSinkronisasi();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final r = ref.watch(ringkasAntreanProvider).valueOrNull ?? const RingkasAntrean();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          r.tinjau > 0 ? Icons.sync_problem_rounded : Icons.sync_rounded,
          color: r.tinjau > 0 ? AppColors.danger : cs.primary,
        ),
        title: const Text('Sinkronisasi'),
        subtitle: Text(
          r.total == 0
              ? 'Semua transaksi sudah terkirim'
              : '${r.menunggu} menunggu dikirim · ${r.tinjau} perlu ditinjau',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(builder: (_) => const SinkronisasiScreen()),
        ),
      ),
    );
  }
}

/// Saklar "Notifikasi pesanan meja": menjalankan layanan latar depan yang
/// memeriksa pesanan meja walau aplikasi ditutup. Android menampilkan
/// notifikasi tetap selama layanan hidup — itu syarat sistem, dijelaskan di
/// subjudul agar tidak dikira gangguan.
class _SaklarPemantau extends ConsumerWidget {
  const _SaklarPemantau();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final svc = ref.watch(pemantauServiceProvider);
    if (!svc.didukung) return const SizedBox.shrink();
    final aktif = ref.watch(pemantauDiinginkanProvider).valueOrNull ?? false;
    final demo = ref.watch(authControllerProvider.notifier).isDemo;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        secondary: Icon(Icons.notifications_active_outlined, color: cs.primary),
        title: const Text('Notifikasi pesanan meja'),
        subtitle: Text(
          demo
              ? 'Tidak tersedia di Mode Demo.'
              : aktif
              ? 'Berjalan di latar belakang; bunyi saat ada pesanan atau '
                    'permintaan bayar dari meja. Notifikasi "memantau" '
                    'tetap tampil selama aktif.'
              : 'Beri tahu saat pelanggan memesan atau minta bayar dari '
                    'QR meja, walau aplikasi ditutup.',
        ),
        value: aktif,
        onChanged: demo
            ? null
            : (v) async {
                if (v) {
                  final izin = await svc.mintaIzin();
                  if (!izin) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Izin notifikasi ditolak. Aktifkan di Setelan '
                          'Android → Aplikasi → Tuléh → Notifikasi.',
                        ),
                      ),
                    );
                    return;
                  }
                }
                await ref.read(pemantauDiinginkanProvider.notifier).atur(v);
              },
      ),
    );
  }
}
