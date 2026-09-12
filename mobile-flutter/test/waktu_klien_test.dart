// `waktu_klien` yang dikirim ke server MOVERA.
//
// Server menyimpannya apa adanya ke kolom MySQL `datetime`
// (`client_created_at`): format ISO dengan akhiran "Z" ditolak dengan
// SQLSTATE[22007] 1292 "Incorrect datetime value" dan transaksi GAGAL —
// kasir tidak bisa menyelesaikan penjualan. Uji ini menjaga formatnya.

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/offline/rujukan_lokal.dart';
import 'package:tuleh_pos/core/offline/waktu_klien.dart';

void main() {
  test('memakai waktu lokal kasir, detik penuh, tanpa zona & milidetik', () {
    expect(waktuKlienIso(DateTime(2026, 9, 12, 14, 25, 41, 635)), '2026-09-12T14:25:41');
    expect(waktuKlienIso(DateTime(2026, 1, 5, 7, 8, 9)), '2026-01-05T07:08:09');
  });

  test('tidak pernah mengandung "Z" maupun offset zona', () {
    final teks = waktuKlienIso();
    expect(teks, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'));
    expect(teks.contains('Z'), isFalse);
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

    test('nilai tak terbaca dibiarkan apa adanya (server yang menjawab)', () {
      expect(badanKirim({'waktu_klien': 'entah'})['waktu_klien'], 'entah');
      expect(badanKirim({'waktu_klien': ''})['waktu_klien'], '');
    });
  });
}
