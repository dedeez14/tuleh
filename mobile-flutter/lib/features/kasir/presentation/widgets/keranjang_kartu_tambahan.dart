// Bagian dari lembar keranjang (cart_sheet.dart), dipisah agar tiap berkas
// tetap di bawah batas ukuran dan mudah dibaca sendiri-sendiri.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../controllers/cart_controller.dart';
import '../controllers/keranjang_meta.dart';
import 'pilih_pelanggan_sheet.dart';

class KartuTambahanKeranjang extends ConsumerWidget {
  const KartuTambahanKeranjang({super.key});

  Future<void> _pilihPelanggan(BuildContext context, WidgetRef ref) async {
    final meta = ref.read(keranjangMetaProvider);
    final p = await PilihPelangganSheet.tampilkan(context, terpilih: meta.pelanggan);
    if (p == null) return;
    ref.read(keranjangMetaProvider.notifier).pilihPelanggan(
      identical(p, PilihPelangganSheet.hapus) ? null : p,
    );
  }

  Future<void> _aturDiskon(BuildContext context, WidgetRef ref) async {
    final meta = ref.read(keranjangMetaProvider);
    final ctrl = TextEditingController(
      text: meta.diskonPersen > 0 ? fmtQty(meta.diskonPersen) : '',
    );
    final hasil = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diskon transaksi'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: '%',
            helperText: 'Berlaku untuk semua item. Kosongkan untuk menghapus.',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, double.tryParse(v.replaceAll(',', '.')) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0),
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (hasil == null) return;
    if (hasil < 0 || hasil > 100) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            backgroundColor: AppColors.danger, content: Text('Diskon harus 0–100%.')));
      return;
    }
    ref.read(keranjangMetaProvider.notifier).aturDiskon(hasil);
  }

  Future<void> _aturCatatan(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: ref.read(keranjangMetaProvider).catatan);
    final hasil = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Catatan transaksi'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 200,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Mis. tanpa es, ambil jam 5'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (hasil == null) return;
    ref.read(keranjangMetaProvider.notifier).aturCatatan(hasil);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(keranjangMetaProvider);
    final kotor = ref.watch(cartTotalProvider);
    final potongan = hitungPotongan(kotor, meta.diskonPersen);
    final cs = Theme.of(context).colorScheme;

    Widget baris({
      required IconData ikon,
      required String label,
      required String nilai,
      required bool terisi,
      required VoidCallback onTap,
    }) => ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(ikon, color: terisi ? cs.primary : cs.onSurface.withValues(alpha: 0.5)),
      title: Text(label, style: const TextStyle(fontSize: 13.5)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              nilai,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: terisi ? FontWeight.w800 : FontWeight.w500,
                color: terisi ? cs.onSurface : cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
        ],
      ),
      onTap: onTap,
    );

    return Material(
      color: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline),
      ),
      child: Column(
        children: [
          baris(
            ikon: Icons.person_outline_rounded,
            label: 'Pelanggan',
            nilai: meta.pelanggan?.nama ?? 'Umum',
            terisi: meta.pelanggan != null,
            onTap: () => _pilihPelanggan(context, ref),
          ),
          const Divider(height: 1, indent: 12, endIndent: 12),
          baris(
            ikon: Icons.percent_rounded,
            label: 'Diskon transaksi',
            nilai: meta.diskonPersen > 0
                ? '${fmtQty(meta.diskonPersen)}% · −${fmtIDR(potongan)}'
                : 'Tidak ada',
            terisi: meta.diskonPersen > 0,
            onTap: () => _aturDiskon(context, ref),
          ),
          const Divider(height: 1, indent: 12, endIndent: 12),
          baris(
            ikon: Icons.sticky_note_2_outlined,
            label: 'Catatan',
            nilai: meta.catatan.isEmpty ? 'Tidak ada' : meta.catatan,
            terisi: meta.catatan.isNotEmpty,
            onTap: () => _aturCatatan(context, ref),
          ),
        ],
      ),
    );
  }
}
