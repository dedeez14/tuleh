import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/demo/data/masa_coba_service.dart';
import 'package:tuleh_pos/features/demo/presentation/demo_identitas_screen.dart';

import 'helpers/masa_coba_palsu.dart';

/// Layar verifikasi identitas (lapis 3 masa coba): render, ganti jenis,
/// validasi kolom kosong, dan pesan galat dari server tiruan (404 = layanan
/// belum ada) tanpa membekukan tombol.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pompa(WidgetTester t, {Size size = const Size(360, 780)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          masaCobaServiceProvider.overrideWithValue(MasaCobaPalsu()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DemoIdentitasScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('tampil dengan pilihan WhatsApp/Email dan tombol Kirim kode', (t) async {
    await pompa(t);
    expect(find.text('Verifikasi masa coba'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Nomor WhatsApp'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Kirim kode'), findsOneWidget);

    await t.tap(find.text('Email'));
    await t.pumpAndSettle();
    expect(find.text('Alamat email'), findsOneWidget);
  });

  testWidgets('kolom kosong ditolak; server tanpa endpoint memberi pesan, tombol tetap hidup', (t) async {
    await pompa(t);
    await t.tap(find.widgetWithText(FilledButton, 'Kirim kode'));
    await t.pumpAndSettle();
    expect(find.text('Isi nomor WhatsApp.'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, '081234567890');
    await t.tap(find.widgetWithText(FilledButton, 'Kirim kode'));
    await t.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 30));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await t.pumpAndSettle();
    expect(find.text('Layanan verifikasi belum tersedia di server.'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('tidak meluber di ponsel sempit', (t) async {
    await pompa(t, size: const Size(320, 560));
    expect(t.takeException(), isNull);
  });
}
