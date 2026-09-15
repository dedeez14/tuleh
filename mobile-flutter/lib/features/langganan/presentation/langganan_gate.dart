import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/offline/pengurai.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../domain/langganan.dart';
import 'langganan_providers.dart';

/// Pembungkus akar: saat endpoint tulis menjawab 402, tampilkan layar
/// "Langganan berakhir" dengan tautan perpanjang dari server. Transaksi yang
/// ditolak TIDAK diantrekan; data tetap bisa dilihat setelah layar ditutup.
class LanggananGate extends ConsumerWidget {
  const LanggananGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terkunci = ref.watch(langgananTerkunciProvider);
    final masuk = ref.watch(authControllerProvider).valueOrNull != null;
    if (terkunci == null || !masuk) return child;
    return LanggananBerakhirScreen(info: terkunci);
  }
}

class LanggananBerakhirScreen extends ConsumerStatefulWidget {
  const LanggananBerakhirScreen({super.key, required this.info});
  final LanggananTerkunci info;

  @override
  ConsumerState<LanggananBerakhirScreen> createState() => _LanggananBerakhirScreenState();
}

class _LanggananBerakhirScreenState extends ConsumerState<LanggananBerakhirScreen> {
  bool _memeriksa = false;
  String? _catatan;

  String? get _urlPerpanjang {
    final dariTolak = widget.info.perpanjangUrl;
    if (dariTolak != null) return dariTolak;
    return ref.read(statusLanggananProvider).valueOrNull?.perpanjangUrl;
  }

  Future<void> _buka(String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null && await ref.read(pembukaTautanProvider)(uri);
    if (!ok && mounted) setState(() => _catatan = 'Tautan tidak dapat dibuka di perangkat ini.');
  }

  Future<void> _periksaLagi() async {
    setState(() {
      _memeriksa = true;
      _catatan = null;
    });
    ref.invalidate(statusLanggananProvider);
    final status = await ref.read(statusLanggananProvider.future);
    if (!mounted) return;
    final masihTerblokir = status == null || (status.berakhir && status.blokirTulis);
    if (status != null && !masihTerblokir) {
      ref.read(langgananTerkunciProvider.notifier).state = null;
      // Transaksi yang tertahan 402 di antrean dilanjutkan.
      await ref.read(penguraiProvider).jalankan();
      if (mounted) setState(() => _memeriksa = false);
      return;
    }
    setState(() {
      _memeriksa = false;
      _catatan = status == null
          ? 'Status langganan belum bisa diperiksa. Pastikan ada internet lalu coba lagi.'
          : 'Langganan masih tercatat berakhir. Selesaikan perpanjangan lalu periksa lagi.';
    });
  }

  @override
  Widget build(BuildContext context) {
    // Tautan dari status bila jawaban 402 tidak menyertakannya.
    ref.watch(statusLanggananProvider);
    final kontak = ref.watch(kontakCsProvider).valueOrNull;
    final url = _urlPerpanjang;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.mint900,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_clock_outlined, color: Colors.white, size: 56),
                    const SizedBox(height: 20),
                    const Text(
                      'Langganan berakhir',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.info.pesan,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Transaksi baru tidak dapat disimpan sampai langganan diperpanjang. '
                      'Data yang sudah ada tetap bisa dilihat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13.5, height: 1.45),
                    ),
                    const SizedBox(height: 24),
                    if (url != null)
                      FilledButton.icon(
                        key: const Key('langganan-perpanjang'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.mint400,
                          foregroundColor: AppColors.mint900,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: () => _buka(url),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Perpanjang langganan'),
                      )
                    else
                      Text(
                        'Tautan perpanjangan belum tersedia dari server. Hubungi layanan pelanggan.',
                        key: const Key('langganan-tanpa-tautan'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    if (kontak != null && kontak.ada) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () => _buka(kontak.waLink!),
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(kontak.nama == null ? 'Hubungi CS' : 'Hubungi ${kontak.nama}'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _memeriksa ? null : _periksaLagi,
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: Text(_memeriksa ? 'Memeriksa…' : 'Saya sudah memperpanjang — periksa lagi'),
                    ),
                    TextButton(
                      onPressed: () => ref.read(langgananTerkunciProvider.notifier).state = null,
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: const Text('Tutup & lihat data'),
                    ),
                    if (_catatan != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _catatan!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.mint200),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pita peringatan langganan di atas isi layar utama. Kapan tampil diputuskan
/// data server ([StatusLangganan.perluPeringatan]: ambang dari master data).
class PitaLangganan extends ConsumerWidget {
  const PitaLangganan({super.key, required this.child});
  final Widget child;

  static String teks(StatusLangganan s) {
    if (s.berakhir) {
      return s.blokirTulis
          ? 'Langganan berakhir — transaksi baru tidak dapat disimpan.'
          : 'Langganan berakhir. Segera perpanjang.';
    }
    if (s.tenggang) return 'Langganan dalam masa tenggang. Segera perpanjang.';
    final sisa = s.sisaHari ?? 0;
    return sisa <= 0 ? 'Langganan berakhir hari ini.' : 'Langganan berakhir dalam $sisa hari.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statusLanggananProvider).valueOrNull;
    final tampil = s != null && s.perluPeringatan;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (tampil)
          Material(
            key: const Key('pita-langganan'),
            color: (s.berakhir ? AppColors.danger : AppColors.warn).withValues(alpha: 0.14),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: [
                    Icon(Icons.event_busy_outlined, size: 18, color: s.berakhir ? AppColors.danger : AppColors.warn),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        teks(s),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                    ),
                    if (s.perpanjangUrl != null)
                      TextButton(
                        onPressed: () async {
                          final uri = Uri.tryParse(s.perpanjangUrl!);
                          if (uri != null) await ref.read(pembukaTautanProvider)(uri);
                        },
                        child: const Text('Perpanjang'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: child),
      ],
    );
  }
}
