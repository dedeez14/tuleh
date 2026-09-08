// Bagian dari lembar keranjang (cart_sheet.dart), dipisah agar tiap berkas
// tetap di bawah batas ukuran dan mudah dibaca sendiri-sendiri.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/format.dart';
import '../controllers/cart_controller.dart';

class DaftarItemKeranjang extends ConsumerWidget {
  const DaftarItemKeranjang({super.key, required this.onUbah, required this.onHapus, this.tambahan});

  final void Function(String id, int qty) onUbah;
  final void Function(String id) onHapus;

  /// Kartu di bawah daftar item (pelanggan, diskon, catatan).
  final Widget? tambahan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartControllerProvider);
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      itemCount: items.length + (tambahan == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i == items.length) return tambahan!;
        final it = items[i];
        return Dismissible(
          key: ValueKey(it.product.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => onHapus(it.product.id),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 18),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.delete_outline_rounded, color: cs.error),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.product.nama,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${fmtIDR(it.product.harga)} × ${it.qty}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fmtIDR(it.subtotal),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                PengaturJumlahKeranjang(
                  qty: it.qty,
                  onUbah: (n) => onUbah(it.product.id, n),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pelanggan, diskon transaksi, dan catatan — opsional, di bawah daftar item.

class PengaturJumlahKeranjang extends StatelessWidget {
  const PengaturJumlahKeranjang({super.key, required this.qty, required this.onUbah});

  final int qty;
  final ValueChanged<int> onUbah;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: qty == 1 ? 'Hapus' : 'Kurangi',
            onPressed: () {
              onUbah(qty - 1);
              HapticFeedback.selectionClick();
            },
            icon: Icon(
              qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
              size: 19,
              color: cs.primary,
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: cs.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Tambah',
            onPressed: () {
              onUbah(qty + 1);
              HapticFeedback.selectionClick();
            },
            icon: Icon(Icons.add_rounded, size: 19, color: cs.primary),
          ),
        ],
      ),
    );
  }
}
