import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../domain/entities/meja.dart';
import '../providers/meja_providers.dart';
import 'bill_detail_screen.dart';

/// Layar Meja (dine-in) — peta meja: kosong vs terisi (+ total bon).
/// Tap meja kosong → buka bon. Tambah item & bayar = fase berikutnya.
class MejaScreen extends ConsumerWidget {
  const MejaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peta = ref.watch(mejaPetaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Meja')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mejaPetaProvider),
        child: peta.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text(e is ApiException ? e.message : 'Gagal memuat meja.',
                      textAlign: TextAlign.center)),
            ),
          ]),
          data: (list) => list.isEmpty
              ? ListView(children: const [
                  Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: Text('Toko ini tidak menggunakan meja.')),
                  ),
                ])
              // Kolom mengikuti lebar layar (bukan tetap 2) dan tinggi kartu
              // tetap, bukan rasio: rasio membuat kartu terlalu pendek di
              // ponsel sempit sehingga isinya meluber.
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 118,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _MejaCard(meja: list[i]),
                ),
        ),
      ),
    );
  }
}

class _MejaCard extends ConsumerWidget {
  const _MejaCard({required this.meja});
  final Meja meja;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terisi = meja.terisi;
    final cs = Theme.of(context).colorScheme;
    final bg = terisi ? AppColors.mint600 : cs.surface;
    final fg = terisi ? Colors.white : cs.onSurface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => terisi ? _lihat(context, ref) : _konfirmasiBuka(context, ref),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: terisi ? Colors.transparent : cs.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.table_restaurant_outlined, color: fg, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Meja ${meja.nomor}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg, fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ],
              ),
              if (terisi)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Terisi${meja.pax != null ? ' · ${meja.pax} org' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 12)),
                    if (meja.billTotal != null)
                      Text(fmtIDR(meja.billTotal!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(Icons.add_circle_outline, color: cs.primary, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Buka bon',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _lihat(BuildContext context, WidgetRef ref) async {
    if (meja.billId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BillDetailScreen(billId: meja.billId!, mejaNomor: meja.nomor),
      ),
    );
    ref.invalidate(mejaPetaProvider); // segarkan total setelah kembali dari detail
  }

  Future<void> _konfirmasiBuka(BuildContext context, WidgetRef ref) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Buka bon Meja ${meja.nomor}?'),
        content: const Text('Meja akan ditandai terisi dan bon baru dibuka.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buka')),
        ],
      ),
    );
    if (ya != true || !context.mounted) return;
    final r = await ref.read(mejaRepositoryProvider).bukaBon(meja.id);
    if (!context.mounted) return;
    r.when(
      ok: (_) {
        ref.invalidate(mejaPetaProvider);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: AppColors.success,
              content: Text('Bon Meja ${meja.nomor} dibuka.')));
      },
      err: (e) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(e.firstError() ?? e.message))),
    );
  }
}
