import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/meja/presentation/providers/meja_providers.dart';
import '../../features/pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../features/products/presentation/providers/products_provider.dart';
import '../../features/riwayat/presentation/providers/riwayat_providers.dart';
import '../../features/sesi/presentation/providers/sesi_providers.dart';
import '../../features/toko/presentation/providers/toko_providers.dart';
import '../theme/app_colors.dart';
import 'antrean.dart';
import 'koneksi.dart';
import 'pengurai.dart';
import 'sinkronisasi_screen.dart';

/// Pita status di atas isi layar: tampil hanya saat offline, dengan umur
/// data yang sedang ditampilkan dan tombol coba lagi. Begitu server kembali
/// terjangkau, data utama dimuat ulang dan pita menghilang.
class PitaKoneksi extends ConsumerStatefulWidget {
  const PitaKoneksi({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PitaKoneksi> createState() => _PitaKoneksiState();
}

class _PitaKoneksiState extends ConsumerState<PitaKoneksi>
    with WidgetsBindingObserver {
  bool _memeriksa = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Antrean sisa sesi sebelumnya dikirim saat aplikasi dibuka.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jalankanAntrean());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _jalankanAntrean();
  }

  Future<void> _jalankanAntrean() async {
    try {
      final terkirim = await ref.read(penguraiProvider).jalankan();
      if (terkirim > 0 && mounted) _segarkanSemua();
    } catch (_) {
      // penyimpanan offline bermasalah — jangan ganggu layar
    }
  }

  static String _jam(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${dua(l.hour)}:${dua(l.minute)}';
  }

  Future<void> _cobaLagi() async {
    setState(() => _memeriksa = true);
    final online = await ref.read(koneksiProvider.notifier).periksa();
    if (online) await _jalankanAntrean();
    if (mounted) setState(() => _memeriksa = false);
  }

  void _segarkanSemua() {
    ref.invalidate(tokoListProvider);
    ref.invalidate(productsProvider);
    ref.invalidate(activeSesiProvider);
    ref.invalidate(riwayatListProvider);
    ref.invalidate(mejaPetaProvider);
    ref.invalidate(profilUsahaProvider);
    ref.invalidate(pengaturanPembayaranProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<StatusKoneksi>(koneksiProvider, (prev, next) {
      if (prev != null && !prev.online && next.online) {
        _segarkanSemua();
        _jalankanAntrean();
      }
    });
    final status = ref.watch(koneksiProvider);
    final antrean = ref.watch(ringkasAntreanProvider).valueOrNull ?? const RingkasAntrean();
    final cs = Theme.of(context).colorScheme;
    final jam = _jam(status.salinanTerakhir);
    final tampil = !status.online || antrean.total > 0;
    final teks = !status.online
        ? [
            'Offline',
            if (antrean.menunggu > 0) '${antrean.menunggu} menunggu dikirim',
            if (jam.isNotEmpty) 'menampilkan data terakhir $jam' else 'server tidak terjangkau',
          ].join(' · ')
        : [
            if (antrean.menunggu > 0) '${antrean.menunggu} transaksi sedang dikirim',
            if (antrean.tinjau > 0) '${antrean.tinjau} perlu ditinjau',
          ].join(' · ');

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !tampil
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: AppColors.warn.withValues(alpha: 0.14),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(
                        children: [
                          Icon(
                            status.online
                                ? Icons.cloud_upload_outlined
                                : Icons.cloud_off_rounded,
                            size: 18,
                            color: AppColors.warn,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              teks,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _memeriksa
                                ? null
                                : antrean.tinjau > 0 && status.online
                                ? () => Navigator.of(context, rootNavigator: true).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const SinkronisasiScreen(),
                                    ),
                                  )
                                : _cobaLagi,
                            child: Text(
                              _memeriksa
                                  ? 'Memeriksa…'
                                  : antrean.tinjau > 0 && status.online
                                  ? 'Tinjau'
                                  : 'Coba lagi',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
