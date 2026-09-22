import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_result.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/utils/format.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/pengaturan/domain/entities/profil_usaha.dart';
import 'package:tuleh_pos/features/pengaturan/presentation/providers/pengaturan_providers.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/hasil_pesanan.dart';
import 'package:tuleh_pos/features/pesanan/domain/entities/pesanan.dart';
import 'package:tuleh_pos/features/pesanan/domain/repositories/pesanan_repository.dart';
import 'package:tuleh_pos/features/pesanan/presentation/providers/pesanan_providers.dart';
import 'package:tuleh_pos/features/pesanan/presentation/screens/papan_pesanan_screen.dart';
import 'package:tuleh_pos/features/toko/domain/entities/toko_manifest.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

/// Papan pesanan Fase 3 (2.33.0) sebagai widget: pil DP & sisa terbaca utuh
/// di ponsel sempit, lembar Lunasi menagih SISA, dan struk pelunasan hanya
/// tampil bila server mengirimnya.

class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  final Map<String, String> _m = {};
  @override
  Future<String?> readToken() async => _m['token'];
  @override
  Future<String?> readActiveTokoId() async => _m['toko'];
  @override
  Future<String?> bacaNilai(String k) async => _m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async =>
      v == null ? _m.remove(k) : _m[k] = v;
}

/// Laundry: satu kolom SIAP_AMBIL (tahap terakhir sebelum SELESAI) supaya
/// kartu DP langsung tampil di tab pertama dengan aksi "Lunasi & Serahkan".
class _ManifestPalsu extends ManifestNotifier {
  @override
  Future<TokoManifest> build() async => const TokoManifest(
    transactionFlow: ['INTAKE', 'PAYMENT_OR_LATER'],
    lifecycleStates: ['SIAP_AMBIL', 'SELESAI'],
    paymentModes: ['TUNAI', 'QRIS'],
  );
}

class _RepoPapan implements PesananRepository {
  _RepoPapan({this.struk});

  /// Struk transaksi akhir yang dikirim balik transisi (null = server lama).
  final Map<String, dynamic>? struk;

  final transisi = <({String id, String to, String? tipe})>[];

  @override
  Future<Result<List<Pesanan>>> list({String? stage, String? bayar}) async =>
      const Ok([_dp]);

  @override
  Future<Result<HasilTransisi>> transition(
    String id, {
    required String to,
    String? tipePembayaran,
  }) async {
    transisi.add((id: id, to: to, tipe: tipePembayaran));
    return Ok(
      HasilTransisi(
        pesanan: Pesanan(id: id, stage: to, bayar: 'LUNAS', total: 28000, dibayar: 28000),
        struk: struk,
      ),
    );
  }

  @override
  Future<Result<NotaPesanan>> buatNota({
    required String bayar,
    required List<ItemNota> items,
    String? idPelanggan,
    String? catatan,
    num? uangMuka,
    String? metodeUangMuka,
    required String clientRef,
  }) => throw UnimplementedError();
}

const _dp = Pesanan(
  id: 'ORD-7',
  stage: 'SIAP_AMBIL',
  nomor: 'ORD/0007',
  noAntrian: 'B-007',
  bayar: 'DP',
  total: 28000,
  dibayar: 10000,
  sisa: 18000,
  items: [PesananItem(nama: 'Cuci Setrika', kuantitas: 1)],
);

const _strukPelunasan = <String, dynamic>{
  'nomor': 'TRX/0009',
  'tanggal': '2026-09-22T11:00:00',
  'status': 'SELESAI',
  'tipe_pembayaran': 'TUNAI',
  'grand_total': 28000,
  'uang_muka': 10000,
  'dibayar': 28000,
  'kembalian': 0,
  'items': [
    {'nama': 'Cuci Setrika', 'kuantitas': 1, 'harga': 28000},
  ],
};

/// Pompa berbatas — papan memakai indikator & polling berulang.
Future<void> _pompa(WidgetTester t, [int kali = 12]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<void> pumpPapan(
    WidgetTester t,
    _RepoPapan repo, {
    Size ukuran = const Size(420, 900),
    List<String> metode = const ['TUNAI', 'QRIS'],
  }) async {
    t.view.physicalSize = ukuran;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(_Storage()),
        masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ...overrideOffline(),
        activeManifestProvider.overrideWith(_ManifestPalsu.new),
        pesananRepositoryProvider.overrideWithValue(repo),
        metodePembayaranProvider.overrideWith((_) async => metode),
        profilUsahaProvider.overrideWith(
          (_) async => const ProfilUsaha(nama: 'Laundry Uji'),
        ),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: PapanPesananScreen()),
      ),
    );
    await _pompa(t);
  }

  testWidgets('360 dp: pil "DP · sisa" terbaca utuh, tidak terpotong elipsis', (t) async {
    await pumpPapan(t, _RepoPapan(), ukuran: const Size(360, 640));
    final pil = find.text('DP Rp 10.000 · sisa Rp 18.000');
    expect(pil, findsOneWidget);
    expect(t.renderObject<RenderParagraph>(pil).didExceedMaxLines, isFalse,
        reason: 'sisa tagihan tak boleh hilang di balik "…"');
    expect(t.renderObject<RenderParagraph>(find.text(fmtIDR(28000))).didExceedMaxLines, isFalse);
    expect(t.takeException(), isNull, reason: 'tanpa luapan RenderFlex');
  });

  testWidgets('Lunasi pesanan DP: lembar menagih SISA & struk pelunasan tampil', (t) async {
    final repo = _RepoPapan(struk: _strukPelunasan);
    await pumpPapan(t, repo);
    await t.tap(find.widgetWithText(FilledButton, 'Lunasi & Serahkan'));
    await _pompa(t);

    expect(find.text('B-007 · ${fmtIDR(18000)}'), findsOneWidget, reason: 'tagihan = sisa, bukan total');
    expect(find.text('Uang muka ${fmtIDR(10000)} sudah diterima.'), findsOneWidget);

    await t.tap(find.widgetWithText(ListTile, 'TUNAI'));
    await _pompa(t, 20);
    expect(repo.transisi.single, (id: 'ORD-7', to: 'SELESAI', tipe: 'TUNAI'));
    expect(find.text('Struk pelunasan'), findsOneWidget);
    expect(find.textContaining('TRX/0009'), findsWidgets);
    await t.tap(find.widgetWithText(TextButton, 'Tutup'));
    await _pompa(t);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('server tanpa struk: transisi tetap sukses, tanpa lembar struk', (t) async {
    final repo = _RepoPapan();
    await pumpPapan(t, repo);
    await t.tap(find.widgetWithText(FilledButton, 'Lunasi & Serahkan'));
    await _pompa(t);
    await t.tap(find.widgetWithText(ListTile, 'QRIS'));
    await _pompa(t, 20);
    expect(repo.transisi, hasLength(1), reason: 'transisi benar-benar dikirim');
    expect(find.text('Struk pelunasan'), findsNothing);
    expect(find.text('Pesanan B-007 lunas & diserahkan.'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('metode dari server kosong ([]) → pilihan cadangan, bukan lembar tanpa tombol', (t) async {
    final repo = _RepoPapan();
    await pumpPapan(t, repo, metode: const []);
    await t.tap(find.widgetWithText(FilledButton, 'Lunasi & Serahkan'));
    await _pompa(t);
    expect(find.widgetWithText(ListTile, 'TUNAI'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'QRIS'), findsOneWidget);
    await t.tapAt(const Offset(20, 20));
    await _pompa(t);
  });
}
