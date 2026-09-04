import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/services/apk_installer.dart';
import '../../domain/entities/app_version_info.dart';
import '../../domain/sumber_apk.dart';

enum UpdatePhase {
  checking,
  needPermission,
  ready,
  downloading,
  installing,
  launched, // pemasang sistem sudah dibuka (terminal, tetap ada aksi ulang)
  error,
}

/// Mesin-status alur pembaruan (izin → unduh → pasang), terpisah dari UI agar
/// dipakai ulang oleh layar wajib DAN banner opsional. Semua langkah pakai
/// native channel + system installer (TANPA Navigator Flutter) → aman dipanggil
/// dari widget di atas Navigator (MaterialApp.builder).
class UpdateFlowController extends ChangeNotifier {
  UpdateFlowController(this._installer, this._info);

  final ApkInstaller _installer;
  final AppVersionInfo _info;

  UpdatePhase phase = UpdatePhase.checking;
  int pct = 0;
  String? error;
  String? _downloadedPath;

  StreamSubscription<int>? _sub;
  bool _disposed = false;

  bool get _busy =>
      phase == UpdatePhase.downloading || phase == UpdatePhase.installing;

  /// Cek dukungan + izin instal. Panggil sekali saat mulai alur.
  Future<void> init() async {
    if (!_installer.isSupported) {
      _set(UpdatePhase.error,
          err: 'Pembaruan dalam-app tak tersedia di perangkat ini.');
      return;
    }
    if (!_info.hasAndroidDownload) {
      _set(UpdatePhase.error,
          err: 'Sumber unduhan tidak dikenal. Unduh versi terbaru dari '
              'github.com/${SumberApk.repoGithub}/releases.');
      return;
    }
    final ok = await _installer.canInstall();
    _set(ok ? UpdatePhase.ready : UpdatePhase.needPermission);
  }

  Future<void> openPermission() => _installer.openInstallPermission();

  Future<void> recheckPermission() async {
    if (_busy) return;
    _set(UpdatePhase.checking);
    final ok = await _installer.canInstall();
    _set(ok ? UpdatePhase.ready : UpdatePhase.needPermission);
  }

  /// Unduh (progres) → pasang (pemasang sistem terbuka). Guard: no-op saat sibuk.
  Future<void> start() async {
    if (_busy) return; // cegah re-entrancy (double-tap)
    await _sub?.cancel();
    _set(UpdatePhase.downloading, pct: 0);
    _sub = _installer.progress.listen((p) {
      pct = p;
      _emit();
    });
    try {
      final path = await _installer.download(
        _info.androidUrl!,
        filename: _info.androidNama ?? 'Tuleh-update.apk',
      );
      await _sub?.cancel();
      _downloadedPath = path;
      _set(UpdatePhase.installing);
      await _installer.install(path);
      _set(UpdatePhase.launched);
    } on PlatformException catch (e) {
      await _sub?.cancel();
      _set(UpdatePhase.error, err: e.message ?? 'Unduhan gagal.');
    } catch (_) {
      await _sub?.cancel();
      _set(UpdatePhase.error, err: 'Unduhan gagal. Periksa koneksi lalu coba lagi.');
    }
  }

  /// Buka lagi pemasang untuk APK yang SUDAH diunduh (tanpa unduh ulang).
  /// Dipakai bila pengguna menutup pemasang sistem lalu ingin memasang lagi.
  Future<void> reinstall() async {
    if (_busy) return;
    final p = _downloadedPath;
    if (p == null) {
      await start();
      return;
    }
    try {
      _set(UpdatePhase.installing);
      await _installer.install(p);
      _set(UpdatePhase.launched);
    } on PlatformException catch (e) {
      _set(UpdatePhase.error, err: e.message ?? 'Gagal membuka pemasang.');
    } catch (_) {
      _set(UpdatePhase.error, err: 'Gagal membuka pemasang.');
    }
  }

  /// Batalkan unduhan berjalan → kembali ke ready.
  Future<void> cancel() async {
    if (phase != UpdatePhase.downloading) return;
    await _installer.cancel();
    await _sub?.cancel();
    _set(UpdatePhase.ready);
  }

  void _set(UpdatePhase p, {int? pct, String? err}) {
    phase = p;
    if (pct != null) this.pct = pct;
    error = err;
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
