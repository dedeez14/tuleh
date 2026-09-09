// Struk bon meja (2.20.0): membayar bon menghasilkan struk yang bisa dicetak,
// dibagikan, dan ikut cetak otomatis — sebelumnya bon dibayar tanpa struk.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/network/api_result.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/offline/antrean_tulis.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/cetak/data/printer_service.dart';
import 'package:tuleh_pos/features/cetak/domain/entities/struk.dart';
import 'package:tuleh_pos/features/cetak/presentation/providers/printer_providers.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/meja/domain/entities/bill_detail.dart';
import 'package:tuleh_pos/features/meja/domain/repositories/meja_repository.dart';
import 'package:tuleh_pos/features/meja/presentation/providers/meja_providers.dart';
import 'package:tuleh_pos/features/meja/presentation/screens/bill_detail_screen.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/features/products/presentation/providers/products_provider.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

import 'helpers/masa_coba_palsu.dart';

class _Storage extends SecureStorage {
  _Storage([Map<String, String>? awal]) : super(const FlutterSecureStorage()) {
    if (awal != null) _m.addAll(awal);
  }
  final Map<String, String> _m = {};
  @override
  Future<String?> readToken() async => _m['token'];
  @override
  Future<void> writeToken(String? v) async => v == null ? _m.remove('token') : _m['token'] = v;
  @override
  Future<String?> readActiveTokoId() async => _m['toko'];
  @override
  Future<void> writeActiveTokoId(String? v) async => v == null ? _m.remove('toko') : _m['toko'] = v;
  @override
  Future<String?> bacaNilai(String k) async => _m[k];
  @override
  Future<void> tulisNilai(String k, String? v) async => v == null ? _m.remove(k) : _m[k] = v;
  @override
  Future<void> clearSession() async {
    _m.remove('token');
    _m.remove('toko');
  }
}

class _PrinterPalsu implements PrinterService {
  final dicetak = <Struk>[];
  @override
  Future<void> cetak(Struk struk, {required PrinterTersimpan printer, Object? lebar}) async =>
      dicetak.add(struk);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _printer = PrinterTersimpan(nama: 'RPP02', mac: '00:11:22:33:44:55');

final _bon = BillDetail(
  id: 'B1',
  nomor: 'BON/0007',
  label: 'Meja 4',
  pax: 2,
  status: 'BUKA',
  total: 47000,
  items: const [
    BillItem(nama: 'Mie Ayam', kuantitas: 2, harga: 18000, subtotal: 36000),
    BillItem(nama: 'Es Teh', kuantitas: 2, harga: null, subtotal: 11000),
  ],
);

/// Repo bon palsu: detail tetap, `bayar` mengembalikan hasil yang diminta.
class _MejaPalsu implements MejaRepository {
  _MejaPalsu({this.tertunda = false, BillDetail? bon}) : bon = bon ?? _bon;
  final BillDetail bon;
  final bool tertunda;
  int panggilanBayar = 0;
  double? dibayarTerakhir;

  @override
  Future<Result<BillDetail>> detail(String billId) async => Ok(bon);

  @override
  Future<Result<HasilTulis>> bayar(String billId, {required String tipe, required double dibayar}) async {
    panggilanBayar++;
    dibayarTerakhir = dibayar;
    return Ok(tertunda ? HasilTulis(tertunda: true, clientRef: 'c1') : HasilTulis.langsung);
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pompa(WidgetTester t, [int kali = 20]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<ProviderContainer> wadah(
    WidgetTester t, {
    required _MejaPalsu meja,
    required _PrinterPalsu printer,
    bool otomatis = false,
    List<Product>? produk,
  }) async {
    late final ProviderContainer c;
    await t.runAsync(() async {
      c = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(
            _Storage({
              'printer_mac': _printer.mac,
              'printer_nama': _printer.nama,
              'printer_otomatis': otomatis ? '1' : '0',
            }),
          ),
          masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
          printerServiceProvider.overrideWithValue(printer),
          mejaRepositoryProvider.overrideWithValue(meja),
          if (produk != null) productsProvider.overrideWith((ref) async => produk),
          ...overrideOffline(antrean: AntreanMemori()),
        ],
      );
      await c.read(authControllerProvider.notifier).startDemo();
      await c.read(activeTokoIdProvider.notifier).select('TOKO-6');
      await c.read(printerTerpilihProvider.future);
    });
    addTearDown(c.dispose);
    return c;
  }

  Widget app(ProviderContainer c) => UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const BillDetailScreen(billId: 'B1', mejaNomor: '4'),
    ),
  );

  Future<void> bayar(WidgetTester t) async {
    await t.tap(find.widgetWithText(FilledButton, 'Bayar'));
    await _pompa(t);
    // Dialog "Bayar Tunai" → tombol Bayar di dalamnya.
    await t.tap(find.widgetWithText(FilledButton, 'Bayar').last);
    await _pompa(t, 30);
  }

  testWidgets('bayar bon menampilkan struk berisi item bon', (t) async {
    final meja = _MejaPalsu();
    final printer = _PrinterPalsu();
    final c = await wadah(t, meja: meja, printer: printer);
    await t.pumpWidget(app(c));
    await _pompa(t);

    await bayar(t);
    expect(meja.panggilanBayar, 1);
    expect(meja.dibayarTerakhir, 47000);
    // Lembar hasil merangkum: "BON/0007 · 4 item" (2 mie + 2 es teh).
    expect(find.textContaining('BON/0007'), findsWidgets, reason: 'nomor bon jadi nomor struk');
    expect(find.textContaining('4 item'), findsWidgets);
    expect(find.text('Cetak struk'), findsOneWidget);
    expect(find.text('Bagikan struk'), findsOneWidget);
    expect(printer.dicetak, isEmpty, reason: 'cetak otomatis mati');
  });

  testWidgets('cetak otomatis nyala: struk bon langsung dicetak', (t) async {
    final meja = _MejaPalsu();
    final printer = _PrinterPalsu();
    final c = await wadah(t, meja: meja, printer: printer, otomatis: true);
    await t.pumpWidget(app(c));
    await _pompa(t);

    await bayar(t);
    expect(printer.dicetak.single.nomor, 'BON/0007');
    // Harga baris tanpa `harga` dihitung dari subtotal ÷ kuantitas.
    final es = printer.dicetak.single.baris.firstWhere((b) => b.nama == 'Es Teh');
    expect(es.harga, 5500);
    expect(printer.dicetak.single.total, 47000);
  });

  testWidgets('bon berisi barang timbang: satuan ikut ke layar & struk', (t) async {
    // Sebelumnya baris pecahan tampil "0 × Rp 27.000" (kuantitas dipotong ke
    // int) dan struk cetak ulang kehilangan satuannya.
    final bon = BillDetail(
      id: 'B2',
      nomor: 'BON/0009',
      label: 'Meja 1',
      status: 'BUKA',
      total: 19980,
      items: const [
        BillItem(nama: 'Mangga Harum Manis', kuantitas: 0.74, harga: 27000, subtotal: 19980, satuan: 'Kg'),
      ],
    );
    final printer = _PrinterPalsu();
    final c = await wadah(t, meja: _MejaPalsu(bon: bon), printer: printer, otomatis: true);
    await t.pumpWidget(app(c));
    await _pompa(t);
    expect(find.textContaining('0,74 Kg × Rp 27.000'), findsOneWidget);

    await bayar(t);
    final baris = printer.dicetak.single.baris.single;
    expect(baris.labelKuantitas, '0,74 Kg');
    expect(printer.dicetak.single.jumlahItem, 1, reason: 'baris timbang = 1 item');
  });

  testWidgets('tambah pesanan barang timbang: tanya ukuran, bukan +1', (t) async {
    const kakap = Product(id: 'P-KAKAP', nama: 'Ikan Kakap', harga: 90000, satuan: 'kg', stok: 8);
    const nasi = Product(id: 'P-NASI', nama: 'Nasi Putih', harga: 6000, satuan: 'pcs');
    final c = await wadah(
      t,
      meja: _MejaPalsu(),
      printer: _PrinterPalsu(),
      produk: const [kakap, nasi],
    );
    await t.pumpWidget(app(c));
    await _pompa(t);
    await t.tap(find.widgetWithText(OutlinedButton, 'Tambah Pesanan'));
    await _pompa(t);

    // Barang hitungan: sekali ketuk = 1.
    await t.tap(find.widgetWithIcon(IconButton, Icons.add_circle).last);
    await _pompa(t);
    expect(find.textContaining('Kirim ke Dapur (1 item)'), findsOneWidget);

    // Barang per kilo: lembar ukuran, bukan langsung +1.
    await t.tap(find.widgetWithIcon(IconButton, Icons.add_circle).first);
    await _pompa(t);
    expect(find.text('Tambah ke pesanan'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '0,74');
    await _pompa(t);
    await t.tap(find.text('Tambah ke pesanan'));
    await _pompa(t);

    expect(find.text('0,74 kg'), findsOneWidget, reason: 'ukuran tampil di baris produk');
    expect(find.textContaining('Kirim ke Dapur (2 item)'), findsOneWidget,
        reason: 'baris timbang dihitung satu item');
  });

  testWidgets('bon dibayar offline: struk bertanda belum tersinkron', (t) async {
    final meja = _MejaPalsu(tertunda: true);
    final printer = _PrinterPalsu();
    final c = await wadah(t, meja: meja, printer: printer);
    await t.pumpWidget(app(c));
    await _pompa(t);

    await bayar(t);
    expect(find.text('Transaksi disimpan'), findsOneWidget);
    expect(find.textContaining('nomor sementara'), findsOneWidget);
  });
}
