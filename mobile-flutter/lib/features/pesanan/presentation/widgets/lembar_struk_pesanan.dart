import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../cetak/data/struk_teks.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../cetak/presentation/aksi_struk.dart';

/// Lembar nota pesanan / struk pelunasan — pratinjau teks struk apa adanya
/// beserta tombol Cetak & Bagikan yang sama dengan lembar hasil transaksi.
///
/// Dipakai dua kali: setelah nota bayar-nanti / uang muka disimpan di kasir,
/// dan setelah pesanan dilunasi dari papan pesanan. Pratinjau memakai teks
/// (bukan baris terformat) karena nota pesanan membawa baris yang tidak ada
/// di struk transaksi — nomor antrian, uang muka, sisa — dan kasir perlu
/// melihat persis apa yang akan keluar dari printer.
class LembarStrukPesanan extends ConsumerStatefulWidget {
  const LembarStrukPesanan({
    super.key,
    required this.struk,
    required this.judul,
  });

  final Struk struk;
  final String judul;

  @override
  ConsumerState<LembarStrukPesanan> createState() => _LembarStrukPesananState();
}

class _LembarStrukPesananState extends ConsumerState<LembarStrukPesanan> {
  bool _mencetak = false;

  Future<void> _cetak() async {
    setState(() => _mencetak = true);
    try {
      await cetakStrukDenganUmpanBalik(context, ref, widget.struk);
    } finally {
      if (mounted) setState(() => _mencetak = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.struk;

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
                  Icons.receipt_long_rounded,
                  color: AppColors.success,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.judul,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            if (s.demo) ...[
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warn.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    StrukTeks.tandaDemo,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warn,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              s.noAntrian == null || s.noAntrian!.isEmpty
                  ? s.nomor
                  : '${s.nomor} · antrian ${s.noAntrian}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            // Pratinjau apa adanya: bentuknya sama dengan kertas yang keluar.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  const StrukTeks().bangun(s),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
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
              label: Text(_mencetak ? 'Mengirim ke printer…' : 'Cetak nota'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _mencetak ? null : () => bagikanStruk(context, s),
              icon: const Icon(Icons.share_outlined, size: 19),
              label: const Text('Bagikan nota'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _mencetak ? null : () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }
}
