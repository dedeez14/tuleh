import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/core/storage/secure_storage.dart';
import 'package:tuleh_pos/core/theme/app_theme.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/auth/presentation/screens/login_screen.dart';
import 'package:tuleh_pos/features/demo/demo_session.dart';

/// Layar masuk — tata letak dan jalur Mode Demo.
/// Ukuran layar diuji dari ponsel kecil sampai tablet karena form yang meluber
/// (overflow) tidak menggagalkan build, hanya terlihat rusak di perangkat.

/// Penyimpanan tiruan di memori — `flutter_secure_storage` butuh kanal platform
/// yang tidak tersedia dalam test.
class _FakeStorage extends SecureStorage {
  _FakeStorage() : super(const FlutterSecureStorage());

  final Map<String, String> _mem = {};

  @override
  Future<String?> readToken() async => _mem['token'];

  @override
  Future<void> writeToken(String? value) async {
    if (value == null || value.isEmpty) {
      _mem.remove('token');
    } else {
      _mem['token'] = value;
    }
  }

  @override
  Future<String?> readActiveTokoId() async => _mem['toko'];

  @override
  Future<void> writeActiveTokoId(String? value) async {
    if (value == null || value.isEmpty) {
      _mem.remove('toko');
    } else {
      _mem['toko'] = value;
    }
  }

  @override
  Future<void> clearSession() async {
    _mem.remove('token');
    _mem.remove('toko');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpLogin(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.dark()
              : AppTheme.light(),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    container = ProviderContainer(
      overrides: [secureStorageProvider.overrideWithValue(_FakeStorage())],
    );
  });

  tearDown(() => container.dispose());

  group('tata letak', () {
    testWidgets('menampilkan merek, dua kolom, dan dua jalur masuk', (
      tester,
    ) async {
      await pumpLogin(tester);

      expect(find.text('Masuk ke akun'), findsOneWidget);
      expect(find.text('Email atau username'), findsOneWidget);
      expect(find.text('Kata sandi'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Masuk'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Coba Mode Demo'),
        findsOneWidget,
      );
      // Server yang dituju terlihat — transparansi ke pengguna.
      expect(find.textContaining('tatreport.com'), findsOneWidget);
    });

    testWidgets('nama perangkat disembunyikan sampai opsi lanjutan dibuka', (
      tester,
    ) async {
      await pumpLogin(tester);
      expect(find.text('Nama perangkat'), findsNothing);

      await tester.tap(find.text('Opsi lanjutan'));
      await tester.pumpAndSettle();
      expect(find.text('Nama perangkat'), findsOneWidget);
    });

    testWidgets('tanpa luberan tata letak di ponsel kecil sampai tablet', (
      tester,
    ) async {
      for (final size in const [
        Size(320, 640), // ponsel kecil
        Size(390, 844), // ponsel umum
        Size(430, 932), // ponsel besar
        Size(900, 1200), // tablet → tata letak dua kolom
        Size(1280, 800), // tablet mendatar
      ]) {
        await pumpLogin(tester, size: size);
        expect(
          tester.takeException(),
          isNull,
          reason: 'tidak ada luberan pada ${size.width.toInt()}x${size.height.toInt()}',
        );
      }
    });

    testWidgets('tata letak lebar menampilkan daftar keunggulan', (
      tester,
    ) async {
      await pumpLogin(tester, size: const Size(1000, 900));
      expect(find.text('Menyesuaikan bidang usaha'), findsOneWidget);
      expect(find.text('Pesanan terpantau'), findsOneWidget);
    });

    testWidgets('terbentuk juga pada tema gelap', (tester) async {
      await pumpLogin(tester, brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
      expect(find.text('Masuk ke akun'), findsOneWidget);
    });
  });

  group('validasi', () {
    testWidgets('form kosong menolak kirim dengan pesan per kolom', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.pumpAndSettle();

      expect(find.text('Email atau username wajib diisi.'), findsOneWidget);
      expect(find.text('Kata sandi wajib diisi.'), findsOneWidget);
      // Tidak masuk aplikasi.
      expect(container.read(authControllerProvider).valueOrNull, isNull);
    });

    testWidgets('sandi tersembunyi & bisa ditampilkan', (tester) async {
      await pumpLogin(tester);
      TextField sandi() => tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Kata sandi',
        ),
      );

      expect(sandi().obscureText, isTrue);
      await tester.tap(find.byTooltip('Tampilkan kata sandi'));
      await tester.pumpAndSettle();
      expect(sandi().obscureText, isFalse);
    });
  });

  group('Mode Demo', () {
    testWidgets('tombol demo masuk tanpa akun & tanpa jaringan', (
      tester,
    ) async {
      await pumpLogin(tester);
      expect(container.read(demoSessionProvider).active, isFalse);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Coba Mode Demo'));
      await tester.pumpAndSettle();

      expect(container.read(demoSessionProvider).active, isTrue);
      final user = container.read(authControllerProvider).valueOrNull;
      expect(user, isNotNull);
      expect(user!.name, 'Kasir Demo');
    });

    testWidgets('keluar mengakhiri demo', (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Coba Mode Demo'));
      await tester.pumpAndSettle();

      await container.read(authControllerProvider.notifier).logout();
      expect(container.read(demoSessionProvider).active, isFalse);
      expect(container.read(authControllerProvider).valueOrNull, isNull);
    });
  });
}
