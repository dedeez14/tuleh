// Bagian dari lembar keranjang (cart_sheet.dart), dipisah agar tiap berkas
// tetap di bawah batas ukuran dan mudah dibaca sendiri-sendiri.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/rupiah_input.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/states.dart';
import '../../../pengaturan/domain/entities/pengaturan_pembayaran.dart';

class FormBayar extends StatelessWidget {
  const FormBayar({super.key, 
    required this.total,
    required this.metode,
    required this.terpilih,
    required this.uangCtrl,
    required this.saran,
    required this.pembayaran,
    required this.onPilihMetode,
    required this.onUbahUang,
  });

  final double total;
  final List<String> metode;
  final String terpilih;
  final TextEditingController uangCtrl;
  final List<double> saran;
  final AsyncValue<PengaturanPembayaran> pembayaran;
  final ValueChanged<String> onPilihMetode;
  final VoidCallback onUbahUang;

  static IconData _ikon(String m) => switch (m) {
    'TUNAI' => Icons.payments_outlined,
    'QRIS' => Icons.qr_code_2_rounded,
    _ => Icons.account_balance_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tunai = terpilih == 'TUNAI';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Text(
          'Metode pembayaran',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final m in metode) ...[
              Expanded(
                child: PilihanMetode(
                  label: m,
                  ikon: _ikon(m),
                  aktif: m == terpilih,
                  onTap: () => onPilihMetode(m),
                ),
              ),
              if (m != metode.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 22),
        if (tunai) ...[
          Text(
            'Uang diterima',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: uangCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: const [RupiahInputFormatter()],
            autofocus: true,
            onChanged: (_) => onUbahUang(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              prefixText: 'Rp ',
              hintText: '0',
              helperText: 'Ketik 50000, tampil 50.000',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in saran)
                ActionChip(
                  label: Text(
                    s == total ? 'Uang pas' : fmtIDR(s),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    uangCtrl.text = teksRupiah(s);
                    onUbahUang();
                  },
                ),
            ],
          ),
        ] else if (terpilih == 'QRIS')
          PanduanQris(total: total, pembayaran: pembayaran)
        else
          PanduanTransfer(pembayaran: pembayaran),
      ],
    );
  }
}

class PilihanMetode extends StatelessWidget {
  const PilihanMetode({super.key, 
    required this.label,
    required this.ikon,
    required this.aktif,
    required this.onTap,
  });

  final String label;
  final IconData ikon;
  final bool aktif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: aktif ? cs.primary.withValues(alpha: 0.14) : cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Gerak.cepat,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: aktif ? cs.primary : cs.outline,
              width: aktif ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                ikon,
                size: 21,
                color: aktif
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.65),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: aktif ? cs.primary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Metode QRIS: tunjukkan gambar QRIS statis toko (diunggah pemilik di desktop,
/// Pengaturan → Pembayaran) beserta total, sama seperti layar bayar desktop.

/// Metode TRANSFER: daftar rekening toko dengan tombol salin.

class CatatanKecil extends StatelessWidget {
  const CatatanKecil({super.key, 
    required this.ikon,
    required this.teks,
    this.peringatan = false,
  });
  final IconData ikon;
  final String teks;
  final bool peringatan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final warna = peringatan ? AppColors.warn : cs.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, color: warna),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              teks,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PanduanQris extends StatelessWidget {
  const PanduanQris({super.key, required this.total, required this.pembayaran});
  final double total;
  final AsyncValue<PengaturanPembayaran> pembayaran;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = pembayaran.valueOrNull?.qrStatis;
    if (pembayaran.isLoading) {
      return const Kerangka(tinggi: 220, radius: 16);
    }
    if (url == null) {
      return const CatatanKecil(
        ikon: Icons.qr_code_2_rounded,
        peringatan: true,
        teks: 'QRIS statis belum diunggah. Pemilik/Manajer: buka Pengaturan → '
            'Pembayaran di aplikasi desktop untuk mengunggah gambar QRIS usaha.',
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, anak, prog) => prog == null
                  ? anak
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) => const KeadaanKosong(
                ikon: Icons.broken_image_outlined,
                judul: 'Gambar QRIS gagal dimuat',
                detail: 'Periksa koneksi, lalu buka ulang keranjang.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          fmtIDR(total),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const CatatanKecil(
          ikon: Icons.qr_code_scanner_rounded,
          teks: 'Tunjukkan QR ke pelanggan. Setelah pelanggan membayar dan Anda '
              'cek dananya masuk, tekan Bayar.',
        ),
      ],
    );
  }
}

class PanduanTransfer extends StatelessWidget {
  const PanduanTransfer({super.key, required this.pembayaran});
  final AsyncValue<PengaturanPembayaran> pembayaran;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bank = pembayaran.valueOrNull?.bank ?? const [];
    if (pembayaran.isLoading) {
      return const DaftarKerangka(jumlah: 2, tinggiBaris: 64);
    }
    if (bank.isEmpty) {
      return const CatatanKecil(
        ikon: Icons.account_balance_outlined,
        peringatan: true,
        teks: 'Belum ada rekening. Pemilik/Manajer: tambahkan di Pengaturan → '
            'Pembayaran di aplikasi desktop.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in bank) ...[
          Material(
            color: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: cs.outline),
            ),
            child: ListTile(
              leading: Icon(Icons.account_balance_outlined, color: cs.primary),
              title: Text(
                b.rekening,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 0.5,
                ),
              ),
              subtitle: Text('${b.bank} · a.n. ${b.atasNama}'),
              trailing: IconButton(
                tooltip: 'Salin nomor rekening',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: b.rekening));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text('No. rekening ${b.bank} disalin.'),
                      ),
                    );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const CatatanKecil(
          ikon: Icons.verified_outlined,
          teks: 'Pelanggan transfer ke salah satu rekening. Setelah dana masuk, '
              'tekan Bayar.',
        ),
      ],
    );
  }
}
