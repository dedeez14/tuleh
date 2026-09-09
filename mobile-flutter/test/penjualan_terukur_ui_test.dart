// Alur penjualan terukur di kasir Android: ketuk buah per kilo → lembar ukuran,
// isi berat ATAU nominal, keranjang berisi berat yang benar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/kasir/domain/entities/cart_item.dart';
import 'package:tuleh_pos/features/kasir/presentation/controllers/cart_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/lembar_ukuran.dart';
import 'package:tuleh_pos/features/products/domain/entities/product.dart';
import 'package:tuleh_pos/core/offline/antrean.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'helpers/masa_coba_palsu.dart';

/// Penyimpanan in-memory: CartController menonton toko aktif & akun saat dibuat.
class _Storage extends SecureStorage {
  _Storage() : super(const FlutterSecureStorage());
  @override
  Future<String?> readToken() async => null;
  @override
  Future<String?> readActiveTokoId() async => 'TOKO-1';
}

ProviderContainer _wadah() => ProviderContainer(
  overrides: [
    secureStorageProvider.overrideWithValue(_Storage()),
    masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
    ...overrideOffline(antrean: AntreanMemori()),
  ],
);

const _mangga = Product(
  id: 'P-MANGGA',
  nama: 'Mangga Harum Manis',
  harga: 27000,
  satuan: 'kg',
  stok: 50,
);
const _teh = Product(id: 'P-TEH', nama: 'Teh Botol', harga: 5000, satuan: 'pcs', stok: 20);

Future<void> _pompa(WidgetTester t, [int kali = 12]) async {
  for (var i = 0; i < kali; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Halaman uji yang membuka lembar ukuran dan menyimpan hasilnya.
class _Halaman extends StatefulWidget {
  const _Halaman({super.key, required this.produk, this.qtyAwal});
  final Product produk;
  final double? qtyAwal;

  @override
  State<_Halaman> createState() => _HalamanState();
}

class _HalamanState extends State<_Halaman> {
  IsianUkuran? hasil;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async {
          final r = await tanyaUkuran(context, widget.produk, qtyAwal: widget.qtyAwal);
          if (mounted) setState(() => hasil = r);
        },
        child: const Text('buka'),
      ),
    ),
  );
}

void main() {
  Future<_HalamanState> buka(WidgetTester t, {Product? produk, double? qtyAwal}) async {
    final kunci = GlobalKey<_HalamanState>();
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: _Halaman(key: kunci, produk: produk ?? _mangga, qtyAwal: qtyAwal),
    ));
    await t.tap(find.text('buka'));
    await _pompa(t);
    return kunci.currentState!;
  }

  group('lembar ukuran', () {
    testWidgets('mengisi berat: keranjang memakai berat itu', (t) async {
      final st = await buka(t);
      expect(find.textContaining('Rp 27.000 / kg'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '0,74');
      await _pompa(t);
      // Perhitungan tampil sebelum ditambahkan, supaya kasir bisa menyebutkannya.
      expect(find.textContaining('0,74 kg × Rp 27.000'), findsOneWidget);
      expect(find.text('Rp 19.980'), findsOneWidget);

      await t.tap(find.text('Tambah ke keranjang'));
      await _pompa(t);
      expect(st.hasil!.qty, 0.74);
      expect(st.hasil!.cara, CaraInput.ukuran);
      expect(st.hasil!.nominalDiminta, isNull);
    });

    testWidgets('"beli Rp 20.000": berat dihitung & tagihan tak melebihi nominal', (t) async {
      final st = await buka(t);
      await t.tap(find.text('Nominal'));
      await _pompa(t);

      await t.enterText(find.byType(TextField).first, '20000');
      await _pompa(t);
      expect(find.textContaining('Diminta Rp 20.000'), findsOneWidget);
      expect(find.textContaining('0,74 kg × Rp 27.000'), findsOneWidget);
      expect(find.text('Rp 19.980'), findsOneWidget);

      await t.tap(find.text('Tambah ke keranjang'));
      await _pompa(t);
      expect(st.hasil!.qty, 0.74);
      expect(st.hasil!.cara, CaraInput.nominal);
      expect(st.hasil!.nominalDiminta, 20000);
    });

    testWidgets('nominal di bawah satu langkah: ditolak dengan menyebut minimalnya', (t) async {
      await buka(t);
      await t.tap(find.text('Nominal'));
      await _pompa(t);
      await t.enterText(find.byType(TextField).first, '200');
      await _pompa(t);

      expect(find.textContaining('Minimal Rp 270'), findsOneWidget);
      final tombol = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Tambah ke keranjang'),
      );
      expect(tombol.onPressed, isNull, reason: 'tidak bisa menambah baris nol');
    });

    testWidgets('sisa stok tampil dan ukuran di atasnya ditahan', (t) async {
      // Desktop menahan lewat toast; Android harus konsisten — kasir jangan
      // sampai menimbang 1,2 kg lalu keranjang diam-diam berisi 0,8 kg.
      const menipis = Product(
        id: 'P-SALAK',
        nama: 'Salak Pondoh',
        harga: 20000,
        satuan: 'kg',
        stok: 0.8,
      );
      await buka(t, produk: menipis);
      expect(find.text('Sisa stok 0,8 kg'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '1,2');
      await _pompa(t);
      expect(find.textContaining('Sisa stok hanya 0,8 kg'), findsOneWidget);
      expect(
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Tambah ke keranjang')).onPressed,
        isNull,
      );

      await t.enterText(find.byType(TextField).first, '0,8');
      await _pompa(t);
      expect(
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Tambah ke keranjang')).onPressed,
        isNotNull,
        reason: 'menjual tepat sisa stok tetap boleh',
      );
    });

    testWidgets('produk tanpa kelola stok: tak ada batas', (t) async {
      await buka(t, produk: const Product(id: 'J', nama: 'Kain Meteran', harga: 15000, satuan: 'meter'));
      expect(find.textContaining('Sisa stok'), findsNothing);
      await t.enterText(find.byType(TextField).first, '99');
      await _pompa(t);
      expect(
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Tambah ke keranjang')).onPressed,
        isNotNull,
      );
    });

    testWidgets('harga 0: tab Nominal dimatikan', (t) async {
      await buka(t, produk: const Product(id: 'X', nama: 'Sayur', harga: 0, satuan: 'kg'));
      final segmen = t.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
      final nominal = segmen.segments.firstWhere((s) => s.value == true);
      expect(nominal.enabled, isFalse);
    });

    testWidgets('mengubah baris: nilai lama terisi lebih dulu', (t) async {
      await buka(t, qtyAwal: 1.5);
      expect(find.text('1,5'), findsOneWidget);
      expect(find.text('Simpan perubahan'), findsOneWidget);
    });
  });

  group('keranjang', () {
    test('tambahUkuran mengganti isi baris terukur, tidak menumpuk', () {
      final c = _wadah();
      addTearDown(c.dispose);
      final cart = c.read(cartControllerProvider.notifier);

      cart.tambahUkuran(_mangga, 0.74, cara: CaraInput.nominal, nominalDiminta: 20000, ganti: true);
      cart.tambahUkuran(_mangga, 1.2, cara: CaraInput.ukuran, ganti: true);

      final baris = c.read(cartControllerProvider).single;
      expect(baris.qty, 1.2, reason: 'timbang ulang mengganti, bukan menambah');
      expect(baris.cara, CaraInput.ukuran);
      expect(baris.subtotal, 32400);
      expect(baris.labelQty, '1,2 kg');
    });

    test('barang hitungan tetap bertambah 1 tiap ketukan', () {
      final c = _wadah();
      addTearDown(c.dispose);
      final cart = c.read(cartControllerProvider.notifier);
      cart..add(_teh)..add(_teh);
      final baris = c.read(cartControllerProvider).single;
      expect(baris.qty, 2);
      expect(baris.terukur, isFalse);
      expect(baris.labelQty, '2');
    });

    test('jumlah item: baris terukur dihitung satu', () {
      final c = _wadah();
      addTearDown(c.dispose);
      final cart = c.read(cartControllerProvider.notifier);
      cart.tambahUkuran(_mangga, 0.74, ganti: true);
      cart..add(_teh)..add(_teh);
      expect(c.read(cartCountProvider), 3, reason: '1 baris mangga + 2 teh');
      expect(c.read(cartTotalProvider), 19980 + 10000);
    });
  });
}
