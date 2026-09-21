// Refund dari Detail Transaksi (2.30.0): tombol hanya bila server memberi hak
// `transaksi.refund` & ada sisa; lembar per item mengirim kontrak refund; batal
// kini ikut gerbang `transaksi.batal`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/akses/akses.dart';
import 'package:tuleh_pos/core/network/api_result.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/refund.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/transaksi.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/transaksi_detail.dart';
import 'package:tuleh_pos/features/riwayat/domain/repositories/riwayat_repository.dart';
import 'package:tuleh_pos/features/riwayat/presentation/providers/riwayat_providers.dart';
import 'package:tuleh_pos/features/riwayat/presentation/screens/detail_transaksi_screen.dart';

const _detail = TransaksiDetail(
  id: 'T1', nomor: 'POS-000051', tanggal: '2026-09-20T09:00:00', status: 'SELESAI', kasir: 'Kasir A',
  tipePembayaran: 'TUNAI', subtotal: 51000, totalDiskon: 0, totalPajak: 0, grandTotal: 51000, dibayar: 100000, kembalian: 49000,
  items: [
    TrxItem(id: 'I1', nama: 'Kopi Susu', kuantitas: 2, harga: 18000, subtotal: 36000, satuan: 'cup', qtyBisaRefund: 2),
    TrxItem(id: 'I2', nama: 'Roti Bakar', kuantitas: 1, harga: 15000, subtotal: 15000, qtyRefund: 1, qtyBisaRefund: 0),
  ],
  totalRefund: 15000, nilaiBersih: 36000,
  refunds: [Refund(id: 'R0', nomor: 'RF-000001', total: 15000, alasan: 'Gosong', metodeNama: 'Tunai')],
);

class _RepoPalsu implements RiwayatRepository {
  PermintaanRefund? diterima;
  String? idRefund;
  @override
  Future<Result<List<Transaksi>>> list() async => const Ok([]);
  @override
  Future<Result<TransaksiDetail>> detail(String id) async => const Ok(_detail);
  @override
  Future<Result<void>> batal(String id) async => const Ok(null);
  @override
  Future<Result<Refund>> refund(String id, PermintaanRefund p) async {
    idRefund = id;
    diterima = p;
    return Ok(Refund(id: 'R1', nomor: 'RF-000002', total: 18000, metode: p.metode, alasan: p.alasan));
  }
}

ProviderContainer _wadah(_RepoPalsu repo, Set<String> akses) {
  final c = ProviderContainer(overrides: [
    riwayatRepositoryProvider.overrideWithValue(repo),
    aksesProvider.overrideWithValue(akses),
    koneksiProvider.overrideWith(() => KoneksiNotifier(jaringan: const Stream.empty())),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _buka(WidgetTester t, ProviderContainer c) async {
  t.view.physicalSize = const Size(420, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: DetailTransaksiScreen(id: 'T1')),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('dengan hak refund & batal: tombol Refund dan Batalkan tampil; blok refund & NILAI BERSIH di struk', (t) async {
    await _buka(t, _wadah(_RepoPalsu(), {'transaksi.refund', 'transaksi.batal'}));
    expect(find.text('Refund'), findsOneWidget);
    expect(find.text('Batalkan transaksi'), findsOneWidget);
    expect(find.textContaining('RF-000001'), findsWidgets);
    expect(find.text('NILAI BERSIH'), findsOneWidget);
  });

  testWidgets('tanpa hak dari server: tidak ada tombol Refund maupun Batalkan (gagal-tertutup)', (t) async {
    await _buka(t, _wadah(_RepoPalsu(), const {}));
    expect(find.text('Refund'), findsNothing);
    expect(find.text('Batalkan transaksi'), findsNothing);
  });

  testWidgets('lembar refund: hanya baris bersisa; isi qty & alasan → konfirmasi → kontrak terkirim, snackbar', (t) async {
    final repo = _RepoPalsu();
    await _buka(t, _wadah(repo, {'transaksi.refund'}));
    await t.tap(find.text('Refund'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('rf-qty-I1')), findsOneWidget);
    expect(find.byKey(const ValueKey('rf-qty-I2')), findsNothing, reason: 'Roti Bakar sudah habis direfund');

    await t.tap(find.text('Catat refund'));
    await t.pumpAndSettle();
    expect(find.text('Pilih minimal satu item yang direfund.'), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('rf-qty-I1')), '1');
    await t.enterText(find.byKey(const ValueKey('rf-alasan')), 'Tumpah');
    await t.pumpAndSettle();
    expect(find.textContaining('18.000'), findsWidgets, reason: 'perkiraan dana kembali');

    await t.tap(find.text('Catat refund'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ya, catat'));
    await t.pumpAndSettle();

    expect(repo.idRefund, 'T1');
    expect(repo.diterima!.baris.single.id, 'I1');
    expect(repo.diterima!.baris.single.kuantitas, 1);
    expect(repo.diterima!.alasan, 'Tumpah');
    expect(repo.diterima!.metode, 'TUNAI', reason: 'bawaan = metode transaksi');
    expect(repo.diterima!.kembaliStok, isTrue);
    expect(repo.diterima!.clientRef, isNotEmpty);
    expect(find.textContaining('Refund RF-000002 tercatat'), findsOneWidget);
  });
}
