import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/format.dart';
import '../../domain/entities/transaksi.dart';
import '../providers/riwayat_providers.dart';
import 'detail_transaksi_screen.dart';

/// Layar Riwayat — daftar transaksi toko aktif, tarik-untuk-segarkan.
class RiwayatScreen extends ConsumerWidget {
  const RiwayatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riwayat = ref.watch(riwayatListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(riwayatListProvider),
        child: riwayat.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    e is ApiException ? e.message : 'Gagal memuat riwayat.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: Text('Belum ada transaksi.')),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _TrxTile(trx: list[i]),
                ),
        ),
      ),
    );
  }
}

class _TrxTile extends StatelessWidget {
  const _TrxTile({required this.trx});
  final Transaksi trx;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dibatalkan = (trx.status ?? '').toUpperCase().contains('BATAL');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DetailTransaksiScreen(id: trx.id),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: cs.surfaceContainerHighest,
          child: Icon(Icons.receipt_long_outlined, color: cs.primary, size: 20),
        ),
        title: Text(trx.nomor, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          if (trx.tanggal != null) trx.tanggal!,
          if (trx.metode != null) '· ${trx.metode}',
        ].join(' ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fmtIDR(trx.grandTotal),
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    decoration: dibatalkan ? TextDecoration.lineThrough : null)),
            if (trx.status != null)
              Text(trx.status!,
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.55))),
          ],
        ),
      ),
    );
  }
}
