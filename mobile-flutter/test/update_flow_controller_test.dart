import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/update/data/services/apk_installer.dart';
import 'package:tuleh_pos/features/update/domain/entities/app_version_info.dart';
import 'package:tuleh_pos/features/update/presentation/widgets/update_flow_controller.dart';

/// Pemasang palsu: unduh langsung selesai, `install` mengembalikan nilai yang
/// ditentukan (true = pemasang langsung terbuka, false = tertunda karena app
/// di latar belakang; native membukanya otomatis saat app kembali ke depan).
class _InstallerPalsu extends ApkInstaller {
  _InstallerPalsu({this.langsungTerbuka = true});
  final bool langsungTerbuka;
  final dipasang = <String>[];
  int unduhan = 0;

  @override
  bool get isSupported => true;
  @override
  Future<bool> canInstall() async => true;
  @override
  Stream<int> get progress => const Stream.empty();
  @override
  Future<String> download(String url, {required String filename, int? ukuran, String? direktori}) async {
    unduhan++;
    return '/data/unduhan/$filename';
  }

  @override
  Future<bool> install(String path) async {
    dipasang.add(path);
    return langsungTerbuka;
  }
}

const _info = AppVersionInfo(
  wajib: false,
  updateTersedia: true,
  versiTerbaru: '2.9.0',
  versiMinimum: null,
  catatan: '',
  androidUrl: 'https://tatreport.com/unduh/tuleh-2.9.0.apk',
  androidNama: 'tuleh-2.9.0.apk',
  ukuran: null,
);

void main() {
  test('unduhan selesai → pemasang langsung dibuka tanpa aksi pengguna', () async {
    final inst = _InstallerPalsu();
    final f = UpdateFlowController(inst, _info);
    await f.init();
    expect(f.phase, UpdatePhase.ready);
    await f.start();
    expect(inst.dipasang, ['/data/unduhan/tuleh-2.9.0.apk']);
    expect(f.phase, UpdatePhase.launched);
    expect(f.pemasangTertunda, isFalse);
  });

  test('app di latar belakang → status tertunda; Pasang Ulang tidak mengunduh lagi', () async {
    final inst = _InstallerPalsu(langsungTerbuka: false);
    final f = UpdateFlowController(inst, _info);
    await f.init();
    await f.start();
    expect(f.phase, UpdatePhase.launched);
    expect(f.pemasangTertunda, isTrue);
    expect(inst.unduhan, 1);

    await f.reinstall();
    expect(inst.unduhan, 1, reason: 'APK yang sudah diunduh dipakai ulang');
    expect(inst.dipasang.length, 2);
  });
}
