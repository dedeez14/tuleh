import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/states.dart';
import '../../../demo/demo_session.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../../sesi/domain/entities/sesi_rekap.dart';
import '../../domain/entities/laporan_keuangan.dart';
import '../../domain/entities/penjualan_hari.dart';
import '../../domain/laporan_teks.dart';
import '../providers/laporan_providers.dart';
import '../widgets/grafik_penjualan.dart';

/// Layar Laporan — omzet bulan berjalan sebagai angka utama, grafik omzet
/// harian, lalu tabel harian dan rekap kasir.
///
/// Urutannya sengaja: satu angka besar untuk pertanyaan "berapa bulan ini",
/// grafik untuk "naik atau turun", tabel untuk "hari mana persisnya".
class LaporanScreen extends ConsumerWidget {
  const LaporanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keuangan = ref.watch(laporanKeuanganProvider);
    final harian = ref.watch(penjualanHarianProvider);
    final rekap = ref.watch(rekapKasirProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          IconButton(
            tooltip: 'Bagikan ringkasan laporan',
            onPressed: keuangan.hasValue
                ? () => _bagikan(context, ref, keuangan.requireValue)
                : null,
            icon: const Icon(Icons.share_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackground(
        ombak: false,
        intensitas: 0.5,
        child: LebarKonten(child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(laporanKeuanganProvider);
            ref.invalidate(penjualanHarianProvider);
            ref.invalidate(rekapKasirProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              MunculBertahap(
                child: keuangan.when(
                  loading: () => const _KerangkaKotak(tinggi: 168),
                  error: (e, _) => KeadaanGagal(
                    error: e,
                    onUlangi: () => ref.invalidate(laporanKeuanganProvider),
                  ),
                  data: (k) => _RingkasanKeuangan(k: k),
                ),
              ),
              const SizedBox(height: 24),
              const MunculBertahap(
                urutan: 1,
                child: _JudulBagian(
                  teks: 'Omzet harian',
                  catatan: 'Delapan hari terakhir.',
                ),
              ),
              const SizedBox(height: 12),
              MunculBertahap(
                urutan: 2,
                child: harian.when(
                  loading: () => const _KerangkaKotak(tinggi: 208),
                  error: (e, _) => KeadaanGagal(
                    error: e,
                    onUlangi: () => ref.invalidate(penjualanHarianProvider),
                  ),
                  data: (rows) => rows.isEmpty
                      ? const KeadaanKosong(
                          ikon: Icons.show_chart_rounded,
                          judul: 'Belum ada penjualan',
                          detail: 'Grafik muncul setelah ada transaksi.',
                        )
                      : _KartuGrafik(rows: rows),
                ),
              ),
              const SizedBox(height: 24),
              const MunculBertahap(
                urutan: 3,
                child: _JudulBagian(teks: 'Rincian per hari'),
              ),
              const SizedBox(height: 10),
              harian.maybeWhen(
                data: (rows) => Column(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      MunculBertahap(
                        urutan: 4 + i,
                        child: _BarisHari(hari: rows[i]),
                      ),
                  ],
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              const MunculBertahap(
                urutan: 5,
                child: _JudulBagian(teks: 'Rekap kasir'),
              ),
              const SizedBox(height: 10),
              rekap.when(
                loading: () => const _KerangkaKotak(tinggi: 120),
                error: (e, _) => KeadaanGagal(
                  error: e,
                  onUlangi: () => ref.invalidate(rekapKasirProvider),
                ),
                data: (rows) => rows.isEmpty
                    ? const KeadaanKosong(
                        ikon: Icons.point_of_sale_outlined,
                        judul: 'Belum ada sesi kasir',
                        detail: 'Buka sesi kasir untuk mulai mencatat penjualan.',
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < rows.length; i++)
                            MunculBertahap(
                              urutan: 6 + i,
                              child: _BarisRekap(sesi: rows[i]),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// Bagikan ringkasan laporan sebagai teks (WhatsApp, catatan, e-mail).
/// Ditutup selama Mode Demo — sama dengan ekspor laporan di desktop, agar
/// angka contoh tidak beredar sebagai laporan sungguhan.
Future<void> _bagikan(BuildContext context, WidgetRef ref, LaporanKeuangan k) async {
  final messenger = ScaffoldMessenger.of(context);
  if (ref.read(demoSessionProvider).active) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Bagikan laporan tidak tersedia di Mode Demo.'),
      ));
    return;
  }
  final nama = ref.read(profilUsahaProvider).valueOrNull?.nama ?? 'Tuléh POS';
  final teks = laporanTeks(
    namaToko: nama,
    keuangan: k,
    harian: ref.read(penjualanHarianProvider).valueOrNull ?? const [],
    rekap: ref.read(rekapKasirProvider).valueOrNull ?? const [],
  );
  await SharePlus.instance.share(
    ShareParams(text: teks, subject: 'Laporan $nama · ${k.bulan}'),
  );
}

class _JudulBagian extends StatelessWidget {
  const _JudulBagian({required this.teks, this.catatan});
  final String teks;
  final String? catatan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          teks,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        if (catatan != null) ...[
          const SizedBox(height: 2),
          Text(
            catatan!,
            style: TextStyle(
              fontSize: 12.5,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}

/// Omzet bulan berjalan sebagai angka utama; tiga angka pendukung di bawahnya.
/// Hanya laba yang berwarna, karena tandanya bermakna (untung/rugi) — dan
/// disertai ikon panah agar tidak bergantung pada warna saja.
class _RingkasanKeuangan extends StatelessWidget {
  const _RingkasanKeuangan({required this.k});
  final LaporanKeuangan k;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final untung = k.laba >= 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OMZET BULAN INI',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 6),
          AngkaBerubah(
            nilai: k.omset,
            format: fmtIDR,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${k.jumlahTransaksi} transaksi · ${k.bulan}',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: cs.outline, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AngkaPendukung(
                  label: 'Pengeluaran',
                  nilai: fmtIDR(k.pengeluaran),
                ),
              ),
              Container(width: 1, height: 34, color: cs.outline),
              const SizedBox(width: 14),
              Expanded(
                child: _AngkaPendukung(
                  label: untung ? 'Laba' : 'Rugi',
                  nilai: fmtIDR(k.laba.abs()),
                  warna: untung ? AppColors.success : AppColors.danger,
                  // Ikon + label wajib: hijau & merah nyaris tak terbedakan
                  // bagi mata yang sulit membedakan warna.
                  ikon: untung
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AngkaPendukung extends StatelessWidget {
  const _AngkaPendukung({
    required this.label,
    required this.nilai,
    this.warna,
    this.ikon,
  });

  final String label;
  final String nilai;
  final Color? warna;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: 3),
        Row(
          children: [
            if (ikon != null) ...[
              Icon(ikon, size: 16, color: warna),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                nilai,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: warna ?? cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KartuGrafik extends StatelessWidget {
  const _KartuGrafik({required this.rows});
  final List<PenjualanHari> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: GrafikPenjualan(rows: rows),
    );
  }
}

/// Tabel harian — pasangan angka penuh untuk grafik di atasnya.
class _BarisHari extends StatelessWidget {
  const _BarisHari({required this.hari});
  final PenjualanHari hari;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kosong = hari.jumlahTransaksi == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtTanggal(hari.tanggal),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  kosong ? 'Tidak ada transaksi' : '${hari.jumlahTransaksi} transaksi',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Text(
            fmtIDR(hari.totalOmzet),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: kosong ? cs.onSurface.withValues(alpha: 0.45) : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarisRekap extends StatelessWidget {
  const _BarisRekap({required this.sesi});
  final SesiRekap sesi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buka = sesi.isBuka;
    final selisih = sesi.selisih;
    final adaSelisih = !buka && selisih != null && selisih != 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      sesi.nomor,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    // Status ditandai teks, bukan sekadar titik berwarna.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: buka
                            ? AppColors.success.withValues(alpha: 0.13)
                            : cs.onSurface.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        buka ? 'Buka' : 'Tutup',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: buka
                              ? AppColors.success
                              : cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${sesi.kasir} · ${sesi.jumlahTransaksi} transaksi · '
                  '${fmtTanggal(sesi.waktuBuka)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                if (adaSelisih) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        selisih < 0
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        size: 13,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Selisih kas ${fmtIDR(selisih.abs())}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            fmtIDR(sesi.totalPenjualan),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _KerangkaKotak extends StatelessWidget {
  const _KerangkaKotak({required this.tinggi});
  final double tinggi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: tinggi,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Kerangka(tinggi: 12, lebar: 130),
          SizedBox(height: 12),
          Kerangka(tinggi: 26, lebar: 200),
          SizedBox(height: 10),
          Kerangka(tinggi: 11, lebar: 150),
        ],
      ),
    );
  }
}
