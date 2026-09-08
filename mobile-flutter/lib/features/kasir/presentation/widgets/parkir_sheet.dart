import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/states.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../data/parkir_store.dart';
import '../controllers/cart_controller.dart';
import '../controllers/keranjang_meta.dart';

/// Parkir keranjang yang sedang aktif: simpan ke penyimpan per toko, lalu
/// kosongkan keranjang (meta ikut kosong). Umpan balik lewat SnackBar.
Future<bool> parkirKeranjang(BuildContext context, WidgetRef ref) async {
  final items = ref.read(cartControllerProvider);
  if (items.isEmpty) return false;
  final messenger = ScaffoldMessenger.of(context);
  final tokoId = ref.read(activeTokoIdProvider).valueOrNull;
  try {
    final entri = await ref.read(parkirStoreProvider).simpan(
      tokoId,
      items: items,
      meta: ref.read(keranjangMetaProvider),
    );
    ref.read(cartControllerProvider.notifier).clear();
    ref.read(parkirVersiProvider.notifier).state++;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Keranjang #${entri.nomor} diparkir (${entri.jumlahItem} item).'),
      ));
    return true;
  } on ParkirPenuh catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(e.pesan)));
    return false;
  } on ParkirTidakTerbaca catch (e) {
    // Keranjang TIDAK dikosongkan: yang lama belum tentu selamat.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(e.pesan)));
    return false;
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('Gagal menyimpan parkir keranjang di perangkat ini.'),
      ));
    return false;
  }
}

/// Lanjutkan keranjang terparkir: isi keranjang aktif dengan item & meta-nya.
/// Bila keranjang aktif masih berisi, kasir memilih: parkir dulu yang aktif,
/// atau ganti (isi aktif dibuang).
Future<bool> lanjutkanParkir(BuildContext context, WidgetRef ref, KeranjangParkir p) async {
  final aktif = ref.read(cartControllerProvider);
  if (aktif.isNotEmpty) {
    final pilihan = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keranjang aktif masih berisi'),
        content: Text(
          'Keranjang saat ini berisi ${aktif.fold<int>(0, (s, e) => s + e.qty)} item. '
          'Parkir dulu keranjang itu, atau ganti dengan keranjang #${p.nomor}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kembali')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'ganti'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Ganti (buang)'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'parkir'),
            child: const Text('Parkir dulu'),
          ),
        ],
      ),
    );
    if (pilihan == null || !context.mounted) return false;
    if (pilihan == 'parkir' && !await parkirKeranjang(context, ref)) return false;
  }
  if (!context.mounted) return false;
  final tokoId = ref.read(activeTokoIdProvider).valueOrNull;
  final entri = await ref.read(parkirStoreProvider).ambil(tokoId, p.id);
  ref.read(parkirVersiProvider.notifier).state++;
  // PENTING: entri sudah dihapus dari penyimpanan, jadi isinya harus segera
  // dipindahkan ke keranjang. Pemeriksaan context ditunda sampai setelah itu —
  // kalau tidak, layar yang keburu tertutup membuat belanjaan hilang permanen.
  if (entri != null) {
    ref.read(cartControllerProvider.notifier).ganti(entri.items);
    ref.read(keranjangMetaProvider.notifier).atur(entri.meta);
  }
  if (!context.mounted) return entri != null;
  if (entri == null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Keranjang itu sudah tidak ada.')));
    return false;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Keranjang #${entri.nomor} dilanjutkan.')));
  return true;
}

/// Buka daftar keranjang terparkir (lembar bawah di ponsel, dialog di tablet).
Future<void> bukaDaftarParkir(BuildContext context) => tampilkanLembar<void>(
  context,
  builder: (_) => const ParkirSheet(),
);

/// Daftar keranjang terparkir toko aktif dengan aksi Lanjutkan / Hapus.
class ParkirSheet extends ConsumerWidget {
  const ParkirSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftar = ref.watch(parkirDaftarProvider);
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Keranjang terparkir',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ),
                if (layarLebar(context))
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Disimpan di perangkat ini per toko, paling banyak $maksParkir. '
              'Ketuk Lanjutkan untuk memuat kembali ke keranjang.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: daftar.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Gagal membaca parkir: $e'),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: KeadaanKosong(
                        ikon: Icons.local_parking_rounded,
                        judul: 'Belum ada keranjang terparkir',
                        detail: 'Tombol Parkir di keranjang menyimpan belanjaan yang belum dibayar.',
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _KartuParkir(
                        p: list[i],
                        onLanjut: () async {
                          final ok = await lanjutkanParkir(context, ref, list[i]);
                          if (ok && context.mounted) Navigator.of(context).pop();
                        },
                        onHapus: () => _konfirmasiHapus(context, ref, list[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _konfirmasiHapus(BuildContext context, WidgetRef ref, KeranjangParkir p) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus keranjang #${p.nomor}?'),
        content: Text('${p.jumlahItem} item senilai ${fmtIDR(p.total)} akan dibuang.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ya != true) return;
    final tokoId = ref.read(activeTokoIdProvider).valueOrNull;
    await ref.read(parkirStoreProvider).hapus(tokoId, p.id);
    ref.read(parkirVersiProvider.notifier).state++;
  }
}

class _KartuParkir extends StatelessWidget {
  const _KartuParkir({required this.p, required this.onLanjut, required this.onHapus});

  final KeranjangParkir p;
  final VoidCallback onLanjut;
  final VoidCallback onHapus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final jam =
        '${p.waktu.hour.toString().padLeft(2, '0')}:${p.waktu.minute.toString().padLeft(2, '0')}';
    final pelanggan = p.meta.pelanggan?.nama;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onLanjut,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.mint400.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#${p.nomor}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(jam, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.6))),
                  if (pelanggan != null) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.person_outline_rounded, size: 15, color: cs.onSurface.withValues(alpha: 0.6)),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        pelanggan,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.7)),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    fmtIDR(p.total),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.mint600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${p.jumlahItem} item · ${p.ringkasan}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              if (p.meta.catatan.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    p.meta.catatan,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onHapus,
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Hapus'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonalIcon(
                    onPressed: onLanjut,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Lanjutkan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
