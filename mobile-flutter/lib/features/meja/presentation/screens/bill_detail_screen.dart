import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/rupiah_input.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/offline/pengurai.dart';
import '../../../../core/offline/rujukan_lokal.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/products_provider.dart';
import '../../domain/entities/bill_detail.dart';
import '../providers/meja_providers.dart';

/// Detail bon meja — lihat item, tambah pesanan (ronde), bayar (settle).
class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({super.key, required this.billId, required this.mejaNomor});

  final String billId;
  final String mejaNomor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(billDetailProvider(billId));
    return Scaffold(
      appBar: AppBar(title: Text('Meja $mejaNomor')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(e is ApiException ? e.message : 'Gagal memuat bon.',
                textAlign: TextAlign.center),
          ),
        ),
        data: (b) => _Body(billId: billId, bill: b),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.billId, required this.bill});
  final String billId;
  final BillDetail bill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bill.nomor,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  if (bill.pax != null) Text('${bill.pax} org', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
                ],
              ),
              if (adalahRujukanLokal(billId))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Bon dibuka saat offline. Pesanan & pembayaran disimpan di ponsel dan '
                    'dikirim berurutan begitu online.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.warn, height: 1.4),
                  ),
                ),
              const Divider(height: 24),
              if (bill.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Belum ada pesanan. Tekan "Tambah Pesanan".')),
                )
              else
                for (final it in bill.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${it.kuantitas.toInt()} × ${fmtIDR(it.harga ?? 0)}',
                                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                            ],
                          ),
                        ),
                        Text(fmtIDR(it.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(fmtIDR(bill.total),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.mint600)),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => _AddPesananSheet(billId: billId),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah Pesanan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: bill.total <= 0 ? null : () => _bayar(context, ref, bill.total),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Bayar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _bayar(BuildContext context, WidgetRef ref, double total) async {
    final ctrl = TextEditingController(text: total.toInt().toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bayar Tunai'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total ${fmtIDR(total)}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Uang diterima', prefixText: 'Rp '),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bayar')),
        ],
      ),
    );
    final dibayar = ctrl.text.trim().isEmpty ? total : parseRupiah(ctrl.text);
    ctrl.dispose();
    if (ok != true || !context.mounted) return;
    final r = await ref.read(mejaRepositoryProvider).bayar(billId, tipe: 'TUNAI', dibayar: dibayar);
    if (!context.mounted) return;
    r.when(
      ok: (h) {
        if (h.tertunda) ref.read(antreanVersiProvider.notifier).state++;
        ref.invalidate(mejaPetaProvider);
        Navigator.of(context).pop(); // kembali ke peta
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: h.tertunda ? AppColors.warn : AppColors.success,
              content: Text(h.tertunda
                  ? 'Bon ditutup offline — pembayaran dikirim saat online.'
                  : 'Bon dibayar & ditutup.')));
      },
      err: (e) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message))),
    );
  }
}

/// Sheet pilih produk → kirim sebagai ronde ke bon.
class _AddPesananSheet extends ConsumerStatefulWidget {
  const _AddPesananSheet({required this.billId});
  final String billId;

  @override
  ConsumerState<_AddPesananSheet> createState() => _AddPesananSheetState();
}

class _AddPesananSheetState extends ConsumerState<_AddPesananSheet> {
  final Map<String, int> _qty = {}; // productId → qty
  final Map<String, Product> _prod = {};
  bool _loading = false;

  int get _count => _qty.values.fold(0, (s, q) => s + q);

  Future<void> _kirim() async {
    if (_count == 0) return;
    setState(() => _loading = true);
    final items = [
      for (final e in _qty.entries)
        if (e.value > 0) {'id_produk': e.key, 'kuantitas': e.value},
    ];
    // Nama & harga hanya untuk tampilan selama belum terkirim (offline).
    final tampilan = [
      for (final e in _qty.entries)
        if (e.value > 0)
          {
            'id_produk': e.key,
            'nama': _prod[e.key]?.nama ?? '-',
            'harga': _prod[e.key]?.harga ?? 0,
            'kuantitas': e.value,
            'kelola_stok': _prod[e.key]?.stok != null,
          },
    ];
    final r = await ref
        .read(mejaRepositoryProvider)
        .tambahRonde(widget.billId, items, tampilan: tampilan);
    if (!mounted) return;
    r.when(
      ok: (h) {
        if (h.tertunda) ref.read(antreanVersiProvider.notifier).state++;
        ref.invalidate(billDetailProvider(widget.billId));
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: h.tertunda ? AppColors.warn : AppColors.success,
              content: Text(h.tertunda
                  ? '$_count item disimpan offline — dikirim ke dapur saat online.'
                  : '$_count item dikirim ke dapur.')));
      },
      err: (e) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Tambah Pesanan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: products.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(e is ApiException ? e.message : 'Gagal memuat produk.')),
                data: (list) => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final p = list[i];
                    _prod[p.id] = p;
                    final q = _qty[p.id] ?? 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.nama),
                      subtitle: Text(fmtIDR(p.harga)),
                      trailing: q == 0
                          ? IconButton(
                              icon: const Icon(Icons.add_circle, color: AppColors.mint600),
                              onPressed: () => setState(() => _qty[p.id] = 1),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => setState(() {
                                    final n = q - 1;
                                    if (n <= 0) {
                                      _qty.remove(p.id);
                                    } else {
                                      _qty[p.id] = n;
                                    }
                                  }),
                                ),
                                Text('$q', style: const TextStyle(fontWeight: FontWeight.w700)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => setState(() => _qty[p.id] = q + 1),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: (_count == 0 || _loading) ? null : _kirim,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.mint900))
                      : Text(_count == 0 ? 'Pilih item' : 'Kirim ke Dapur ($_count item)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
