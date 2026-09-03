import 'dart:io';

import 'package:flutter/services.dart';

/// Jembatan ke native (MainActivity.kt) untuk unduh + pasang APK pembaruan.
/// Hanya Android; platform lain → no-op / tak didukung.
class ApkInstaller {
  static const MethodChannel _method = MethodChannel('tuleh/updater');
  static const EventChannel _progress = EventChannel('tuleh/updater/progress');

  /// Auto-Update dalam-app hanya untuk Android (app tak menargetkan web).
  bool get isSupported => Platform.isAndroid;

  /// Apakah izin "Instal aplikasi tak dikenal" sudah diberikan.
  Future<bool> canInstall() async {
    if (!isSupported) return false;
    final r = await _method.invokeMethod<bool>('canInstall');
    return r ?? false;
  }

  /// Buka layar sistem "Instal aplikasi tak dikenal" untuk paket ini.
  Future<void> openInstallPermission() async {
    if (!isSupported) return;
    await _method.invokeMethod<void>('openInstallPermission');
  }

  /// Progres unduhan 0..100 (stream native).
  Stream<int> get progress =>
      _progress.receiveBroadcastStream().map((e) => (e as num).toInt());

  /// Unduh APK → kembalikan path lokal. Lempar [PlatformException] bila gagal.
  Future<String> download(String url, {required String filename}) async {
    final path = await _method.invokeMethod<String>(
      'download',
      {'url': url, 'filename': filename},
    );
    if (path == null || path.isEmpty) {
      throw PlatformException(code: 'DOWNLOAD', message: 'Unduhan gagal.');
    }
    return path;
  }

  /// Buka pemasang sistem untuk APK yang sudah diunduh.
  Future<void> install(String path) async {
    if (!isSupported) return;
    await _method.invokeMethod<void>('install', {'path': path});
  }

  /// Batalkan unduhan yang sedang berjalan.
  Future<void> cancel() async {
    if (!isSupported) return;
    await _method.invokeMethod<void>('cancel');
  }
}
