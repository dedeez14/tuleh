import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../cetak/data/printer_service.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../cetak/presentation/providers/printer_providers.dart';
import '../../../cetak/presentation/screens/printer_screen.dart';

/// Lembar hasil transaksi — kembalian besar, ringkasan, dan cetak struk.
///
/// Ditampilkan menetap (bukan snackbar) karena kasir biasanya masih
/// menghitung uang; menghilang sendiri justru menyulitkan.
class HasilTransaksiSheet extends ConsumerStatefulWidget {
  const HasilTransaksiSheet({
    super.key,
    required this.struk,
    required this.kembalian,
  });

  final Struk struk;
  final double kembalian;

  @override
  ConsumerState<HasilTransaksiSheet> createState() =>
      _HasilTransaksiSheetState();
}

class _HasilTransaksiSheetState extends ConsumerState<HasilTransaksiSheet> {
  bool _mencetak = false;

  Future<void> _cetak() async {
    final terpilih = ref.read(printerTerpilihProvider).valueOrNull;
    final printer = terpilih?.printer;

    if (printer == null) {
      final keSetelan = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Printer belum dipilih'),
          content: const Text(
            'Pilih printer thermal Bluetooth lebih dulu di Pengaturan → '
            'Printer Struk.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nanti'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Atur printer'),
            ),
          ],
        ),
      );
      if (keSetelan == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PrinterScreen()),
        );
      }
      return;
    }

    setState(() => _mencetak = true);
    try {
      await ref
          .read(printerServiceProvider)
          .cetak(widget.struk, printer: printer, lebar: terpilih!.lebar);
      _pesan('Struk terkirim ke ${printer.nama}.');
    } on PrinterException catch (e) {
      _pesan(e.saran == null ? e.pesan : '${e.pesan} ${e.saran}', gagal: true);
    } catch (e) {
      _pesan('Gagal mencetak: $e', gagal: true);
    } finally {
      if (mounted) setState(() => _mencetak = false);
    }
  }

  void _pesan(String teks, {bool gagal = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: gagal ? AppColors.danger : AppColors.success,
          content: Text(teks),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.struk;
    final adaKembalian = widget.kembalian > 0;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                height: 62,
                width: 62,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: AppColors.success,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Transaksi berhasil',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${s.nomor} · ${s.jumlahItem} item',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            // Kembalian adalah angka yang paling dicari kasir — dibuat dominan.
            if (adaKembalian)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'KEMBALIAN',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fmtIDR(widget.kembalian),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              )
            else
              _Baris(label: 'Total', nilai: fmtIDR(s.total), tebal: true),
            const SizedBox(height: 14),
            if (adaKembalian) ...[
              _Baris(label: 'Total', nilai: fmtIDR(s.total)),
              if (s.dibayar != null)
                _Baris(label: 'Uang diterima', nilai: fmtIDR(s.dibayar!)),
            ],
            _Baris(label: 'Metode', nilai: s.metode ?? '-'),
            const SizedBox(height: 18),
            if (s.barcode != null && s.barcode!.isNotEmpty) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outline),
                  ),
                  child: BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: s.barcode!,
                    width: 108,
                    height: 108,
                    drawText: false,
                    color: const Color(0xFF14332C),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Kode nota ${s.barcode}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 18),
            ],
            FilledButton.icon(
              onPressed: _mencetak ? null : _cetak,
              icon: _mencetak
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.mint900,
                      ),
                    )
                  : const Icon(Icons.print_rounded, size: 20),
              label: Text(_mencetak ? 'Mengirim ke printer…' : 'Cetak struk'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _mencetak ? null : () => Navigator.of(context).pop(),
              child: const Text('Selesai'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Baris extends StatelessWidget {
  const _Baris({required this.label, required this.nilai, this.tebal = false});

  final String label;
  final String nilai;
  final bool tebal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65)),
          ),
          const Spacer(),
          Text(
            nilai,
            style: TextStyle(
              fontWeight: tebal ? FontWeight.w800 : FontWeight.w700,
              fontSize: tebal ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
