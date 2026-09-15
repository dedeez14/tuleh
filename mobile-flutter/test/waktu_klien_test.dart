// `waktu_klien` yang dikirim ke server MOVERA.
//
// Server menyimpannya apa adanya ke kolom MySQL `datetime`
// (`client_created_at`): format ISO dengan akhiran "Z" ditolak dengan
// SQLSTATE[22007] 1292 "Incorrect datetime value" dan transaksi GAGAL —
// kasir tidak bisa menyelesaikan penjualan. Uji ini menjaga formatnya.

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/rujukan_lokal.dart';
import 'package:tuleh_pos/core/offline/waktu_klien.dart';

String _offset(DateTime d) {
  final o = d.timeZoneOffset;
  final m = o.inMinutes.abs();
  return '${o.isNegative ? '-' : '+'}${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

void main() {
  test('waktu lokal kasir + offset zona, detik penuh, tanpa milidetik', () {
    final a = DateTime(2026, 9, 12, 14, 25, 41, 635);
    expect(waktuKlienIso(a), '2026-09-12T14:25:41${_offset(a)}');
    final b = DateTime(2026, 1, 5, 7, 8, 9);
    expect(waktuKlienIso(b), '2026-01-05T07:08:09${_offset(b)}');
  });

  test('uji berjalan dengan TZ=Asia/Jakarta: offset +07:00', () {
    // CI & docker menjalankan `flutter test` dengan TZ=Asia/Jakarta.
    expect(waktuKlienIso(DateTime(2026, 9, 12, 14, 25, 41)), '2026-09-12T14:25:41+07:00');
  }, skip: DateTime(2026, 9, 12).timeZoneOffset != const Duration(hours: 7) ? 'TZ bukan Asia/Jakarta' : false);

  test('tidak pernah "Z" maupun milidetik; offset selalu eksplisit', () {
    final teks = waktuKlienIso();
    expect(teks, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$'));
    expect(teks.contains('Z'), isFalse);
  });

  test('bolak-balik: diurai lagi menjadi instan yang sama', () {
    final t = DateTime.utc(2026, 9, 12, 7, 25, 40);
    expect(DateTime.parse(waktuKlienIso(t)).toUtc(), t);
  });

  test('waktu UTC diterjemahkan ke jam toko, bukan disalin apa adanya', () {
    final utc = DateTime.utc(2026, 9, 12, 7, 25, 40);
    expect(waktuKlienIso(utc), waktuKlienIso(utc.toLocal()));
  });

  group('badanKirim', () {
    test('merapikan waktu_klien lama yang berakhiran Z', () {
      final badan = badanKirim({
        'items': const [],
        'waktu_klien': '2026-09-12T07:25:40.635Z',
        '_tampilan': const [],
      });
      // Baris antrean lama harus tetap bisa dikirim setelah aplikasi diperbarui.
      expect(badan['waktu_klien'], waktuKlienIso(DateTime.utc(2026, 9, 12, 7, 25, 40, 635)));
      expect(badan.containsKey('_tampilan'), isFalse);
    });

    test('baris lama tanpa zona (waktu lokal perangkat) diberi offset', () {
      final badan = badanKirim({'waktu_klien': '2026-09-12T14:25:41'});
      expect(badan['waktu_klien'], waktuKlienIso(DateTime(2026, 9, 12, 14, 25, 41)));
      expect(badan['waktu_klien'], matches(r'[+-]\d{2}:\d{2}$'));
    });

    test('nilai tak terbaca dibiarkan apa adanya (server yang menjawab)', () {
      expect(badanKirim({'waktu_klien': 'entah'})['waktu_klien'], 'entah');
      expect(badanKirim({'waktu_klien': ''})['waktu_klien'], '');
    });
  });
}
