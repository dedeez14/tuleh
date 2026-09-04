import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/rupiah_input.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../domain/entities/pengeluaran.dart';
import '../providers/pengeluaran_providers.dart';

/// Pengeluaran (kas keluar) — daftar bulan berjalan + total, tambah & hapus.
class PengeluaranScreen extends ConsumerWidget {
  const PengeluaranScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pengeluaranListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const _TambahSheet(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pengeluaranListProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(e is ApiException ? e.message : 'Gagal memuat pengeluaran.',
                    textAlign: TextAlign.center),
              ),
            ),
          ]),
          data: (rows) => _Body(rows: rows),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.rows});
  final List<Pengeluaran> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final total = rows.fold<double>(0, (s, e) => s + e.nominal);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('Total bulan ini',
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65))),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(fmtIDR(total),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.danger)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('Belum ada pengeluaran bulan ini.')),
          )
        else
          for (final p in rows) _Tile(p: p),
      ],
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.p});
  final Pengeluaran p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline),
      ),
      child: ListTile(
        title: Text(p.keterangan, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(fmtTanggal(p.tanggal),
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 12)),
        // Trailing dibatasi lebarnya: ListTile memberi trailing ruang bebas,
        // dan nominal panjang + tombol hapus pernah mendorong judul keluar
        // layar pada ponsel 320px.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(fmtIDR(p.nominal),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: cs.onSurface.withValues(alpha: 0.5)),
              onPressed: () => _hapus(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _hapus(BuildContext context, WidgetRef ref) async {
    if (p.id.isEmpty) return;
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus pengeluaran?'),
        content: Text('"${p.keterangan}" (${fmtIDR(p.nominal)}) akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ya != true || !context.mounted) return;
    final r = await ref.read(pengeluaranRepositoryProvider).hapus(p.id);
    if (!context.mounted) return;
    r.when(
      ok: (_) {
        ref.invalidate(pengeluaranListProvider);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              backgroundColor: AppColors.success, content: Text('Pengeluaran dihapus.')));
      },
      err: (e) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message))),
    );
  }
}

class _TambahSheet extends ConsumerStatefulWidget {
  const _TambahSheet();

  @override
  ConsumerState<_TambahSheet> createState() => _TambahSheetState();
}

class _TambahSheetState extends ConsumerState<_TambahSheet> {
  final _keterangan = TextEditingController();
  final _nominal = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _keterangan.dispose();
    _nominal.dispose();
    super.dispose();
  }

  String _todayIso() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _simpan() async {
    final ket = _keterangan.text.trim();
    final nom = parseRupiah(_nominal.text);
    if (ket.isEmpty || nom <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Isi keterangan & nominal yang valid.')));
      return;
    }
    setState(() => _saving = true);
    final r = await ref.read(pengeluaranRepositoryProvider).tambah(
          keterangan: ket,
          nominal: nom,
          tanggal: _todayIso(),
        );
    if (!mounted) return;
    r.when(
      ok: (_) {
        ref.invalidate(pengeluaranListProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              backgroundColor: AppColors.success, content: Text('Pengeluaran ditambahkan.')));
      },
      err: (e) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tambah Pengeluaran',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            controller: _keterangan,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Keterangan',
              hintText: 'mis. Beli galon, bayar listrik',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nominal,
            keyboardType: TextInputType.number,
            inputFormatters: const [RupiahInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Nominal',
              hintText: '50.000',
              prefixText: 'Rp ',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _simpan,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.mint900),
                  )
                : const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
