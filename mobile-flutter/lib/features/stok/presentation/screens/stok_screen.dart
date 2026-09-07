import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/stok_item.dart';
import '../providers/stok_providers.dart';

/// Stok — peringatan restok. Daftar produk urut stok terendah, dengan penanda
/// "Habis"/"Menipis" berdasarkan ambang yang bisa diatur.
class StokScreen extends ConsumerWidget {
  const StokScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(stokListProvider);
    final ambang = ref.watch(restokAmbangProvider).valueOrNull ?? 5;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok'),
        actions: [
          IconButton(
            tooltip: 'Ambang restok',
            onPressed: () => _editAmbang(context, ref, ambang),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: LebarKonten(child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(stokListProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(e is ApiException ? e.message : 'Gagal memuat stok.',
                    textAlign: TextAlign.center),
              ),
            ),
          ]),
          data: (rows) => _Body(rows: rows, ambang: ambang),
        ),
      )),
    );
  }

  Future<void> _editAmbang(BuildContext context, WidgetRef ref, int current) async {
    final nilai = await showDialog<int>(
      context: context,
      builder: (_) => _AmbangDialog(current: current),
    );
    if (nilai == null) return;
    await ref.read(restokAmbangProvider.notifier).set(nilai);
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.rows, required this.ambang});
  final List<StokItem> rows;
  final int ambang;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final perlu = rows.where((s) => s.perluRestok(ambang)).length;
    final habis = rows.where((s) => s.habis).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: perlu > 0 ? AppColors.warn.withValues(alpha: 0.12) : cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: perlu > 0 ? AppColors.warn.withValues(alpha: 0.4) : cs.outline),
          ),
          child: Row(
            children: [
              Icon(perlu > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: perlu > 0 ? AppColors.warn : AppColors.success),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perlu > 0
                          ? '$perlu item perlu direstok'
                          : 'Stok aman',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      '${rows.length} produk · ambang ≤ $ambang'
                      '${habis > 0 ? ' · $habis habis' : ''}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('Tidak ada data stok.')),
          )
        else
          for (final s in rows) _Tile(item: s, ambang: ambang),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.ambang});
  final StokItem item;
  final int ambang;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color color, String? label) = item.habis
        ? (AppColors.danger, 'Habis')
        : item.menipis(ambang)
            ? (AppColors.warn, 'Menipis')
            : (cs.onSurface.withValues(alpha: 0.7), null);
    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline),
      ),
      child: ListTile(
        title: Text(item.produk, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(item.kode,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55), fontSize: 12)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_n(item.stok),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
            if (label != null)
              Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

class _AmbangDialog extends StatefulWidget {
  const _AmbangDialog({required this.current});
  final int current;

  @override
  State<_AmbangDialog> createState() => _AmbangDialogState();
}

class _AmbangDialogState extends State<_AmbangDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current.toString());

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ambang Restok'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Produk dengan stok ≤ nilai ini ditandai perlu direstok.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Ambang (unit)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, int.tryParse(_ctrl.text.trim()) ?? widget.current),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
