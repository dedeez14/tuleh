import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
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
    final products = ref.watch(productsProvider);

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
      body: Column(
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
                      onRefresh: () async => ref.invalidate(productsProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _Tile(product: list[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final stok = product.stok;
    final habis = stok != null && stok <= 0;
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
        trailing: stok == null
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (habis ? AppColors.danger : AppColors.mint600)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Stok ${stok.toInt()}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: habis ? AppColors.danger : AppColors.mint700)),
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
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _tambahStok(context, ref),
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Tambah Stok'),
                  ),
                ),
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
      await ref
          .read(inventoryDataSourceProvider)
          .stokMasuk(idProduk: product.id, jumlah: jumlah);
      ref.invalidate(productsProvider);
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.success,
            content: Text('Stok +${jumlah.toInt()} ditambahkan.')));
    } on ApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(e.firstError() ?? e.message)));
    }
  }
}
