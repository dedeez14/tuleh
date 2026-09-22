// Persetujuan atasan di Detail Transaksi (Tahap B §2c): kasir TANPA hak batal/
// refund tetap melihat tombolnya — berlabel "(perlu persetujuan)" — dan
// menyelesaikannya dengan PIN atasan di perangkatnya. Token sekali pakai yang
// didapat ikut dikirim ke endpoint aksi, sekali saja: server MEMBAKAR token
// walau layanannya lalu menolak, jadi percobaan berikutnya minta persetujuan
// lagi. Persetujuan hanya hidup online (daftar pemberi + tukar PIN ke server).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/akses/akses.dart';
import 'package:tuleh_pos/core/network/api_exception.dart';
import 'package:tuleh_pos/core/network/api_result.dart';
import 'package:tuleh_pos/core/offline/koneksi.dart';
import 'package:tuleh_pos/features/keamanan/data/datasources/keamanan_remote_datasource.dart';
import 'package:tuleh_pos/features/keamanan/domain/entities/otorisasi.dart';
import 'package:tuleh_pos/features/keamanan/presentation/providers/keamanan_providers.dart';
import 'package:tuleh_pos/features/keamanan/presentation/widgets/dialog_otorisasi.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/refund.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/transaksi.dart';
import 'package:tuleh_pos/features/riwayat/domain/entities/transaksi_detail.dart';
import 'package:tuleh_pos/features/riwayat/domain/repositories/riwayat_repository.dart';
import 'package:tuleh_pos/features/riwayat/presentation/providers/riwayat_providers.dart';
import 'package:tuleh_pos/features/riwayat/presentation/screens/detail_transaksi_screen.dart';

const _detail = TransaksiDetail(
  id: 'T1',
  nomor: 'POS-000051',
  tanggal: '2026-09-21T09:00:00',
  status: 'SELESAI',
  kasir: 'Kasir A',
  tipePembayaran: 'TUNAI',
  subtotal: 20000,
  totalDiskon: 0,
  totalPajak: 0,
  grandTotal: 20000,
  dibayar: 20000,
  kembalian: 0,
  items: [TrxItem(id: 'I1', nama: 'Teh', kuantitas: 1, harga: 20000, subtotal: 20000, qtyBisaRefund: 1)],
);

class _Repo implements RiwayatRepository {
  _Repo({this.isi = _detail, this.galatBatal, this.galatRefund});

  TransaksiDetail isi;

  /// Penolakan layanan untuk panggilan batal PERTAMA (token tetap terbakar di server).
  ApiException? galatBatal;

  /// Penolakan layanan untuk panggilan refund PERTAMA (token tetap terbakar di server).
  ApiException? galatRefund;

  /// Bila diisi, jawaban refund ditahan sampai tes menyelesaikannya sendiri.
  Completer<Result<Refund>>? tundaRefund;

  /// Berapa kali detail ditarik — penyegaran sesudah lembar refund terlihat di sini.
  int detailDiminta = 0;

  /// Token yang ikut pada tiap panggilan, urut — dipakai memastikan tak ada token ulang.
  final tokenBatal = <String?>[];
  final tokenRefund = <String?>[];
  PermintaanRefund? permintaan;

  @override
  Future<Result<List<Transaksi>>> list() async => const Ok([]);

  @override
  Future<Result<TransaksiDetail>> detail(String id) async {
    detailDiminta += 1;
    return Ok(isi);
  }

  @override
  Future<Result<void>> batal(String id, {String? otorisasiToken}) async {
    tokenBatal.add(otorisasiToken);
    final e = galatBatal;
    if (e != null) {
      galatBatal = null;
      return Err<void>(e);
    }
    return const Ok(null);
  }

  @override
  Future<Result<Refund>> refund(String id, PermintaanRefund p) {
    tokenRefund.add(p.otorisasiToken);
    permintaan = p;
    final tahan = tundaRefund;
    if (tahan != null) return tahan.future;
    final e = galatRefund;
    if (e != null) {
      galatRefund = null;
      return Future.value(Err<Refund>(e));
    }
    return Future.value(const Ok(Refund(id: 'R1', nomor: 'RFD-1', total: 20000)));
  }
}

class _Keamanan extends KeamananRemoteDataSource {
  _Keamanan({
    this.daftar = const [PemberiOtorisasi(id: 'U1', nama: 'Manajer', peran: 'Manager')],
    this.galat,
    this.tunda = false,
  }) : super(Dio());

  final List<PemberiOtorisasi> daftar;

  /// Jawaban penolakan server untuk tukar PIN (PIN salah, 429, …).
  final ApiException? galat;

  /// true = jawaban ditahan sampai tes menyelesaikannya sendiri.
  final bool tunda;
  Completer<Otorisasi>? tertahan;

  final pinDipakai = <String>[];
  final aksiDiminta = <String>[];
  int terbit = 0;

  @override
  Future<List<PemberiOtorisasi>> pemberi() async => daftar;

  @override
  Future<Otorisasi> otorisasi({
    required String pemberiId,
    required String pin,
    required String aksi,
    required String transaksiId,
  }) {
    pinDipakai.add(pin);
    aksiDiminta.add(aksi);
    final e = galat;
    if (e != null) return Future<Otorisasi>.error(e);
    if (tunda) return (tertahan = Completer<Otorisasi>()).future;
    terbit += 1;
    return Future.value(Otorisasi(token: 'tok-$terbit', pemberiNama: 'Manajer'));
  }
}

/// Koneksi terkunci pada satu keadaan: `tandaiOffline()` asli menjadwalkan
/// pemeriksaan ulang 30 detik, dan timer menggantung menggagalkan tes widget.
class _Koneksi extends KoneksiNotifier {
  _Koneksi({this.mula = true}) : super(jaringan: const Stream.empty());

  final bool mula;

  @override
  StatusKoneksi build() {
    super.build();
    return StatusKoneksi(online: mula);
  }

  void setel({required bool online}) => state = StatusKoneksi(online: online);
}

ProviderContainer _wadah({
  required _Repo repo,
  _Keamanan? keamanan,
  Set<String> akses = const {'kasir.transaksi'},
  _Koneksi? koneksi,
}) {
  final c = ProviderContainer(
    overrides: [
      riwayatRepositoryProvider.overrideWithValue(repo),
      keamananDataSourceProvider.overrideWithValue(keamanan ?? _Keamanan()),
      aksesProvider.overrideWithValue(akses),
      koneksiProvider.overrideWith(() => koneksi ?? _Koneksi()),
    ],
  );
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

Future<void> _ketuk(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

/// Lembar refund menyalakan pemuatan SEBELUM dialog konfirmasi, jadi ada
/// CircularProgressIndicator yang berputar terus — pumpAndSettle tak pernah usai.
Future<void> _pompa(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 500));
}

const _labelBatal = 'Batalkan transaksi (perlu persetujuan)';

void main() {
  testWidgets('kasir tanpa hak: tombol berlabel perlu persetujuan; PIN atasan → token ikut terkirim', (t) async {
    final repo = _Repo();
    final keamanan = _Keamanan();
    await _buka(t, _wadah(repo: repo, keamanan: keamanan));

    expect(find.text(_labelBatal), findsOneWidget);
    await _ketuk(t, find.text(_labelBatal));
    await _ketuk(t, find.text('Ya, batalkan'));

    expect(find.text('Minta persetujuan'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('ot-pin')), '2468');
    await _ketuk(t, find.text('Setujui'));

    expect(keamanan.pinDipakai, ['2468']);
    expect(keamanan.aksiDiminta, ['transaksi.batal']);
    expect(repo.tokenBatal, ['tok-1']);
    expect(find.text('Minta persetujuan'), findsNothing, reason: 'dialog tertutup setelah token terbit');
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('pemegang hak: label biasa, tanpa dialog persetujuan, token null', (t) async {
    final repo = _Repo();
    final keamanan = _Keamanan();
    await _buka(t, _wadah(repo: repo, keamanan: keamanan, akses: {'transaksi.batal'}));

    expect(find.text('Batalkan transaksi'), findsOneWidget);
    await _ketuk(t, find.text('Batalkan transaksi'));
    await _ketuk(t, find.text('Ya, batalkan'));

    expect(find.text('Minta persetujuan'), findsNothing);
    expect(keamanan.pinDipakai, isEmpty);
    expect(repo.tokenBatal, [null]);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('belum ada atasan ber-PIN: alasannya dijelaskan, formulir PIN tidak ditawarkan', (t) async {
    final repo = _Repo();
    await _buka(t, _wadah(repo: repo, keamanan: _Keamanan(daftar: const [])));

    await _ketuk(t, find.text(_labelBatal));
    await _ketuk(t, find.text('Ya, batalkan'));

    expect(find.text('Minta persetujuan'), findsNothing);
    expect(find.textContaining('Belum ada atasan yang menyetel PIN persetujuan'), findsOneWidget);
    expect(repo.tokenBatal, isEmpty, reason: 'tanpa pemberi, aksinya tidak dijalankan');
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('PIN salah: kalimat server tampil di dialog, dialog tetap terbuka, aksi tidak jalan', (t) async {
    final repo = _Repo();
    await _buka(t, _wadah(
      repo: repo,
      keamanan: _Keamanan(galat: const ApiException(message: 'PIN salah. Sisa percobaan: 4.', statusCode: 422)),
    ));

    await _ketuk(t, find.text(_labelBatal));
    await _ketuk(t, find.text('Ya, batalkan'));
    await t.enterText(find.byKey(const ValueKey('ot-pin')), '1111');
    await _ketuk(t, find.text('Setujui'));

    expect(find.text('PIN salah. Sisa percobaan: 4.'), findsOneWidget);
    expect(find.text('Minta persetujuan'), findsOneWidget);
    expect(repo.tokenBatal, isEmpty);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('dialog ditutup selagi permintaan melayang: jawaban telat tak mengaku sukses', (t) async {
    final repo = _Repo();
    final keamanan = _Keamanan(tunda: true);
    await _buka(t, _wadah(repo: repo, keamanan: keamanan));

    await _ketuk(t, find.text(_labelBatal));
    await _ketuk(t, find.text('Ya, batalkan'));
    await t.enterText(find.byKey(const ValueKey('ot-pin')), '2468');
    await t.tap(find.text('Setujui'));
    await t.pump();
    expect(find.text('Memeriksa…'), findsOneWidget);

    // Ditutup lewat overlay selagi server belum menjawab.
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.text('Minta persetujuan'), findsNothing);

    keamanan.tertahan!.complete(const Otorisasi(token: 'tok-telat', pemberiNama: 'Manajer'));
    await t.pumpAndSettle();

    expect(repo.tokenBatal, isEmpty, reason: 'pemanggil sudah berhenti — tak ada yang dibatalkan');
    expect(find.textContaining('dibatalkan.'), findsNothing);
    expect(find.text('POS-000051'), findsOneWidget, reason: 'layar detail tidak ikut ter-pop');
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('offline: tombol mati dengan alasan persetujuan, dan konfirmasi merusak tak dibuka', (t) async {
    final repo = _Repo();
    final keamanan = _Keamanan();
    await _buka(t, _wadah(repo: repo, keamanan: keamanan, koneksi: _Koneksi(mula: false)));

    final tombol = find.widgetWithText(OutlinedButton, _labelBatal);
    expect(t.widget<OutlinedButton>(tombol).enabled, isFalse);
    expect(find.text('Persetujuan atasan hanya bisa diminta saat terhubung ke internet.'), findsWidgets);
    await _ketuk(t, tombol);
    expect(find.text('Batalkan transaksi ini?'), findsNothing);
  });

  testWidgets('koneksi putus setelah konfirmasi: persetujuan tidak diminta, aksi tidak jalan', (t) async {
    final repo = _Repo();
    final keamanan = _Keamanan();
    final koneksi = _Koneksi();
    await _buka(t, _wadah(repo: repo, keamanan: keamanan, koneksi: koneksi));

    await _ketuk(t, find.text(_labelBatal));
    expect(find.text('Batalkan transaksi ini?'), findsOneWidget);
    koneksi.setel(online: false);
    await t.pumpAndSettle();
    await _ketuk(t, find.text('Ya, batalkan'));

    expect(find.text('Minta persetujuan'), findsNothing);
    expect(keamanan.pinDipakai, isEmpty);
    expect(repo.tokenBatal, isEmpty);
    expect(find.text('Persetujuan atasan hanya bisa diminta saat terhubung ke internet.'), findsWidgets);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('layanan menolak: token tidak dipakai ulang — percobaan kedua minta persetujuan lagi', (t) async {
    final repo = _Repo(galatBatal: const ApiException(message: 'Transaksi sudah dibatalkan.', statusCode: 409));
    final keamanan = _Keamanan();
    await _buka(t, _wadah(repo: repo, keamanan: keamanan));

    await _ketuk(t, find.text(_labelBatal));
    await _ketuk(t, find.text('Ya, batalkan'));
    await t.enterText(find.byKey(const ValueKey('ot-pin')), '2468');
    await _ketuk(t, find.text('Setujui'));
    expect(find.text('Transaksi sudah dibatalkan.'), findsOneWidget, reason: 'kalimat server apa adanya');

    await _ketuk(t, find.text(_labelBatal));
    await _ketuk(t, find.text('Ya, batalkan'));
    expect(find.text('Minta persetujuan'), findsOneWidget, reason: 'token lama sudah dibakar server');
    await t.enterText(find.byKey(const ValueKey('ot-pin')), '2468');
    await _ketuk(t, find.text('Setujui'));

    expect(repo.tokenBatal, ['tok-1', 'tok-2']);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('refund tanpa hak: token dicetak saat KIRIM, bukan saat lembar dibuka', (t) async {
    final repo = _Repo();
    final keamanan = _Keamanan();
    await _buka(t, _wadah(repo: repo, keamanan: keamanan));

    expect(find.text('Refund (perlu persetujuan)'), findsOneWidget);
    await _ketuk(t, find.text('Refund (perlu persetujuan)'));

    // Token berumur 300 detik di server: dicetak di muka, ia bisa mati selagi
    // kasir mengisi lembar dan permintaannya berakhir 403 "tidak berhak".
    expect(find.byKey(const ValueKey('rf-qty-I1')), findsOneWidget, reason: 'lembar langsung terbuka');
    expect(find.text('Minta persetujuan'), findsNothing);
    expect(keamanan.aksiDiminta, isEmpty, reason: 'belum ada token yang bisa basi');

    await t.enterText(find.byKey(const ValueKey('rf-qty-I1')), '1');
    await t.enterText(find.byKey(const ValueKey('rf-alasan')), 'Tumpah');
    await t.pumpAndSettle();
    await t.tap(find.text('Catat refund'));
    await _pompa(t);
    await t.tap(find.text('Ya, catat'));
    await _pompa(t);

    expect(find.text('Minta persetujuan'), findsOneWidget, reason: 'PIN diminta tepat sebelum dikirim');
    await t.enterText(find.byKey(const ValueKey('ot-pin')), '2468');
    await t.tap(find.text('Setujui'));
    await _pompa(t);

    expect(keamanan.aksiDiminta, ['transaksi.refund']);
    expect(repo.tokenRefund, ['tok-1']);
    expect(repo.permintaan!.otorisasiToken, 'tok-1');
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('refund ditolak layanan: percobaan kedua mencetak token BARU, bukan mengirim yang mati', (t) async {
    final repo = _Repo(galatRefund: const ApiException(message: 'Jumlah refund melebihi sisa.', statusCode: 422));
    final keamanan = _Keamanan();
    await _buka(t, _wadah(repo: repo, keamanan: keamanan));

    await _ketuk(t, find.text('Refund (perlu persetujuan)'));
    await t.enterText(find.byKey(const ValueKey('rf-qty-I1')), '1');
    await t.enterText(find.byKey(const ValueKey('rf-alasan')), 'Tumpah');
    await t.pumpAndSettle();

    Future<void> kirim(String pin) async {
      await t.tap(find.text('Catat refund'));
      await _pompa(t);
      await t.tap(find.text('Ya, catat'));
      await _pompa(t);
      expect(find.text('Minta persetujuan'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('ot-pin')), pin);
      await t.tap(find.text('Setujui'));
      await _pompa(t);
    }

    await kirim('2468');
    expect(find.text('Jumlah refund melebihi sisa.'), findsOneWidget);
    await kirim('2468');

    expect(repo.tokenRefund, ['tok-1', 'tok-2'], reason: 'token terbakar walau ditolak — yang kedua harus baru');
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('koneksi putus selagi lembar refund terbuka: konfirmasi merusak tak dibuka', (t) async {
    final repo = _Repo();
    final keamanan = _Keamanan();
    final koneksi = _Koneksi();
    await _buka(t, _wadah(repo: repo, keamanan: keamanan, akses: {'transaksi.refund'}, koneksi: koneksi));

    await _ketuk(t, find.text('Refund'));
    await t.enterText(find.byKey(const ValueKey('rf-qty-I1')), '1');
    await t.enterText(find.byKey(const ValueKey('rf-alasan')), 'Tumpah');
    await t.pumpAndSettle();

    koneksi.setel(online: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Catat refund'));
    await _pompa(t);

    expect(find.text('Catat refund?'), findsNothing, reason: 'jangan minta kasir menyetujui aksi merusak yang pasti gagal');
    expect(repo.tokenRefund, isEmpty);
    expect(
      find.widgetWithText(SnackBar, 'Refund hanya bisa dilakukan saat terhubung ke internet.'),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('lembar ditutup selagi POST melayang: detail tetap disegarkan', (t) async {
    final repo = _Repo();
    repo.tundaRefund = Completer<Result<Refund>>();
    await _buka(t, _wadah(repo: repo, akses: {'transaksi.refund'}));
    final sebelum = repo.detailDiminta;

    await _ketuk(t, find.text('Refund'));
    await t.enterText(find.byKey(const ValueKey('rf-qty-I1')), '1');
    await t.enterText(find.byKey(const ValueKey('rf-alasan')), 'Tumpah');
    await t.pumpAndSettle();
    await t.tap(find.text('Catat refund'));
    await _pompa(t);
    await t.tap(find.text('Ya, catat'));
    await _pompa(t);
    expect(repo.tokenRefund, [null], reason: 'POST sudah melayang');

    // Kasir menutup lembar sebelum jawaban datang: refundnya MUNGKIN tercatat.
    await t.tapAt(const Offset(5, 5));
    await _pompa(t);
    repo.tundaRefund!.complete(const Ok(Refund(id: 'R1', nomor: 'RFD-1', total: 20000)));
    await _pompa(t);

    expect(repo.detailDiminta, greaterThan(sebelum), reason: 'tanpa ini refund yang tercatat tak terlihat sampai disegarkan manual');
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('penyetuju tampil di struk dan di baris refund', (t) async {
    final repo = _Repo(
      isi: const TransaksiDetail(
        id: 'T1',
        nomor: 'POS-000052',
        tanggal: '2026-09-21T09:00:00',
        status: 'DIBATALKAN',
        kasir: 'Kasir A',
        tipePembayaran: 'TUNAI',
        subtotal: 20000,
        totalDiskon: 0,
        totalPajak: 0,
        grandTotal: 20000,
        dibayar: 20000,
        kembalian: 0,
        disetujuiOleh: 'Manajer Toko',
        items: [TrxItem(id: 'I1', nama: 'Teh', kuantitas: 1, harga: 20000, subtotal: 20000)],
        totalRefund: 5000,
        refunds: [Refund(id: 'R0', nomor: 'RFD-9', total: 5000, disetujuiOleh: 'Bu Owner')],
      ),
    );
    await _buka(t, _wadah(repo: repo));

    expect(find.text('Disetujui'), findsOneWidget);
    expect(find.text('Manajer Toko'), findsOneWidget);
    expect(find.textContaining('Disetujui: Bu Owner'), findsOneWidget);
  });

  testWidgets('layar sempit: nama penyetuju panjang tidak meluap dari baris struk', (t) async {
    final repo = _Repo(
      isi: const TransaksiDetail(
        id: 'T1',
        nomor: 'POS-000053',
        tanggal: '2026-09-21T09:00:00',
        status: 'DIBATALKAN',
        kasir: 'Kasir A',
        tipePembayaran: 'TUNAI',
        subtotal: 20000,
        totalDiskon: 0,
        totalPajak: 0,
        grandTotal: 20000,
        dibayar: 20000,
        kembalian: 0,
        disetujuiOleh: 'Ibu Siti Nurhaliza Rahmawati Kusumaningrum Manajer Toko Cabang Pusat',
        items: [TrxItem(id: 'I1', nama: 'Teh', kuantitas: 1, harga: 20000, subtotal: 20000)],
      ),
    );
    // Lebar telepon sempit (420 logis) — nama sepanjang ini harus dipotong,
    // bukan meluap: RenderFlex overflow membuat tes widget gagal.
    await _buka(t, _wadah(repo: repo));

    expect(find.text('Disetujui'), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'RenderFlex overflow = baris nilai tanpa Expanded');
  });

  group('label & alasan (murni)', () {
    test('label memberi tahu sebelum ditekan bahwa atasan akan diminta', () {
      expect(labelAksi('Refund', punyaHak: true), 'Refund');
      expect(labelAksi('Refund', punyaHak: false), 'Refund (perlu persetujuan)');
    });

    test('alasan offline menyebut persetujuan bagi yang tak punya hak', () {
      expect(alasanOffline('Pembatalan', punyaHak: true), startsWith('Pembatalan hanya bisa'));
      expect(alasanOffline('Pembatalan', punyaHak: false), startsWith('Persetujuan atasan'));
    });

    test('isian dialog: pemberi wajib dipilih, PIN 4–8 digit angka', () {
      expect(galatIsianOtorisasi(pemberiId: '', pin: '2468'), 'Pilih pemberi persetujuan lebih dulu.');
      expect(galatIsianOtorisasi(pemberiId: 'U1', pin: '123'), 'PIN harus 4–8 digit angka.');
      expect(galatIsianOtorisasi(pemberiId: 'U1', pin: 'abcd'), 'PIN harus 4–8 digit angka.');
      expect(galatIsianOtorisasi(pemberiId: 'U1', pin: '2468'), isNull);
    });
  });
}
