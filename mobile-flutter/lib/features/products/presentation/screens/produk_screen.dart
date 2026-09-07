import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../domain/entities/product.dart';
import '../providers/products_provider.dart';
import 'product_form_sheet.dart';

/// Layar Produk — katalog toko (lihat harga & stok). Tap untuk detail + tambah stok.
class ProdukScreen extends ConsumerWidget {
  const ProdukScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(produkKelolaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Produk')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const ProductFormSheet(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
      ),
      body: LebarKonten(child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => ref.read(productQueryProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'Cari produk / barcode…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(e is ApiException ? e.message : 'Gagal memuat produk.',
                      textAlign: TextAlign.center),
                ),
              ),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('Belum ada produk.'))
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(produkKelolaProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _Tile(product: list[i]),
                      ),
                    ),
            ),
          ),
        ],
      )),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.product});
  final Product product;

  bool get _jasa => (product.tipe ?? '').toUpperCase() == 'JASA';

  @override
  Widget build(BuildContext context) {
    final stok = product.stok;
    final habis = !_jasa && stok != null && stok <= 0;
    final menipis = !_jasa && stok != null && stok > 0 && stok <= 5;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () async {
          final action = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (_) => _Detail(product: product),
          );
          if (action == 'edit' && context.mounted) {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => ProductFormSheet(product: product),
            );
          }
        },
        title: Text(product.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          fmtIDR(product.harga),
          if (product.satuan != null) '/ ${product.satuan}',
          if (product.kategori != null) '· ${product.kategori}',
        ].join(' ')),
        // Jasa tidak punya stok: sebelumnya tampil "Stok 0" merah seolah habis,
        // menyesatkan pemilik toko. Kini jasa berlencana "Jasa", barang
        // berlencana stok dengan warna habis/menipis/aman.
        trailing: _jasa
            ? _Lencana(teks: 'Jasa', warna: AppColors.mint700, ikon: Icons.handyman_outlined)
            : stok == null
                ? null
                : _Lencana(
                    teks: habis ? 'Habis' : 'Stok ${stok.toInt()}',
                    warna: habis
                        ? AppColors.danger
                        : menipis
                            ? AppColors.warn
                            : AppColors.mint700,
                  ),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(product.nama,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(fmtIDR(product.harga),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.mint600)),
            const SizedBox(height: 16),
            _kv('Satuan', product.satuan),
            _kv('Kategori', product.kategori),
            _kv('Barcode', product.barcode),
            if ((product.tipe ?? '').toUpperCase() != 'JASA')
              _kv('Stok', product.stok?.toInt().toString()),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop('edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                // Tambah stok tidak relevan untuk jasa.
                if ((product.tipe ?? '').toUpperCase() != 'JASA') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _tambahStok(context, ref),
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Tambah Stok'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.grey)),
            Text((v == null || v.isEmpty) ? '—' : v,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Future<void> _tambahStok(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tambah Stok — ${product.nama}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Jumlah masuk'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    final jumlah = double.tryParse(ctrl.text.trim()) ?? 0;
    ctrl.dispose();
    if (confirmed != true || jumlah <= 0) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // Offline → diantrekan; stok tampil langsung naik lewat delta tertunda.
      final hasil = await ref.read(antreanTulisProvider).jalankan(
        jenis: 'STOK_MASUK',
        path: '/inventory/stok-masuk',
        body: {'id_produk': product.id, 'jumlah': jumlah},
        kirim: ref.read(inventoryDataSourceProvider).stokMasukBody,
        deltaStok: {product.id: jumlah},
      );
      if (hasil.tertunda) ref.read(antreanVersiProvider.notifier).state++;
      ref.invalidate(produkKelolaProvider);
      ref.invalidate(productsProvider);
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: hasil.tertunda ? AppColors.warn : AppColors.success,
            content: Text(hasil.tertunda
                ? 'Offline — stok +${jumlah.toInt()} disimpan, dikirim saat internet kembali.'
                : 'Stok +${jumlah.toInt()} ditambahkan.')));
    } on ApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(e.firstError() ?? e.message)));
    }
  }
}

class _Lencana extends StatelessWidget {
  const _Lencana({required this.teks, required this.warna, this.ikon});
  final String teks;
  final Color warna;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: warna.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ikon != null) ...[
              Icon(ikon, size: 13, color: warna),
              const SizedBox(width: 4),
            ],
            Text(teks,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: warna)),
          ],
        ),
      );
}
