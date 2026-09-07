import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/entities/transaksi.dart';
import '../providers/riwayat_providers.dart';
import 'detail_transaksi_screen.dart';

/// Riwayat transaksi — dikelompokkan per hari dengan subtotal, karena
/// pertanyaan kasir biasanya "tadi siang jam berapa" dan "hari ini total
/// berapa", bukan menelusuri deretan nomor nota.
class RiwayatScreen extends ConsumerStatefulWidget {
  const RiwayatScreen({super.key});

  @override
  ConsumerState<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends ConsumerState<RiwayatScreen> {
  /// Transaksi yang dibuka di panel kanan (tablet). Di ponsel detail dibuka
  /// sebagai layar sendiri.
  String? _terpilihId;

  void _buka(BuildContext context, Transaksi trx) {
    if (layarLebar(context)) {
      setState(() => _terpilihId = trx.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DetailTransaksiScreen(id: trx.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final riwayat = ref.watch(riwayatListProvider);
    final lebar = layarLebar(context);

    final daftar = RefreshIndicator(
          onRefresh: () async => ref.invalidate(riwayatListProvider),
          child: riwayat.when(
            loading: () => const DaftarKerangka(jumlah: 7, tinggiBaris: 72),
            error: (e, _) => ListView(
              children: [
                KeadaanGagal(
                  error: e,
                  onUlangi: () => ref.invalidate(riwayatListProvider),
                ),
              ],
            ),
            data: (list) => list.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 60),
                      KeadaanKosong(
                        ikon: Icons.receipt_long_outlined,
                        judul: 'Belum ada transaksi',
                        detail: 'Transaksi dari kasir akan tercatat di sini.',
                      ),
                    ],
                  )
                : _DaftarPerHari(
                    list: list,
                    terpilihId: lebar ? _terpilihId : null,
                    onBuka: (t) => _buka(context, t),
                  ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat')),
      body: AppBackground(
        ombak: false,
        intensitas: 0.45,
        child: lebar
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 420, child: daftar),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _terpilihId == null
                        ? const KeadaanKosong(
                            ikon: Icons.receipt_long_outlined,
                            judul: 'Pilih transaksi',
                            detail: 'Detail struk tampil di sini.',
                          )
                        : DetailTransaksiScreen(
                            key: ValueKey(_terpilihId),
                            id: _terpilihId!,
                            tertanam: true,
                          ),
                  ),
                ],
              )
            : daftar,
      ),
    );
  }
}

class _DaftarPerHari extends StatelessWidget {
  const _DaftarPerHari({required this.list, required this.onBuka, this.terpilihId});
  final List<Transaksi> list;
  final ValueChanged<Transaksi> onBuka;
  final String? terpilihId;

  @override
  Widget build(BuildContext context) {
    // Kelompokkan per tanggal (yyyy-mm-dd); hari terbaru di atas, dan di
    // dalam satu hari transaksi terbaru di atas.
    final kelompok = <String, List<Transaksi>>{};
    for (final t in list) {
      final tgl = _tanggalSaja(t.tanggal);
      kelompok.putIfAbsent(tgl, () => []).add(t);
    }
    for (final trx in kelompok.values) {
      trx.sort((a, b) => (b.tanggal ?? '').compareTo(a.tanggal ?? ''));
    }

    final anak = <Widget>[];
    var urut = 0;
    kelompok.forEach((tgl, trx) {
      final total = trx
          .where((t) => !_dibatalkan(t))
          .fold<double>(0, (s, t) => s + t.grandTotal);
      anak.add(
        MunculBertahap(
          urutan: urut++,
          child: _KepalaHari(
            label: _labelHari(tgl),
            jumlah: trx.length,
            total: total,
          ),
        ),
      );
      anak.add(
        MunculBertahap(
          urutan: urut++,
          child: _KartuHari(trx: trx, onBuka: onBuka, terpilihId: terpilihId),
        ),
      );
      anak.add(const SizedBox(height: 18));
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: anak,
    );
  }

  static String _tanggalSaja(String? iso) {
    if (iso == null || iso.length < 10) return '';
    return iso.substring(0, 10);
  }

  static bool _dibatalkan(Transaksi t) =>
      (t.status ?? '').toUpperCase().contains('BATAL');

  static String _labelHari(String tgl) {
    final d = DateTime.tryParse(tgl);
    if (d == null) return tgl.isEmpty ? 'Tanpa tanggal' : tgl;
    final now = DateTime.now();
    final hariIni = DateTime(now.year, now.month, now.day);
    final itu = DateTime(d.year, d.month, d.day);
    final selisih = hariIni.difference(itu).inDays;
    if (selisih == 0) return 'Hari ini';
    if (selisih == 1) return 'Kemarin';
    return fmtTanggal(tgl);
  }
}

class _KepalaHari extends StatelessWidget {
  const _KepalaHari({
    required this.label,
    required this.jumlah,
    required this.total,
  });

  final String label;
  final int jumlah;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$jumlah transaksi',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Text(
            fmtIDR(total),
            style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
          ),
        ],
      ),
    );
  }
}

/// Satu kartu per hari berisi baris-baris transaksi — lebih ringan daripada
/// satu kartu per transaksi, dan batas harinya jelas.
class _KartuHari extends StatelessWidget {
  const _KartuHari({required this.trx, required this.onBuka, this.terpilihId});
  final List<Transaksi> trx;
  final ValueChanged<Transaksi> onBuka;
  final String? terpilihId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < trx.length; i++) ...[
            _BarisTrx(
              trx: trx[i],
              terpilih: trx[i].id == terpilihId,
              onTap: () => onBuka(trx[i]),
            ),
            if (i < trx.length - 1)
              Divider(height: 1, color: cs.outline, indent: 62),
          ],
        ],
      ),
    );
  }
}

class _BarisTrx extends StatelessWidget {
  const _BarisTrx({required this.trx, required this.onTap, this.terpilih = false});
  final Transaksi trx;
  final VoidCallback onTap;
  final bool terpilih;

  static IconData _ikonMetode(String? m) => switch ((m ?? '').toUpperCase()) {
    'QRIS' => Icons.qr_code_2_rounded,
    'TRANSFER' => Icons.account_balance_outlined,
    'TUNAI' => Icons.payments_outlined,
    _ => Icons.receipt_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final batal = (trx.status ?? '').toUpperCase().contains('BATAL');
    final tertunda = trx.status == statusBelumSinkron;
    final jam = _jam(trx.tanggal);

    return ListTile(
      onTap: onTap,
      selected: terpilih,
      selectedTileColor: cs.primary.withValues(alpha: 0.08),
      leading: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: batal
              ? cs.error.withValues(alpha: 0.10)
              : cs.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          batal
              ? Icons.cancel_outlined
              : tertunda
              ? Icons.cloud_upload_outlined
              : _ikonMetode(trx.metode),
          size: 20,
          color: batal
              ? cs.error
              : tertunda
              ? AppColors.warn
              : cs.primary,
        ),
      ),
      title: Text(
        trx.nomor,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          decoration: batal ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        [
          if (jam.isNotEmpty) jam,
          if (trx.metode != null && trx.metode!.isNotEmpty) trx.metode!,
          if (batal) 'Dibatalkan',
          if (tertunda) 'Belum tersinkron',
        ].join(' · '),
        style: TextStyle(
          fontSize: 12.5,
          color: batal
              ? cs.error
              : tertunda
              ? AppColors.warn
              : cs.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: Text(
        fmtIDR(trx.grandTotal),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: batal ? cs.onSurface.withValues(alpha: 0.45) : cs.onSurface,
          decoration: batal ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }

  /// "14:05" dari ISO; kosong bila tanggal tak memuat jam — termasuk bentuk
  /// server MOVERA "2026-09-05T00:00:00+07:00" (tanggal saja, jam 00:00
  /// bukan waktu transaksi sebenarnya).
  static String _jam(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null || (iso!.length <= 10)) return '';
    final lokal = d.isUtc ? d.toLocal() : d;
    if (lokal.hour == 0 && lokal.minute == 0 && lokal.second == 0) return '';
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${dua(lokal.hour)}:${dua(lokal.minute)}';
  }
}

