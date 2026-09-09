import '../../../../core/utils/satuan_terukur.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/offline/koneksi.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../cetak/presentation/aksi_struk.dart';
import '../../../demo/demo_session.dart';
import '../../../laporan/presentation/providers/laporan_providers.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../../products/presentation/providers/products_provider.dart';
import '../../../sesi/presentation/providers/sesi_providers.dart';
import '../../domain/entities/transaksi_detail.dart';
import '../providers/riwayat_providers.dart';

/// Layar Detail Transaksi — tampilan struk dari `/transaksi/{id}`.
class DetailTransaksiScreen extends ConsumerWidget {
  const DetailTransaksiScreen({super.key, required this.id, this.tertanam = false});

  final String id;

  /// true = ditampilkan di panel kanan layar Riwayat (tablet), tanpa AppBar.
  final bool tertanam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(transaksiDetailProvider(id));
    final d = detail.valueOrNull;
    final bisaAksi = d != null && (d.status?.toUpperCase() != 'DIBATALKAN');
    // Pembatalan hanya untuk transaksi yang sudah tercatat di server dan saat
    // online — struk lokal (belum sinkron) dibatalkan lewat layar Sinkronisasi.
    final lokal = id.startsWith(awalanIdLokal);
    final online = ref.watch(koneksiProvider.select((s) => s.online));
    final bisaBatal = bisaAksi && !lokal;

    final isi = detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              e is ApiException ? e.message : 'Gagal memuat detail.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Receipt(d: d),
            if (bisaAksi) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => bagikanStruk(context, _struk(ref, d)),
                      icon: const Icon(Icons.share_outlined, size: 19),
                      label: const Text('Bagikan'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => cetakStrukDenganUmpanBalik(context, ref, _struk(ref, d)),
                      icon: const Icon(Icons.print_rounded, size: 19),
                      label: const Text('Cetak ulang'),
                    ),
                  ),
                ],
              ),
            ],
            if (bisaBatal) ...[
              const SizedBox(height: 10),
              _TombolBatal(
                aktif: online,
                onTekan: () => _konfirmasiBatal(context, ref, d),
              ),
            ],
          ],
        ),
      );

    if (tertanam) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: isi),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Transaksi')),
      body: isi,
    );
  }
}

/// Tombol "Batalkan transaksi" — merah garis tepi, nonaktif saat offline
/// dengan keterangan sebabnya (pembatalan tidak diantrekan).
class _TombolBatal extends StatelessWidget {
  const _TombolBatal({required this.aktif, required this.onTekan});

  final bool aktif;
  final VoidCallback onTekan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: aktif ? onTekan : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(color: AppColors.danger.withValues(alpha: aktif ? 0.6 : 0.25)),
          ),
          icon: const Icon(Icons.cancel_outlined, size: 19),
          label: const Text('Batalkan transaksi'),
        ),
        if (!aktif)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Pembatalan hanya bisa dilakukan saat terhubung ke internet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _konfirmasiBatal(BuildContext context, WidgetRef ref, TransaksiDetail d) async {
  final ya = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Batalkan transaksi ini?'),
      content: Text(
        'Transaksi ${d.nomor} (${fmtIDR(d.grandTotal)}) akan dibatalkan — stok barang '
        'dikembalikan ke gudang dan penjualannya dihapus dari laporan. '
        'Tindakan ini tidak dapat diurungkan.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Ya, batalkan'),
        ),
      ],
    ),
  );
  if (ya != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final hasil = await ref.read(riwayatRepositoryProvider).batal(d.id);
  hasil.when(
    ok: (_) {
      ref.invalidate(transaksiDetailProvider(d.id));
      ref.invalidate(riwayatListProvider);
      // Stok kembali ke gudang dan penjualannya keluar dari rekap: layar lain
      // harus ikut menyegarkan, kalau tidak kasir melihat angka yang batal.
      ref.invalidate(activeSesiProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(produkKelolaProvider);
      ref.invalidate(laporanKeuanganProvider);
      ref.invalidate(penjualanProdukProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Transaksi ${d.nomor} dibatalkan.'),
        ));
    },
    err: (e) {
      // 409 "sudah dibatalkan" → segarkan detail agar tombol ikut hilang.
      if (e.statusCode == 409) ref.invalidate(transaksiDetailProvider(d.id));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(e.firstError() ?? e.message),
        ));
    },
  );
}

/// Struk untuk cetak ulang/bagikan, dibangun dari detail server + profil
/// usaha saat ini (logo & catatan kaki mengikuti pengaturan terbaru).
Struk _struk(WidgetRef ref, TransaksiDetail d) {
  final usaha = ref.read(profilUsahaProvider).valueOrNull;
  final tunai = (d.tipePembayaran ?? '').toUpperCase() == 'TUNAI';
  return Struk(
    namaToko: usaha?.nama ?? 'Tuléh POS',
    alamat: usaha?.alamat,
    telepon: usaha?.telepon,
    nomor: d.nomor,
    waktu: DateTime.tryParse(d.tanggal ?? '') ?? DateTime.now(),
    kasir: d.kasir,
    baris: [
      for (final it in d.items)
        StrukBaris(
          nama: it.nama,
          kuantitas: it.kuantitas,
          harga: it.harga,
          satuan: apakahTerukur(it.satuan) ? it.satuan : null,
        ),
    ],
    total: d.grandTotal,
    metode: d.tipePembayaran,
    dibayar: tunai ? d.dibayar : null,
    kembalian: tunai ? d.kembalian : null,
    catatanKaki: usaha?.strukFooter,
    barcode: d.nomor,
    logoUrl: (usaha?.strukTampilLogo ?? false) ? usaha?.logo : null,
    demo: ref.read(demoSessionProvider).active,
    pelanggan: d.pelanggan,
    diskon: d.totalDiskon > 0 ? d.totalDiskon : null,
  );
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.d});
  final TransaksiDetail d;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(d.nomor,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Center(child: Text(fmtTanggal(d.tanggal))),
            const SizedBox(height: 12),
            _kv('Kasir', d.kasir),
            _kv('Pelanggan', d.pelanggan),
            _kv('Pembayaran', d.tipePembayaran),
            _kv('Status', d.status),
            const _Dashed(),
            for (final it in d.items) _ItemRow(item: it),
            const _Dashed(),
            _row('Subtotal', fmtIDR(d.subtotal)),
            if (d.totalDiskon > 0) _row('Diskon', '−${fmtIDR(d.totalDiskon)}'),
            if (d.totalPajak > 0) _row('Pajak', fmtIDR(d.totalPajak)),
            const SizedBox(height: 4),
            _row('TOTAL', fmtIDR(d.grandTotal), bold: true),
            _row('Dibayar', fmtIDR(d.dibayar)),
            _row('Kembalian', fmtIDR(d.kembalian)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String? v) {
    if (v == null || v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          Text(v),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                    fontSize: bold ? 16 : 14)),
            Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: bold ? 16 : 14)),
          ],
        ),
      );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final TrxItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${labelKuantitas(item.kuantitas, item.satuan)} × ${fmtIDR(item.harga)}',
                  style: const TextStyle(color: Colors.grey)),
              Text(fmtIDR(item.subtotal)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dashed extends StatelessWidget {
  const _Dashed();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(style: BorderStyle.solid, color: Colors.black12)),
          ),
          child: SizedBox(height: 1, width: double.infinity),
        ),
      );
}
