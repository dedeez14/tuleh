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

/// Cara bayar keranjang (Fase 3): Lunas = checkout; Bayar nanti & Uang muka =
/// nota pesanan (`POST /orders`), hanya untuk toko ber-alur `PAYMENT_OR_LATER`.
enum ModeBayar { lunas, nanti, dp }

extension ModeBayarLabel on ModeBayar {
  String get label => switch (this) {
    ModeBayar.lunas => 'Lunas',
    ModeBayar.nanti => 'Bayar nanti',
    ModeBayar.dp => 'Uang muka',
  };
}

class FormBayar extends StatelessWidget {
  const FormBayar({
    super.key,
    required this.total,
    required this.metode,
    required this.terpilih,
    required this.uangCtrl,
    required this.saran,
    required this.pembayaran,
    required this.onPilihMetode,
    required this.onUbahUang,
    this.modeTersedia = const [ModeBayar.lunas],
    this.mode = ModeBayar.lunas,
    this.onPilihMode,
    this.uangMukaCtrl,
    this.galatUangMuka,
    this.sisaUangMuka,
  });

  final double total;
  final List<String> metode;
  final String terpilih;
  final TextEditingController uangCtrl;
  final List<double> saran;
  final AsyncValue<PengaturanPembayaran> pembayaran;
  final ValueChanged<String> onPilihMetode;
  final VoidCallback onUbahUang;

  /// Cara bayar yang boleh dipilih di toko ini. Satu pilihan (Lunas saja) =
  /// pemilih tidak dirender sama sekali, persis tampilan sebelum Fase 3.
  final List<ModeBayar> modeTersedia;
  final ModeBayar mode;
  final ValueChanged<ModeBayar>? onPilihMode;

  /// Kolom nominal uang muka (mode [ModeBayar.dp]).
  final TextEditingController? uangMukaCtrl;

  /// Pesan galat inline uang muka; null = sah (tombol kirim terbuka).
  final String? galatUangMuka;

  /// Sisa tagihan yang akan ditagih saat pesanan diambil; null = tak ditampilkan.
  final double? sisaUangMuka;

  static IconData _ikon(String m) => switch (m) {
    'TUNAI' => Icons.payments_outlined,
    'QRIS' => Icons.qr_code_2_rounded,
    _ => Icons.account_balance_outlined,
  };

  Widget _judulKecil(BuildContext context, String teks) => Text(
    teks,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nanti = mode == ModeBayar.nanti;
    final dp = mode == ModeBayar.dp;
    // Kembalian hanya relevan untuk pembayaran penuh; uang muka memakai
    // kolomnya sendiri dan nota bayar-nanti tidak menerima uang sama sekali.
    final tunai = terpilih == 'TUNAI' && mode == ModeBayar.lunas;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        if (modeTersedia.length > 1) ...[
          _judulKecil(context, 'Cara bayar'),
          const SizedBox(height: 10),
          SegmentedButton<ModeBayar>(
            showSelectedIcon: false,
            segments: [
              for (final m in modeTersedia)
                ButtonSegment<ModeBayar>(value: m, label: Text(m.label)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onPilihMode?.call(s.first),
          ),
          const SizedBox(height: 22),
        ],
        if (nanti)
          CatatanKecil(
            ikon: Icons.schedule_rounded,
            teks:
                'Total nota ${fmtIDR(total)} dibayar saat pesanan diambil. '
                'Nota tersimpan tanpa uang masuk sekarang.',
          )
        else ...[
          _judulKecil(context, dp ? 'Metode uang muka' : 'Metode pembayaran'),
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
        ],
        // Bayar nanti: tak ada metode maupun nominal — panduan QRIS/transfer
        // di bawah pun tidak berlaku (belum ada uang yang diterima).
        if (nanti)
          const SizedBox.shrink()
        else if (dp) ...[
          TextField(
            key: const ValueKey('nota-uang-muka'),
            controller: uangMukaCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: const [RupiahInputFormatter()],
            onChanged: (_) => onUbahUang(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              labelText: 'Uang muka',
              prefixText: 'Rp ',
              hintText: '0',
              errorText: galatUangMuka,
              helperText: galatUangMuka == null && sisaUangMuka != null
                  ? 'Sisa dibayar saat ambil: ${fmtIDR(sisaUangMuka!)}'
                  : 'Dari total ${fmtIDR(total)}',
            ),
          ),
          // Uang muka non-tunai: pelanggan tetap butuh QR statis / rekening
          // toko — sebesar UANG MUKA yang diketik, bukan total pesanan.
          if (terpilih != 'TUNAI') ...[
            const SizedBox(height: 18),
            if (terpilih == 'QRIS')
              PanduanQris(
                total: parseRupiah(uangMukaCtrl?.text ?? ''),
                pembayaran: pembayaran,
                keterangan:
                    'Uang muka — tunjukkan QR ke pelanggan, pindai sebesar '
                    'nominal di atas, cek dananya masuk, lalu tekan Simpan nota.',
              )
            else
              PanduanTransfer(
                pembayaran: pembayaran,
                keterangan:
                    'Uang muka — pelanggan transfer sebesar nominal di atas ke '
                    'salah satu rekening. Setelah dana masuk, tekan Simpan nota.',
              ),
          ],
        ] else if (tunai) ...[
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
  const PilihanMetode({
    super.key,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: aktif
          ? (isDark
                ? AppColors.mint400.withValues(alpha: 0.12)
                : AppColors.mint50.withValues(alpha: 0.9))
          : cs.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: aktif ? 1 : 0,
      shadowColor: AppColors.mint900.withValues(alpha: 0.12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Gerak.cepat,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: aktif
                  ? cs.primary
                  : cs.outline.withValues(alpha: isDark ? 0.65 : 0.85),
              width: aktif ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                ikon,
                size: 22,
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

class CatatanKecil extends StatelessWidget {
  const CatatanKecil({
    super.key,
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

/// Metode QRIS: tunjukkan gambar QRIS statis toko (diunggah pemilik di desktop,
/// Pengaturan → Pembayaran) beserta nominal yang harus dipindai, sama seperti
/// layar bayar desktop.
class PanduanQris extends StatelessWidget {
  const PanduanQris({
    super.key,
    required this.total,
    required this.pembayaran,
    this.keterangan = _keteranganBawaan,
  });

  /// Nominal yang dipindai pelanggan — total bayar Lunas, atau uang muka.
  final double total;
  final AsyncValue<PengaturanPembayaran> pembayaran;

  /// Petunjuk di bawah QR (bawaan: bayar Lunas).
  final String keterangan;

  static const _keteranganBawaan =
      'Tunjukkan QR ke pelanggan. Setelah pelanggan membayar dan Anda '
      'cek dananya masuk, tekan Bayar.';

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
        teks:
            'QRIS statis belum diunggah. Pemilik/Manajer: buka Pengaturan → '
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
        CatatanKecil(ikon: Icons.qr_code_scanner_rounded, teks: keterangan),
      ],
    );
  }
}

/// Metode TRANSFER: daftar rekening toko dengan tombol salin.
class PanduanTransfer extends StatelessWidget {
  const PanduanTransfer({
    super.key,
    required this.pembayaran,
    this.keterangan = _keteranganBawaan,
  });
  final AsyncValue<PengaturanPembayaran> pembayaran;

  /// Petunjuk di bawah daftar rekening (bawaan: bayar Lunas).
  final String keterangan;

  static const _keteranganBawaan =
      'Pelanggan transfer ke salah satu rekening. Setelah dana masuk, '
      'tekan Bayar.';

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
        teks:
            'Belum ada rekening. Pemilik/Manajer: tambahkan di Pengaturan → '
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
        CatatanKecil(ikon: Icons.verified_outlined, teks: keterangan),
      ],
    );
  }
}
