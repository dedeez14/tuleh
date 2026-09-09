import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/states.dart';
import '../../domain/entities/meja.dart';
import '../providers/meja_providers.dart';

/// Peran yang boleh mengubah daftar meja. Server menolak selain ini dengan
/// 403, jadi tombolnya pun disembunyikan agar tidak menjanjikan yang mustahil.
bool bolehKelolaMeja(String? posRole) {
  final r = (posRole ?? '').toUpperCase();
  return r == 'OWNER' || r == 'MANAGER';
}

/// Daftar meja lengkap (termasuk nonaktif) untuk layar Kelola Meja.
final daftarMejaProvider = FutureProvider.autoDispose<List<Meja>>((ref) async {
  final r = await ref.watch(mejaRepositoryProvider).daftarMeja(semua: true);
  return r.when(ok: (v) => v, err: (e) => throw e);
});

/// Kelola Meja — tambah, ubah nomor, nonaktifkan.
///
/// Daftar meja dimiliki server (ERP tatreport); layar ini jendela ke sana.
/// Dua aturan server yang terlihat di sini: kode QR TIDAK berubah saat meja
/// diberi nomor baru (stiker yang sudah tertempel tetap sah), dan meja yang
/// masih punya bon terbuka tidak bisa dinonaktifkan.
class KelolaMejaScreen extends ConsumerWidget {
  const KelolaMejaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftar = ref.watch(daftarMejaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Meja')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _tambah(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah meja'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(daftarMejaProvider),
        child: daftar.when(
          loading: () => const DaftarKerangka(jumlah: 6, tinggiBaris: 66),
          error: (e, _) => ListView(
            children: [
              KeadaanGagal(error: e, onUlangi: () => ref.invalidate(daftarMejaProvider)),
            ],
          ),
          data: (rows) => rows.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 60),
                    KeadaanKosong(
                      ikon: Icons.table_restaurant_outlined,
                      judul: 'Belum ada meja',
                      detail: 'Tambahkan meja lewat tombol di bawah. '
                          'Kode QR dibuat otomatis oleh server.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _KartuMeja(
                    meja: rows[i],
                    onUbah: () => _ubah(context, ref, rows[i]),
                    onNonaktif: () => _nonaktifkan(context, ref, rows[i]),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _tambah(BuildContext context, WidgetRef ref) async {
    final nomor = await _mintaNomor(context, judul: 'Tambah meja');
    if (nomor == null || nomor.isEmpty || !context.mounted) return;
    await _jalankan(
      context,
      ref,
      () => ref.read(mejaRepositoryProvider).tambahMeja(nomor),
      sukses: 'Meja $nomor ditambahkan.',
    );
  }

  Future<void> _ubah(BuildContext context, WidgetRef ref, Meja m) async {
    final nomor = await _mintaNomor(
      context,
      judul: 'Ubah Meja ${m.nomor}',
      awal: m.nomor,
      catatan: 'Kode QR tidak berubah, jadi stiker yang sudah tertempel tetap berlaku.',
    );
    if (nomor == null || nomor.isEmpty || nomor == m.nomor || !context.mounted) return;
    await _jalankan(
      context,
      ref,
      () => ref.read(mejaRepositoryProvider).ubahMeja(m.id, nomor),
      sukses: 'Meja ${m.nomor} kini bernomor $nomor.',
    );
  }

  Future<void> _nonaktifkan(BuildContext context, WidgetRef ref, Meja m) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nonaktifkan Meja ${m.nomor}?'),
        content: const Text(
          'Meja disembunyikan dari peta kasir. Riwayat bon lamanya tetap utuh, '
          'dan meja bisa diaktifkan kembali lewat tatreport.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Ya, nonaktifkan'),
          ),
        ],
      ),
    );
    if (ya != true || !context.mounted) return;
    await _jalankan(
      context,
      ref,
      () => ref.read(mejaRepositoryProvider).nonaktifkanMeja(m.id),
      sukses: 'Meja ${m.nomor} dinonaktifkan.',
    );
  }

  /// Jalankan aksi lalu tampilkan hasilnya. Pesan galat server (mis. 409 "masih
  /// punya bon BON/0007") ditampilkan apa adanya karena menyebut nomor bonnya.
  Future<void> _jalankan(
    BuildContext context,
    WidgetRef ref,
    Future<dynamic> Function() aksi, {
    required String sukses,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final hasil = await aksi();
    hasil.when(
      ok: (_) {
        ref.invalidate(daftarMejaProvider);
        ref.invalidate(mejaPetaProvider);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(backgroundColor: AppColors.success, content: Text(sukses)));
      },
      err: (e) {
        final pesan = e is ApiException ? (e.firstError() ?? e.message) : '$e';
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6),
            content: Text(pesan),
          ));
      },
    );
  }
}

Future<String?> _mintaNomor(
  BuildContext context, {
  required String judul,
  String awal = '',
  String? catatan,
}) => showDialog<String>(
  context: context,
  builder: (_) => _DialogNomor(judul: judul, awal: awal, catatan: catatan),
);

/// Dialog dengan controller miliknya sendiri (dibuang bersama dialognya).
class _DialogNomor extends StatefulWidget {
  const _DialogNomor({required this.judul, required this.awal, this.catatan});

  final String judul;
  final String awal;
  final String? catatan;

  @override
  State<_DialogNomor> createState() => _DialogNomorState();
}

class _DialogNomorState extends State<_DialogNomor> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.awal);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _simpan() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.judul),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (_) => _simpan(),
          decoration: const InputDecoration(
            labelText: 'Nomor meja',
            hintText: 'mis. 7, A3, VIP-1',
            counterText: '',
          ),
        ),
        if (widget.catatan != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.catatan!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
      FilledButton(onPressed: _simpan, child: const Text('Simpan')),
    ],
  );
}

class _KartuMeja extends StatelessWidget {
  const _KartuMeja({required this.meja, required this.onUbah, required this.onNonaktif});

  final Meja meja;
  final VoidCallback onUbah;
  final VoidCallback onNonaktif;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Meja ${meja.nomor}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          decoration: meja.aktif ? null : TextDecoration.lineThrough,
                          color: meja.aktif ? null : cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                      if (!meja.aktif) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('nonaktif', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                      if (meja.terisi) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warn.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('ada bon', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meja.kode ?? '—',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Ubah nomor',
              onPressed: onUbah,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            if (meja.aktif)
              IconButton(
                tooltip: 'Nonaktifkan',
                onPressed: onNonaktif,
                icon: const Icon(Icons.visibility_off_outlined, size: 20),
                color: AppColors.danger,
              ),
          ],
        ),
      ),
    );
  }
}
