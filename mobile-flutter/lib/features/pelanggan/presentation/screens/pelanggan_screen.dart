import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/pelanggan.dart';
import '../providers/pelanggan_providers.dart';

/// Layar Pelanggan — daftar + tambah cepat.
class PelangganScreen extends ConsumerWidget {
  const PelangganScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pelangganListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pelanggan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const _TambahSheet(),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Tambah'),
      ),
      body: LebarKonten(child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pelangganListProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text(e is ApiException ? e.message : 'Gagal memuat pelanggan.',
                      textAlign: TextAlign.center)),
            ),
          ]),
          data: (rows) => rows.isEmpty
              ? ListView(children: const [
                  Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: Text('Belum ada pelanggan.')),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _Tile(p: rows[i]),
                ),
        ),
      )),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.p});
  final Pelanggan p;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = p.nama.isNotEmpty ? p.nama[0].toUpperCase() : '?';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.mint400.withValues(alpha: 0.2),
          child: Text(initial,
              style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
        ),
        title: Text(p.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (p.telepon != null && p.telepon!.isNotEmpty) p.telepon!,
          if (p.kode != null && p.kode!.isNotEmpty) p.kode!,
        ].join(' · ')),
      ),
    );
  }
}

class _TambahSheet extends ConsumerStatefulWidget {
  const _TambahSheet();
  @override
  ConsumerState<_TambahSheet> createState() => _TambahSheetState();
}

class _TambahSheetState extends ConsumerState<_TambahSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nama = TextEditingController();
  final _telepon = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nama.dispose();
    _telepon.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final r = await ref.read(pelangganRepositoryProvider).tambah(
          nama: _nama.text.trim(),
          telepon: _telepon.text.trim(),
        );
    if (!mounted) return;
    r.when(
      ok: (_) {
        ref.invalidate(pelangganListProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              backgroundColor: AppColors.success,
              content: Text('Pelanggan ditambahkan.')));
      },
      err: (e) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: AppColors.danger,
              content: Text(e.firstError() ?? e.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tambah Pelanggan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nama,
              textInputAction: TextInputAction.next,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Nama', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nama wajib diisi.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telepon,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _loading ? null : _simpan(),
              decoration: const InputDecoration(
                  labelText: 'No. WhatsApp (opsional)',
                  prefixIcon: Icon(Icons.chat_outlined)),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _loading ? null : _simpan,
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: AppColors.mint900))
                  : const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
