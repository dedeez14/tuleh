import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/app_version_info.dart';
import '../providers/update_providers.dart';
import 'update_flow_controller.dart';

/// Banner pembaruan OPSIONAL (bawah layar). Bisa ditutup (maks 1×/hari).
/// "Perbarui" memperluas banner → alur unduh/pasang INLINE (tanpa modal).
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key, required this.info});

  final AppVersionInfo info;

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  UpdateFlowController? _flow;

  Future<void> _mulai() async {
    if (_flow != null) return; // cegah buat ganda (double-tap)
    final f = _flow = UpdateFlowController(
      ref.read(apkInstallerProvider),
      widget.info,
    );
    setState(() {});
    await f.init();
    if (f.phase == UpdatePhase.ready) await f.start();
  }

  @override
  void dispose() {
    _flow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.mint900,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: _flow == null
            ? _collapsed()
            : ListenableBuilder(
                listenable: _flow!,
                builder: (_, _) => _flowUi(_flow!),
              ),
      ),
    );
  }

  Widget _collapsed() {
    return Row(
      children: [
        const Icon(Icons.system_update, color: AppColors.mint400, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pembaruan tersedia',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              if (widget.info.versiTerbaru.isNotEmpty)
                Text('Versi ${widget.info.versiTerbaru} siap dipasang.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            ],
          ),
        ),
        TextButton(
          onPressed: _mulai,
          style: TextButton.styleFrom(foregroundColor: AppColors.mint400),
          child: const Text('Perbarui',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        // Catatan: TANPA tooltip — UpdateGate berada di MaterialApp.builder (di
        // atas Navigator/Overlay), sedangkan Tooltip butuh Overlay → "No Overlay
        // widget found". Semua widget di banner harus bebas-Overlay.
        IconButton(
          onPressed: () => snoozeUpdateBanner(ref),
          icon: Icon(Icons.close,
              color: Colors.white.withValues(alpha: 0.7), size: 20),
        ),
      ],
    );
  }

  Widget _flowUi(UpdateFlowController f) {
    switch (f.phase) {
      case UpdatePhase.checking:
        return _line(const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.mint400)),
            'Memeriksa…');
      case UpdatePhase.needPermission:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text('Izinkan Tuléh memasang aplikasi untuk memperbarui.'),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: f.openPermission,
                  style: TextButton.styleFrom(foregroundColor: AppColors.mint400),
                  child: const Text('Buka Izin'),
                ),
                TextButton(
                  onPressed: f.recheckPermission,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Sudah izinkan'),
                ),
              ],
            ),
          ],
        );
      case UpdatePhase.ready:
        return Row(
          children: [
            Expanded(child: _text('Siap mengunduh pembaruan.')),
            TextButton(
              onPressed: f.start,
              style: TextButton.styleFrom(foregroundColor: AppColors.mint400),
              child: const Text('Unduh',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        );
      case UpdatePhase.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _text('Mengunduh… ${f.pct}%')),
                TextButton(
                  onPressed: f.cancel,
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.8)),
                  child: const Text('Batal'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: f.pct > 0 ? f.pct / 100 : null,
                minHeight: 6,
                backgroundColor: Colors.white24,
                color: AppColors.mint400,
              ),
            ),
          ],
        );
      case UpdatePhase.installing:
        return _line(const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.mint400)),
            'Membuka pemasang…');
      case UpdatePhase.launched:
        return Row(
          children: [
            Expanded(child: _text('Pemasang dibuka. Selesaikan pemasangan.')),
            TextButton(
              onPressed: f.reinstall,
              style: TextButton.styleFrom(foregroundColor: AppColors.mint400),
              child: const Text('Pasang Ulang',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        );
      case UpdatePhase.error:
        return Row(
          children: [
            Expanded(child: _text(f.error ?? 'Gagal.')),
            TextButton(
              onPressed: f.start,
              style: TextButton.styleFrom(foregroundColor: AppColors.mint400),
              child: const Text('Coba Lagi'),
            ),
          ],
        );
    }
  }

  Widget _line(Widget leading, String text) => Row(
        children: [leading, const SizedBox(width: 12), _text(text)],
      );

  Widget _text(String s) => Text(s,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13));
}
