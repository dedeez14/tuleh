import 'dart:async';
import 'dart:math';

import '../diagnostik/log_cincin.dart';
import '../storage/secure_storage.dart';

/// Kunci nilai bebas secure storage untuk id perangkat sinkron. Disimpan
/// sebagai `tuleh_perangkat_sinkron` (awalan ditambah [SecureStorage.tulisNilai]),
/// tidak ikut terhapus saat keluar, ikut hilang bersama basis data antrean
/// saat data aplikasi dihapus / aplikasi dicopot (`allowBackup=false`) —
/// pasangan (device_id, device_seq = `outbox.urut`) tetap konsisten.
const kunciPerangkatSinkron = 'perangkat_sinkron';

/// Satu janji per instans penyimpanan: pemanggil serentak (pengurai & nomor
/// lokal) mendapat id yang sama; gagal baca/tulis → dicoba lagi berikutnya.
final _janji = Expando<Future<String>>('idPerangkatSinkron');

/// UUID v4 acak (RFC 4122) dari [acak].
String buatUuidV4(Random acak) {
  const hex = '0123456789abcdef';
  final b = List<int>.generate(16, (_) => acak.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => hex[x >> 4] + hex[x & 0x0f]).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// `device_id` untuk `POST /sync/v2/batch` (Fase 4): UUID v4 acak dibuat SEKALI
/// per instalasi. Bukan hash ANDROID_ID — nilai itu bertahan pasang ulang
/// sedangkan `outbox.urut` mulai dari 1 lagi, sehingga device_seq bertabrakan.
/// Dibaca juga oleh isolate sinkron latar dengan penyimpanannya sendiri.
Future<String> idPerangkatSinkron(SecureStorage storage, {Random? acak}) {
  final ada = _janji[storage];
  if (ada != null) return ada;
  final baru = _muatAtauBuat(storage, acak ?? Random.secure());
  _janji[storage] = baru;
  return baru;
}

Future<String> _muatAtauBuat(SecureStorage storage, Random acak) async {
  try {
    final tersimpan = (await storage.bacaNilai(kunciPerangkatSinkron))?.trim();
    if (tersimpan != null && tersimpan.isNotEmpty) return tersimpan;
    final baru = buatUuidV4(acak);
    await storage.tulisNilai(kunciPerangkatSinkron, baru);
    return baru;
  } catch (_) {
    _janji[storage] = null;
    rethrow;
  }
}

/// Startup isolate utama, SEBELUM tugas WorkManager didaftarkan
/// (`SinkronLatar.siapkan`): muat atau buat id perangkat sinkron sekali agar
/// isolate latar membaca id yang sudah tersimpan, bukan membuat id kedua
/// bersamaan. Gagal / lewat [batas] tidak menghambat startup — dicatat ke log
/// diagnostik; id dicoba lagi saat pertama dipakai (pengurai / nomor lokal).
Future<void> pastikanIdPerangkatSinkron(
  SecureStorage storage, {
  Duration batas = const Duration(seconds: 3),
}) async {
  try {
    await idPerangkatSinkron(storage).timeout(batas);
  } catch (e) {
    LogCincin.global.catat('Id perangkat sinkron belum tersimpan saat startup (${e.runtimeType})', tingkat: 'W');
  }
}

/// Empat huruf/angka pertama id perangkat, huruf besar — awalan nomor lokal
/// `L-3B9D-260924-0007` supaya struk dua perangkat di hari yang sama tak kembar.
String awalanDariIdPerangkat(String idPerangkat) {
  final bersih = idPerangkat.replaceAll(RegExp('[^0-9A-Za-z]'), '').toUpperCase();
  return bersih.length <= 4 ? bersih : bersih.substring(0, 4);
}
