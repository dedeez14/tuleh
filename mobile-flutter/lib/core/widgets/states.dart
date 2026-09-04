import 'package:flutter/material.dart';

import '../network/api_exception.dart';

/// Tampilan keadaan kosong / gagal / memuat yang seragam di seluruh aplikasi.
/// Satu bentuk untuk semua layar supaya pengguna mengenali polanya.

class KeadaanKosong extends StatelessWidget {
  const KeadaanKosong({
    super.key,
    required this.ikon,
    required this.judul,
    this.detail,
    this.aksi,
  });

  final IconData ikon;
  final String judul;
  final String? detail;
  final Widget? aksi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 76,
              width: 76,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(ikon, size: 34, color: cs.primary),
            ),
            const SizedBox(height: 18),
            Text(
              judul,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (detail != null) ...[
              const SizedBox(height: 7),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
            if (aksi != null) ...[const SizedBox(height: 20), aksi!],
          ],
        ),
      ),
    );
  }
}

class KeadaanGagal extends StatelessWidget {
  const KeadaanGagal({super.key, required this.error, required this.onUlangi});

  final Object error;
  final VoidCallback onUlangi;

  @override
  Widget build(BuildContext context) {
    final pesan = error is ApiException
        ? (error as ApiException).message
        : 'Terjadi kesalahan yang tidak terduga.';
    return KeadaanKosong(
      ikon: Icons.cloud_off_rounded,
      judul: 'Gagal memuat data',
      detail: pesan,
      aksi: OutlinedButton.icon(
        onPressed: onUlangi,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Coba lagi'),
      ),
    );
  }
}

/// Kerangka (skeleton) berkedip — pengganti lingkaran berputar pada daftar,
/// supaya bentuk halaman sudah terbaca sebelum datanya tiba.
class Kerangka extends StatefulWidget {
  const Kerangka({
    super.key,
    this.tinggi = 16,
    this.lebar,
    this.radius = 8,
  });

  final double tinggi;
  final double? lebar;
  final double radius;

  @override
  State<Kerangka> createState() => _KerangkaState();
}

class _KerangkaState extends State<Kerangka>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.tinggi,
        width: widget.lebar,
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.05 + 0.05 * _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Daftar kerangka untuk katalog / riwayat saat memuat.
class DaftarKerangka extends StatelessWidget {
  const DaftarKerangka({super.key, this.jumlah = 6, this.tinggiBaris = 78});

  final int jumlah;
  final double tinggiBaris;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: jumlah,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        height: tinggiBaris,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Kerangka(tinggi: 13, lebar: 190),
            const SizedBox(height: 10),
            const Kerangka(tinggi: 11, lebar: 110),
          ],
        ),
      ),
    );
  }
}
