import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/states.dart';
import '../../../pelanggan/domain/entities/pelanggan.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';

/// Lembar pilih pelanggan untuk transaksi: cari nama/telepon, pilih, atau
/// tambah cepat (nama + telepon). Mengembalikan pelanggan terpilih, atau
/// [PilihPelangganSheet.hapus] bila kasir melepas pelanggan.
class PilihPelangganSheet extends ConsumerStatefulWidget {
  const PilihPelangganSheet({super.key, this.terpilih});

  final Pelanggan? terpilih;

  /// Penanda "lepaskan pelanggan" (dibedakan dari batal/null).
  static const hapus = Pelanggan(id: '', nama: '');

  static Future<Pelanggan?> tampilkan(BuildContext context, {Pelanggan? terpilih}) =>
      showModalBottomSheet<Pelanggan>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => PilihPelangganSheet(terpilih: terpilih),
      );

  @override
  ConsumerState<PilihPelangganSheet> createState() => _PilihPelangganSheetState();
}

class _PilihPelangganSheetState extends ConsumerState<PilihPelangganSheet> {
  final _cari = TextEditingController();
  bool _formTambah = false;
  final _nama = TextEditingController();
  final _telepon = TextEditingController();
  bool _menyimpan = false;

  @override
  void dispose() {
    _cari.dispose();
    _nama.dispose();
    _telepon.dispose();
    super.dispose();
  }

  Future<void> _tambah() async {
    final nama = _nama.text.trim();
    if (nama.isEmpty) return;
    setState(() => _menyimpan = true);
    final r = await ref.read(pelangganRepositoryProvider).tambah(
      nama: nama,
      telepon: _telepon.text.trim().isEmpty ? null : _telepon.text.trim(),
    );
    if (!mounted) return;
    setState(() => _menyimpan = false);
    r.when(
      ok: (p) {
        ref.invalidate(pelangganListProvider);
        Navigator.of(context).pop(p);
      },
      err: (e) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger, content: Text(e.firstError() ?? e.message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daftar = ref.watch(pelangganListProvider);
    final cs = Theme.of(context).colorScheme;
    final q = _cari.text.trim().toLowerCase();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Pelanggan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  if (widget.terpilih != null)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(PilihPelangganSheet.hapus),
                      icon: const Icon(Icons.person_remove_outlined, size: 18),
                      label: const Text('Lepaskan'),
                    ),
                ],
              ),
            ),
            if (_formTambah)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nama,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nama pelanggan'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _telepon,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Telepon (opsional)'),
                      onSubmitted: (_) => _tambah(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _menyimpan ? null : () => setState(() => _formTambah = false),
                          child: const Text('Batal'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _menyimpan ? null : _tambah,
                          child: Text(_menyimpan ? 'Menyimpan…' : 'Simpan & pilih'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cari,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Cari nama atau telepon…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Tambah pelanggan baru',
                      onPressed: () => setState(() {
                        _formTambah = true;
                        _nama.text = _cari.text.trim();
                      }),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: daftar.when(
                loading: () => const DaftarKerangka(jumlah: 6, tinggiBaris: 66),
                error: (e, _) => KeadaanGagal(
                  error: e is ApiException ? e : Exception('Gagal memuat pelanggan'),
                  onUlangi: () => ref.invalidate(pelangganListProvider),
                ),
                data: (semua) {
                  final list = q.isEmpty
                      ? semua
                      : [
                          for (final p in semua)
                            if (p.nama.toLowerCase().contains(q) || (p.telepon ?? '').contains(q)) p,
                        ];
                  if (list.isEmpty) {
                    return KeadaanKosong(
                      ikon: Icons.person_search_outlined,
                      judul: q.isEmpty ? 'Belum ada pelanggan' : 'Tidak ditemukan',
                      detail: 'Ketuk ikon tambah untuk membuat pelanggan baru.',
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      final aktif = p.id == widget.terpilih?.id;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primary.withValues(alpha: 0.14),
                          child: Text(
                            p.nama.isEmpty ? '?' : p.nama[0].toUpperCase(),
                            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(p.nama, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([p.kode, p.telepon].where((s) => s != null && s.isNotEmpty).join(' · ')),
                        trailing: aktif ? Icon(Icons.check_circle, color: cs.primary) : null,
                        onTap: () => Navigator.of(context).pop(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
