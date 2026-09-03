import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../sesi/domain/entities/sesi_rekap.dart';
import '../../domain/entities/laporan_keuangan.dart';
import '../providers/laporan_providers.dart';

/// Layar Laporan — ringkasan keuangan bulan berjalan + penjualan harian.
class LaporanScreen extends ConsumerWidget {
  const LaporanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keuangan = ref.watch(laporanKeuanganProvider);
    final harian = ref.watch(penjualanHarianProvider);
    final rekap = ref.watch(rekapKasirProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(laporanKeuanganProvider);
          ref.invalidate(penjualanHarianProvider);
          ref.invalidate(rekapKasirProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            keuangan.when(
              loading: () => const _LoadingBox(),
              error: (e, _) => _ErrorBox(
                  message: e is ApiException ? e.message : 'Gagal memuat keuangan.'),
              data: (k) => _KeuanganCards(k: k),
            ),
            const SizedBox(height: 24),
            Text('Penjualan Harian',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            harian.when(
              loading: () => const _LoadingBox(),
              error: (e, _) => _ErrorBox(
                  message: e is ApiException ? e.message : 'Gagal memuat penjualan.'),
              data: (rows) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Belum ada penjualan.')),
                    )
                  : Column(
                      children: [
                        for (final r in rows)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(fmtTanggal(r.tanggal),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${r.jumlahTransaksi} transaksi'),
                              trailing: Text(fmtIDR(r.totalOmzet),
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            Text('Rekap Kasir',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            rekap.when(
              loading: () => const _LoadingBox(),
              error: (e, _) => _ErrorBox(
                  message: e is ApiException ? e.message : 'Gagal memuat rekap kasir.'),
              data: (rows) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Belum ada sesi kasir.')),
                    )
                  : Column(
                      children: [for (final s in rows) _RekapKasirTile(sesi: s)],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RekapKasirTile extends StatelessWidget {
  const _RekapKasirTile({required this.sesi});
  final SesiRekap sesi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buka = sesi.isBuka;
    final selisih = sesi.selisih;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.circle,
            size: 10, color: buka ? AppColors.success : cs.onSurface.withValues(alpha: 0.35)),
        title: Text(sesi.nomor, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${sesi.kasir} · ${sesi.jumlahTransaksi} trx · ${fmtTanggal(sesi.waktuBuka)}'
          '${!buka && selisih != null && selisih != 0 ? ' · selisih ${fmtIDR(selisih)}' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              color: (!buka && selisih != null && selisih != 0)
                  ? AppColors.danger
                  : cs.onSurface.withValues(alpha: 0.6)),
        ),
        trailing: Text(fmtIDR(sesi.totalPenjualan),
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _KeuanganCards extends StatelessWidget {
  const _KeuanganCards({required this.k});
  final LaporanKeuangan k;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatTile(label: 'Omzet (bulan ini)', value: fmtIDR(k.omset), color: AppColors.mint600),
        _StatTile(label: 'Transaksi', value: '${k.jumlahTransaksi}', color: AppColors.mint700),
        _StatTile(label: 'Pengeluaran', value: fmtIDR(k.pengeluaran), color: AppColors.warn),
        _StatTile(
          label: 'Laba',
          value: fmtIDR(k.laba),
          color: k.laba < 0 ? AppColors.danger : AppColors.success,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      );
}
