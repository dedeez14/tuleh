import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Logo struk untuk printer thermal.
///
/// Logo diunggah pemilik di desktop (Pengaturan → Profil Usaha) dan tersedia
/// sebagai URL publik di `pengaturan/usaha → struk.logo`. Di sini diunduh
/// (cache di memori per URL), lalu diubah ke bitmap hitam-putih selebar
/// [lebarPx] titik: printer thermal hanya mengenal hitam/putih, dan PNG
/// transparan harus ditumpuk ke putih dulu — tanpa itu latar transparan
/// tercetak sebagai kotak hitam.
class LogoStruk {
  LogoStruk._();

  static final Map<String, Uint8List?> _cache = {};

  /// Batas waktu unduh: logo tak boleh menahan struk lebih dari ini.
  static const Duration batasWaktu = Duration(seconds: 6);

  /// Unduh bytes logo; null bila gagal (cetak berlanjut tanpa logo).
  static Future<Uint8List?> ambil(String url) async {
    if (_cache.containsKey(url)) return _cache[url];
    Uint8List? hasil;
    try {
      final client = HttpClient()..connectionTimeout = batasWaktu;
      try {
        final req = await client.getUrl(Uri.parse(url)).timeout(batasWaktu);
        final res = await req.close().timeout(batasWaktu);
        if (res.statusCode == 200) {
          final b = BytesBuilder(copy: false);
          await res.forEach(b.add).timeout(batasWaktu);
          hasil = b.takeBytes();
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      hasil = null;
    }
    _cache[url] = hasil;
    return hasil;
  }

  /// PNG/JPG → bitmap hitam-putih selebar [lebarPx] (rasio dipertahankan).
  /// Null bila bytes bukan gambar yang dikenali.
  static img.Image? siapkan(Uint8List bytes, {int lebarPx = 240}) {
    img.Image? sumber;
    try {
      sumber = img.decodeImage(bytes);
    } catch (_) {
      // Pendekode paket `image` bisa melempar (bukan null) pada bytes rusak.
      return null;
    }
    if (sumber == null || sumber.width == 0) return null;
    final kecil = img.copyResize(
      sumber,
      width: lebarPx,
      interpolation: img.Interpolation.average,
    );
    // Tumpuk ke kanvas putih (menangani alpha), lalu ambang ke hitam/putih.
    final kanvas = img.Image(width: kecil.width, height: kecil.height);
    img.fill(kanvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(kanvas, kecil);
    for (final p in kanvas) {
      final v = p.luminance > 150 ? 255 : 0;
      p
        ..r = v
        ..g = v
        ..b = v
        ..a = 255;
    }
    return kanvas;
  }
}
