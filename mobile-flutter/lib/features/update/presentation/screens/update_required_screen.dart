import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/app_version_info.dart';
import '../providers/update_providers.dart';
import '../widgets/update_flow_controller.dart';

/// Layar WAJIB perbarui — memblokir seluruh app (tak bisa ditutup / Back ditelan).
/// Muncul saat server balas `wajib=true` di /app/versi ATAU HTTP 426 di request apa pun.
/// Alur unduh/pasang di-render INLINE (tanpa modal → tak butuh Navigator).
class UpdateRequiredScreen extends ConsumerStatefulWidget {
  const UpdateRequiredScreen({super.key, required this.info});

  final AppVersionInfo info;

  @override
  ConsumerState<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends ConsumerState<UpdateRequiredScreen> {
  UpdateFlowController? _flow;

  UpdateFlowController _ensureFlow() {
    final f = _flow ??=
        UpdateFlowController(ref.read(apkInstallerProvider), widget.info);
    return f;
  }

  Future<void> _mulai() async {
    final f = _ensureFlow();
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
    final info = widget.info;
    final catatan = info.catatan.isNotEmpty
        ? info.catatan
        : 'Versi aplikasi Anda sudah tidak didukung. Perbarui untuk melanjutkan.';
    return PopScope(
      canPop: false, // Back ditelan — pembaruan wajib
      child: Scaffold(
        backgroundColor: AppColors.mint900,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.system_update,
                        color: Colors.white, size: 44),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Pembaruan Diperlukan',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    catatan,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  if (info.versiTerbaru.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Versi terbaru: ${info.versiTerbaru}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13)),
                  ],
                  const SizedBox(height: 32),
                  _flow == null
                      ? _initialButton(info)
                      : ListenableBuilder(
                          listenable: _flow!,
                          builder: (_, _) => _flowUi(_flow!),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _initialButton(AppVersionInfo info) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: _btnStyle(),
            onPressed: info.hasAndroidDownload ? _mulai : null,
            icon: const Icon(Icons.download),
            label: const Text('Perbarui Sekarang',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        if (!info.hasAndroidDownload) ...[
          const SizedBox(height: 12),
          _hint('Tautan unduhan belum tersedia. Hubungi admin toko Anda.'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => ref.invalidate(appVersionInfoProvider),
            style: TextButton.styleFrom(foregroundColor: AppColors.mint400),
            child: const Text('Cek Lagi'),
          ),
        ],
      ],
    );
  }

  Widget _flowUi(UpdateFlowController f) {
    switch (f.phase) {
      case UpdatePhase.checking:
        return const CircularProgressIndicator(color: Colors.white);
      case UpdatePhase.needPermission:
        return Column(
          children: [
            _hint('Izinkan Tuléh memasang aplikasi dari sumber ini agar '
                'pembaruan bisa dipasang.'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: _btnStyle(),
                onPressed: f.openPermission,
                icon: const Icon(Icons.settings),
                label: const Text('Buka Pengaturan Izin',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: f.recheckPermission,
              style: TextButton.styleFrom(foregroundColor: AppColors.mint400),
              child: const Text('Saya sudah mengizinkan'),
            ),
          ],
        );
      case UpdatePhase.ready:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: _btnStyle(),
            onPressed: f.start,
            icon: const Icon(Icons.download),
            label: const Text('Unduh & Pasang',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        );
      case UpdatePhase.downloading:
        return Column(
          children: [
            Text('Mengunduh… ${f.pct}%',
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: f.pct > 0 ? f.pct / 100 : null,
                minHeight: 8,
                backgroundColor: Colors.white24,
                color: AppColors.mint400,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: f.cancel,
              style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.8)),
              child: const Text('Batal'),
            ),
          ],
        );
      case UpdatePhase.installing:
        return Column(
          children: const [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text('Membuka pemasang sistem…',
                style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
          ],
        );
      case UpdatePhase.launched:
        return Column(
          children: [
            _hint(f.pemasangTertunda
                ? 'Unduhan selesai. Pemasang akan terbuka otomatis saat aplikasi '
                    'kembali ke depan. Jika tidak, tekan Pasang Ulang.'
                : 'Pemasang sistem telah dibuka. Selesaikan pemasangan. '
                    'Jika batal/gagal, tekan Pasang Ulang.'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: _btnStyle(),
                onPressed: f.reinstall,
                icon: const Icon(Icons.system_update),
                label: const Text('Pasang Ulang',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        );
      case UpdatePhase.error:
        return Column(
          children: [
            _hint(f.error ?? 'Terjadi kesalahan.'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: _btnStyle(),
                onPressed: widget.info.hasAndroidDownload ? f.start : null,
                child: const Text('Coba Lagi',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        );
    }
  }

  ButtonStyle _btnStyle() => FilledButton.styleFrom(
        backgroundColor: AppColors.mint400,
        foregroundColor: AppColors.mint900,
        padding: const EdgeInsets.symmetric(vertical: 16),
      );

  Widget _hint(String text) => Text(
        text,
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.4),
        textAlign: TextAlign.center,
      );
}
