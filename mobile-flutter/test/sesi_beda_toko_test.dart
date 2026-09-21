// Tahap B §2a di Android: server menolak checkout ke toko selain toko sesi kasir (409 berkode).
// Kasir tak boleh cuma melihat pesan merah — tombol "Pindah ke <toko>" mengganti toko aktif.
//
// Id toko dari server adalah ciphertext non-deterministik (encrypt_id): id toko
// yang SAMA berbeda antara `/tokos` dan `meta.sesi_toko`. Pencocokan karena itu
// memakai `kode` (TK-xxx) lalu `nama`, tidak pernah id.

import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/features/kasir/domain/galat_kasir.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko.dart';

void main() {
  const beda = ApiException(
    message: 'Sesi kasir Anda dibuka di toko Toko Pusat. Pilih toko itu atau tutup sesi dulu.',
    statusCode: 409,
    errors: {'kode': ['SESI_BEDA_TOKO']},
    meta: {'sesi_toko': {'id': 'T1', 'nama': 'Toko Pusat'}},
  );

  test('kodeGalat & tokoSesi membaca amplop 409 server', () {
    expect(kodeGalat(beda), 'SESI_BEDA_TOKO');
    expect(tokoSesi(beda)?.id, 'T1');
    expect(tokoSesi(beda)?.nama, 'Toko Pusat');
    expect(tokoSesi(beda)?.kode, isNull, reason: 'server lama belum mengirim kode');
  });

  test('409 lama (belum ada sesi) tidak dikira beda toko', () {
    const lama = ApiException(message: 'Belum ada sesi kasir yang terbuka.', statusCode: 409);
    expect(kodeGalat(lama), '');
    expect(tokoSesi(lama), isNull);
  });

  test('meta tanpa id diabaikan (server lama) — tombol pindah tak ditawarkan', () {
    const separuh = ApiException(message: 'x', statusCode: 409, errors: {'kode': ['SESI_BEDA_TOKO']}, meta: {'sesi_toko': {'nama': 'Toko Pusat'}});
    expect(tokoSesi(separuh), isNull);
  });

  test('kode toko ikut terbaca bila server mengirimnya', () {
    const berkode = ApiException(
      message: 'x',
      statusCode: 409,
      errors: {'kode': ['SESI_BEDA_TOKO']},
      meta: {'sesi_toko': {'id': 'T9', 'nama': 'Toko Pusat', 'kode': 'TK-001'}},
    );
    expect(tokoSesi(berkode)?.kode, 'TK-001');
  });

  group('pilihTokoSesi', () {
    const pusat = Toko(id: 'enc-a', nama: 'Toko Pusat', kode: 'TK-001');
    const cabang = Toko(id: 'enc-b', nama: 'Cabang Dago', kode: 'TK-002');

    test('cocok lewat kode walau id-nya berbeda (ciphertext acak)', () {
      const sesi = TokoSesi(id: 'ciphertext-lain', nama: 'Nama Lama', kode: 'TK-002');
      expect(pilihTokoSesi(const [pusat, cabang], sesi), cabang);
    });

    test('tanpa kode: jatuh ke nama, tanpa peduli spasi & huruf besar', () {
      const sesi = TokoSesi(id: 'z', nama: '  toko PUSAT ');
      expect(pilihTokoSesi(const [pusat, cabang], sesi), pusat);
    });

    test('daftar belum berkode (server lama): nama tetap dipakai', () {
      const lama = Toko(id: 'enc-c', nama: 'Toko Pusat');
      const sesi = TokoSesi(id: 'z', nama: 'Toko Pusat', kode: 'TK-001');
      expect(pilihTokoSesi(const [lama], sesi), lama);
    });

    test('tak ada yang cocok → null (pemanggil pakai id dari amplop 409)', () {
      const sesi = TokoSesi(id: 'z', nama: 'Toko Gudang', kode: 'TK-009');
      expect(pilihTokoSesi(const [pusat, cabang], sesi), isNull);
      expect(pilihTokoSesi(const [], sesi), isNull);
    });

    test('kedua sisi berkode tapi beda: nama senama tidak dianggap cocok', () {
      const sesi = TokoSesi(id: 'z', nama: 'Toko Pusat', kode: 'TK-077');
      expect(pilihTokoSesi(const [pusat, cabang], sesi), isNull);
    });
  });
}
