import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../utils/format.dart';
import '../widgets/states.dart';
import 'antrean.dart';
import 'koneksi.dart';
import 'pengurai.dart';

/// Pengaturan → Sinkronisasi: antrean transaksi/pengeluaran/stok yang belum
/// terkirim, status tiap baris, "Sinkron sekarang", dan keputusan untuk baris
/// yang perlu ditinjau (kirim ulang / batalkan). Istilah untuk kasir, bukan
/// istilah teknis.
class SinkronisasiScreen extends ConsumerStatefulWidget {
  const SinkronisasiScreen({super.key});

  @override
  ConsumerState<SinkronisasiScreen> createState() => _SinkronisasiScreenState();
}

class _SinkronisasiScreenState extends ConsumerState<SinkronisasiScreen> {
  bool _sibuk = false;

  Future<void> _sinkronSekarang() async {
    setState(() => _sibuk = true);
    final online = await ref.read(koneksiProvider.notifier).periksa();
    if (online) await ref.read(penguraiProvider).jalankan();
    if (!mounted) return;
    setState(() => _sibuk = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            online ? 'Sinkronisasi dijalankan.' : 'Server belum terjangkau.',
          ),
        ),
      );
  }

  Future<void> _batalkan(PesanAntrean p) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Batalkan ${p.label.toLowerCase()} ini?'),
        content: const Text(
          'Data dihapus dari perangkat dan tidak akan dikirim ke server. '
          'Stok yang tadi dikurangi dikembalikan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    if (ya != true) return;
    await ref.read(antreanStoreProvider).batalkan(p.clientRef);
    ref.read(antreanVersiProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final daftar = ref.watch(daftarAntreanProvider);
    final koneksi = ref.watch(koneksiProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sinkronisasi')),
      body: daftar.when(
        loading: () => const DaftarKerangka(jumlah: 4, tinggiBaris: 84),
        error: (e, _) => KeadaanGagal(
          error: e,
          onUlangi: () => ref.invalidate(daftarAntreanProvider),
        ),
        data: (rows) {
          final aktif = rows.where((p) => p.status != StatusAntrean.terkirim).toList();
          final terkirim = rows.where((p) => p.status == StatusAntrean.terkirim).toList().reversed.take(20).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _KartuStatus(
                online: koneksi.online,
                menunggu: aktif.where((p) => p.belumTerkirim).length,
                tinjau: aktif.where((p) => p.perluPerhatian).length,
                sibuk: _sibuk,
                onSinkron: _sinkronSekarang,
              ),
              const SizedBox(height: 18),
              if (aktif.isEmpty)
                const KeadaanKosong(
                  ikon: Icons.cloud_done_outlined,
                  judul: 'Semua sudah terkirim',
                  detail: 'Transaksi yang dibuat saat offline akan tampil di sini.',
                )
              else ...[
                Text('Menunggu & perlu ditinjau', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final p in aktif) _BarisAntrean(p: p, onBatalkan: () => _batalkan(p)),
              ],
              if (terkirim.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('Terkirim terakhir', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final p in terkirim)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle, color: AppColors.success),
                    title: Text('${p.label} · ${_nomorHasil(p)}'),
                    subtitle: Text(fmtTanggal(p.dibuat.toIso8601String())),
                    textColor: cs.onSurface.withValues(alpha: 0.75),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _nomorHasil(PesanAntrean p) {
    final n = p.hasil?['nomor'] ?? p.hasil?['no'];
    return n == null ? 'selesai' : '$n';
  }
}

class _KartuStatus extends StatelessWidget {
  const _KartuStatus({
    required this.online,
    required this.menunggu,
    required this.tinjau,
    required this.sibuk,
    required this.onSinkron,
  });

  final bool online;
  final int menunggu;
  final int tinjau;
  final bool sibuk;
  final VoidCallback onSinkron;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  online ? Icons.cloud_done_outlined : Icons.cloud_off_rounded,
                  color: online ? AppColors.success : AppColors.warn,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    online ? 'Server terjangkau' : 'Offline',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$menunggu menunggu dikirim · $tinjau perlu ditinjau',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: sibuk ? null : onSinkron,
              icon: sibuk
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.mint900),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(sibuk ? 'Menyinkronkan…' : 'Sinkron sekarang'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarisAntrean extends ConsumerWidget {
  const _BarisAntrean({required this.p, required this.onBatalkan});
  final PesanAntrean p;
  final VoidCallback onBatalkan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tinjau = p.perluPerhatian;
    final total = p.body['dibayar'] ?? p.body['nominal'] ?? p.body['jumlah'];
    final keterangan = switch (p.jenis) {
      'CHECKOUT' => '${(p.body['items'] as List?)?.length ?? 0} item · ${p.body['tipe_pembayaran'] ?? ''}',
      'PENGELUARAN' => '${p.body['keterangan'] ?? ''}',
      'STOK_MASUK' => 'Jumlah ${fmtQty((p.body['jumlah'] as num?) ?? 0)}',
      _ => '',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  tinjau ? Icons.error_outline_rounded : Icons.schedule_rounded,
                  size: 18,
                  color: tinjau ? AppColors.danger : AppColors.warn,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${p.label}${total is num && p.jenis != 'STOK_MASUK' ? ' · ${fmtIDR(total.toDouble())}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  tinjau ? 'Perlu ditinjau' : (p.status == StatusAntrean.mengirim ? 'Mengirim…' : 'Menunggu'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tinjau ? AppColors.danger : AppColors.warn,
                  ),
                ),
              ],
            ),
            if (keterangan.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(keterangan, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.65))),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Dibuat ${fmtTanggal(p.dibuat.toIso8601String())}'
                '${p.percobaan > 0 ? ' · percobaan ke-${p.percobaan}' : ''}',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55)),
              ),
            ),
            if (p.galatTerakhir != null && p.galatTerakhir!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  p.galatTerakhir!,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: tinjau ? AppColors.danger : cs.onSurface.withValues(alpha: 0.7)),
                ),
              ),
            if (tinjau)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onBatalkan, child: const Text('Batalkan')),
                  TextButton(
                    onPressed: () => ref.read(penguraiProvider).kirimUlang(p.clientRef),
                    child: const Text('Kirim ulang'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
