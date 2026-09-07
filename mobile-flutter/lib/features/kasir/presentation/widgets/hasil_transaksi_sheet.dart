import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../cetak/data/struk_teks.dart';
import '../../../cetak/domain/entities/struk.dart';
import '../../../cetak/presentation/aksi_struk.dart';

/// Lembar hasil transaksi — kembalian besar, ringkasan, dan cetak struk.
///
/// Ditampilkan menetap (bukan snackbar) karena kasir biasanya masih
/// menghitung uang; menghilang sendiri justru menyulitkan.
class HasilTransaksiSheet extends ConsumerStatefulWidget {
  const HasilTransaksiSheet({
    super.key,
    required this.struk,
    required this.kembalian,
    this.tertunda = false,
    this.perluTinjau = false,
  });

  final Struk struk;
  final double kembalian;

  /// Transaksi disimpan di perangkat (offline) dan menunggu dikirim.
  final bool tertunda;

  /// Server mungkin sudah menerima; pengguna perlu memeriksa sebelum kirim ulang.
  final bool perluTinjau;

  @override
  ConsumerState<HasilTransaksiSheet> createState() =>
      _HasilTransaksiSheetState();
}

class _HasilTransaksiSheetState extends ConsumerState<HasilTransaksiSheet> {
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
            Text(
              widget.tertunda ? 'Transaksi disimpan' : 'Transaksi berhasil',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            if (widget.tertunda) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warn.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 18, color: AppColors.warn),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.perluTinjau
                            ? 'Server tidak menjawab setelah data dikirim. Periksa '
                                  'Riwayat lalu putuskan di Pengaturan → Sinkronisasi.'
                            : 'Offline — nomor sementara. Dikirim otomatis saat '
                                  'internet kembali; nomor resmi menyusul.',
                        style: const TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.warn, letterSpacing: 0.4),
                  ),
                ),
              ),
            ],
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
            if ((s.diskon ?? 0) > 0)
              _Baris(label: 'Diskon', nilai: '−${fmtIDR(s.diskon!)}'),
            _Baris(label: 'Metode', nilai: s.metode ?? '-'),
            if (s.pelanggan != null && s.pelanggan!.isNotEmpty)
              _Baris(label: 'Pelanggan', nilai: s.pelanggan!),
            const SizedBox(height: 18),
            if (s.logoUrl != null && s.logoUrl!.isNotEmpty) ...[
              // Logo struk yang diatur pemilik di desktop — pratinjau kepala
              // struk, sama dengan yang dicetak ke printer thermal.
              Center(
                child: Image.network(
                  s.logoUrl!,
                  height: 56,
                  fit: BoxFit.contain,
                  semanticLabel: 'Logo ${s.namaToko}',
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.namaToko,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
            ],
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
            OutlinedButton.icon(
              onPressed: _mencetak ? null : () => bagikanStruk(context, s),
              icon: const Icon(Icons.share_outlined, size: 19),
              label: const Text('Bagikan struk'),
            ),
            const SizedBox(height: 4),
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
