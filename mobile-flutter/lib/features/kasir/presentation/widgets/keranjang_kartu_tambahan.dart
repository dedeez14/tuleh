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
    final hasil = await showDialog<double>(
      context: context,
      builder: (_) => _DialogTeks<double>(
        judul: 'Diskon transaksi',
        awal: meta.diskonPersen > 0 ? fmtQty(meta.diskonPersen) : '',
        labelSimpan: 'Terapkan',
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        dekorasi: const InputDecoration(
          suffixText: '%',
          helperText: 'Berlaku untuk semua item. Kosongkan untuk menghapus.',
        ),
        ubah: (teks) => double.tryParse(teks.replaceAll(',', '.')) ?? 0,
      ),
    );
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
    final hasil = await showDialog<String>(
      context: context,
      builder: (_) => _DialogTeks<String>(
        judul: 'Catatan transaksi',
        awal: ref.read(keranjangMetaProvider).catatan,
        labelSimpan: 'Simpan',
        maksHuruf: 200,
        baris: 3,
        kapital: TextCapitalization.sentences,
        dekorasi: const InputDecoration(hintText: 'Mis. tanpa es, ambil jam 5'),
        ubah: (teks) => teks,
      ),
    );
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

/// Dialog satu kolom isian yang MEMILIKI controllernya sendiri — kalau
/// controller dibuang oleh pemanggil tepat setelah showDialog kembali, dialog
/// yang masih beranimasi menutup akan memakai controller yang sudah dilepas.
class _DialogTeks<T> extends StatefulWidget {
  const _DialogTeks({
    required this.judul,
    required this.awal,
    required this.labelSimpan,
    required this.ubah,
    this.dekorasi,
    this.keyboard,
    this.maksHuruf,
    this.baris = 1,
    this.kapital = TextCapitalization.none,
  });

  final String judul;
  final String awal;
  final String labelSimpan;
  final T Function(String teks) ubah;
  final InputDecoration? dekorasi;
  final TextInputType? keyboard;
  final int? maksHuruf;
  final int baris;
  final TextCapitalization kapital;

  @override
  State<_DialogTeks<T>> createState() => _DialogTeksState<T>();
}

class _DialogTeksState<T> extends State<_DialogTeks<T>> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.awal);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _simpan() => Navigator.pop(context, widget.ubah(_ctrl.text));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.judul),
    content: TextField(
      controller: _ctrl,
      autofocus: true,
      keyboardType: widget.keyboard,
      maxLength: widget.maksHuruf,
      maxLines: widget.baris,
      textCapitalization: widget.kapital,
      decoration: widget.dekorasi,
      onSubmitted: widget.baris == 1 ? (_) => _simpan() : null,
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
      FilledButton(onPressed: _simpan, child: Text(widget.labelSimpan)),
    ],
  );
}
