import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/meja/presentation/providers/meja_providers.dart';
import '../../features/pengaturan/presentation/providers/pengaturan_providers.dart';
import '../../features/products/presentation/providers/products_provider.dart';
import '../../features/riwayat/presentation/providers/riwayat_providers.dart';
import '../../features/sesi/presentation/providers/sesi_providers.dart';
import '../../features/toko/presentation/providers/toko_providers.dart';
import '../theme/app_colors.dart';
import 'koneksi.dart';

/// Pita status di atas isi layar: tampil hanya saat offline, dengan umur
/// data yang sedang ditampilkan dan tombol coba lagi. Begitu server kembali
/// terjangkau, data utama dimuat ulang dan pita menghilang.
class PitaKoneksi extends ConsumerStatefulWidget {
  const PitaKoneksi({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PitaKoneksi> createState() => _PitaKoneksiState();
}

class _PitaKoneksiState extends ConsumerState<PitaKoneksi> {
  bool _memeriksa = false;

  static String _jam(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    String dua(int n) => n.toString().padLeft(2, '0');
    return '${dua(l.hour)}:${dua(l.minute)}';
  }

  Future<void> _cobaLagi() async {
    setState(() => _memeriksa = true);
    await ref.read(koneksiProvider.notifier).periksa();
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
      if (prev != null && !prev.online && next.online) _segarkanSemua();
    });
    final status = ref.watch(koneksiProvider);
    final cs = Theme.of(context).colorScheme;
    final jam = _jam(status.salinanTerakhir);

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: status.online
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: AppColors.warn.withValues(alpha: 0.14),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 18,
                            color: AppColors.warn,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              jam.isEmpty
                                  ? 'Offline · server tidak terjangkau'
                                  : 'Offline · menampilkan data terakhir $jam',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _memeriksa ? null : _cobaLagi,
                            child: Text(_memeriksa ? 'Memeriksa…' : 'Coba lagi'),
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
