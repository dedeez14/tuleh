import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';

/// Pilihan tampilan (ikuti sistem / terang / gelap), disimpan di perangkat.
/// Nilai awal "sistem" dipakai sampai pilihan tersimpan selesai dibaca agar
/// MaterialApp tidak menunggu.
class TemaNotifier extends Notifier<ThemeMode> {
  static const kunci = 'tema_tampilan';

  @override
  ThemeMode build() {
    ref.read(secureStorageProvider).bacaNilai(kunci).then((v) {
      final m = dariNama(v);
      if (m != null && m != state) state = m;
    }).catchError((_) {});
    return ThemeMode.system;
  }

  Future<void> pilih(ThemeMode m) async {
    state = m;
    await ref.read(secureStorageProvider).tulisNilai(kunci, m.name);
  }

  static ThemeMode? dariNama(String? v) => switch (v) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };
}

final temaProvider = NotifierProvider<TemaNotifier, ThemeMode>(TemaNotifier.new);

String labelTema(ThemeMode m) => switch (m) {
  ThemeMode.light => 'Terang',
  ThemeMode.dark => 'Gelap',
  ThemeMode.system => 'Ikuti sistem',
};
