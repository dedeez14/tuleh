import 'dart:collection';

import 'penyamar.dart';

/// Log ringan di memori (buffer cincin): baris terakhir kejadian aplikasi —
/// permintaan HTTP (metode, jalur, status, durasi; tanpa badan & token),
/// keputusan antrean, perubahan koneksi, galat. Dikirim ke dukungan hanya
/// saat pengguna menekan "Kirim laporan ke dukungan" (Pengaturan) atau
/// menyertai laporan crash. Tidak ditulis ke disk.
class LogCincin {
  LogCincin({this.kapasitas = 400, this.panjangBaris = 600});

  /// Instans aplikasi.
  static final LogCincin global = LogCincin();

  final int kapasitas;
  final int panjangBaris;
  final Queue<String> _baris = Queue<String>();

  int get jumlah => _baris.length;

  void catat(String pesan, {String tingkat = 'I'}) {
    final t = DateTime.now();
    String dua(int n) => n.toString().padLeft(2, '0');
    final jam = '${dua(t.hour)}:${dua(t.minute)}:${dua(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    var isi = samarkan(pesan.replaceAll('\n', ' ⏎ '));
    if (isi.length > panjangBaris) isi = '${isi.substring(0, panjangBaris)}…';
    _baris.addLast('$jam $tingkat $isi');
    while (_baris.length > kapasitas) {
      _baris.removeFirst();
    }
  }

  List<String> semua() => List.unmodifiable(_baris);

  /// Baris terakhir yang muat dalam [maksKarakter] (paling baru di bawah).
  String ekor({int maksKarakter = 20000}) {
    final out = <String>[];
    var panjang = 0;
    for (final b in _baris.toList().reversed) {
      if (panjang + b.length + 1 > maksKarakter) break;
      out.add(b);
      panjang += b.length + 1;
    }
    return out.reversed.join('\n');
  }

  void kosongkan() => _baris.clear();
}
