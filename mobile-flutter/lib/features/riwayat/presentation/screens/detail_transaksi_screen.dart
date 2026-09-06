import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/format.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../cetak/presentation/aksi_struk.dart';
import '../../../demo/demo_session.dart';
import '../../../pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../domain/entities/transaksi_detail.dart';
import '../providers/riwayat_providers.dart';

/// Layar Detail Transaksi — tampilan struk dari `/transaksi/{id}`.
class DetailTransaksiScreen extends ConsumerWidget {
  const DetailTransaksiScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(transaksiDetailProvider(id));
    final d = detail.valueOrNull;
    final bisaAksi = d != null && (d.status?.toUpperCase() != 'DIBATALKAN');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Bagikan struk',
            onPressed: bisaAksi ? () => bagikanStruk(context, _struk(ref, d)) : null,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Cetak ulang',
            onPressed: bisaAksi ? () => cetakStrukDenganUmpanBalik(context, ref, _struk(ref, d)) : null,
            icon: const Icon(Icons.print_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: detail.when(
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
          children: [_Receipt(d: d)],
        ),
      ),
    );
  }
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
        StrukBaris(nama: it.nama, kuantitas: it.kuantitas, harga: it.harga),
    ],
    total: d.grandTotal,
    metode: d.tipePembayaran,
    dibayar: tunai ? d.dibayar : null,
    kembalian: tunai ? d.kembalian : null,
    catatanKaki: usaha?.strukFooter,
    barcode: d.nomor,
    logoUrl: (usaha?.strukTampilLogo ?? false) ? usaha?.logo : null,
    demo: ref.read(demoSessionProvider).active,
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
              Text('${item.kuantitas.toInt()} × ${fmtIDR(item.harga)}',
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
