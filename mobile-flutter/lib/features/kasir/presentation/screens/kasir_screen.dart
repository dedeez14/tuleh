import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/products_provider.dart';
import '../../../sesi/presentation/providers/sesi_providers.dart';
import '../../../sesi/presentation/widgets/buka_sesi_dialog.dart';
import '../controllers/cart_controller.dart';
import '../providers/checkout_providers.dart';

/// Layar Kasir — katalog + pencarian, keranjang, checkout tunai.
class KasirScreen extends ConsumerStatefulWidget {
  const KasirScreen({super.key});

  @override
  ConsumerState<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends ConsumerState<KasirScreen> {
  final _queryCtrl = TextEditingController();

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {});
    ref.read(productQueryProvider.notifier).state = value;
  }

  void _clearQuery() {
    _queryCtrl.clear();
    _onQueryChanged('');
    FocusScope.of(context).unfocus();
  }

  void _openCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CartSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final count = ref.watch(cartCountProvider);
    final total = ref.watch(cartTotalProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir'),
        actions: [
          if (count > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Buka keranjang',
                    onPressed: _openCart,
                    icon: const Icon(Icons.shopping_cart_outlined),
                  ),
                  Positioned(
                    right: 3,
                    top: 3,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          const _SesiBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _queryCtrl,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Cari produk / barcode...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _queryCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: _clearQuery,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                message: e is ApiException ? e.message : 'Gagal memuat produk.',
                onRetry: () => ref.invalidate(productsProvider),
              ),
              data: (list) => list.isEmpty
                  ? const _EmptyView()
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        count == 0 ? 20 : 112,
                      ),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ProductTile(
                        product: list[i],
                        onAdd: () => ref
                            .read(cartControllerProvider.notifier)
                            .add(list[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: count == 0
          ? null
          : _CartBar(count: count, total: total, onTap: _openCart),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onAdd});

  final Product product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = <String>[
      if (product.satuan != null && product.satuan!.isNotEmpty)
        'Satuan ${product.satuan}',
      if (product.stok != null) 'Stok ${product.stok!.toInt()}',
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.nama,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fmtIDR(product.harga),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                    if (info.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        info.join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 18),
                    SizedBox(width: 4),
                    Text('Tambah'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.count,
    required this.total,
    required this.onTap,
  });
  final int count;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onPressed: onTap,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mint900.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count item',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Lihat keranjang',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 11)),
                  Text(
                    fmtIDR(total),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartSheet extends ConsumerStatefulWidget {
  const _CartSheet();
  @override
  ConsumerState<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<_CartSheet> {
  bool _loading = false;

  Future<void> _checkout() async {
    final items = ref.read(cartControllerProvider);
    final total = ref.read(cartTotalProvider);
    if (items.isEmpty) return;
    setState(() => _loading = true);
    try {
      final payload = [
        for (final e in items)
          {
            'id_produk': e.product.id,
            'kuantitas': e.qty,
            'harga': e.product.harga,
          },
      ];
      final res = await ref
          .read(transactionDataSourceProvider)
          .checkout(items: payload, metode: 'TUNAI', dibayar: total);
      ref.read(cartControllerProvider.notifier).clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              'Transaksi berhasil${res.nomor.isNotEmpty ? ' · ${res.nomor}' : ''}',
            ),
          ),
        );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(e.firstError() ?? e.message),
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartControllerProvider);
    final total = ref.watch(cartTotalProvider);
    final cart = ref.read(cartControllerProvider.notifier);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Keranjang',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (items.isNotEmpty)
                    TextButton.icon(
                      onPressed: _loading ? null : cart.clear,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Kosongkan'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Expanded(child: Center(child: Text('Keranjang kosong.')))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      it.product.nama,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      fmtIDR(it.subtotal),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () =>
                                    cart.setQty(it.product.id, it.qty - 1),
                              ),
                              SizedBox(
                                width: 30,
                                child: Text(
                                  '${it.qty}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () =>
                                    cart.setQty(it.product.id, it.qty + 1),
                              ),
                              IconButton(
                                tooltip: 'Hapus item',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => cart.remove(it.product.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    fmtIDR(total),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading || items.isEmpty ? null : _checkout,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.mint900,
                        ),
                      )
                    : const Text('Bayar Tunai'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text('Belum ada produk di toko ini.', textAlign: TextAlign.center),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    ),
  );
}

/// Banner peringatan bila sesi kasir belum dibuka (checkout butuh sesi aktif).
class _SesiBanner extends ConsumerWidget {
  const _SesiBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesi = ref.watch(activeSesiProvider);
    if (sesi.isLoading || sesi.valueOrNull != null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.warn, size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('Sesi kasir belum dibuka.')),
          TextButton(
            onPressed: () => _showBukaSesi(context, ref),
            child: const Text('Buka Sesi'),
          ),
        ],
      ),
    );
  }
}

Future<void> _showBukaSesi(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context); // sebelum async gap
  final modal = await showBukaSesiDialog(context);
  if (modal == null) return;
  try {
    await ref.read(activeSesiProvider.notifier).buka(modal);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Sesi kasir dibuka.'),
        ),
      );
  } on ApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(e.firstError() ?? e.message),
        ),
      );
  }
}
