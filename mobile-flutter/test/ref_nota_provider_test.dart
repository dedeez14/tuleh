// Fase 3 (2.33.0): ref nota dibuang saat toko aktif atau pengguna berganti — seperti keranjang —
// supaya muatan identik di toko/pengguna lain tidak memutar ulang nota yang lama di server.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuleh_pos/features/auth/domain/entities/user.dart';
import 'package:tuleh_pos/features/auth/presentation/controllers/auth_controller.dart';
import 'package:tuleh_pos/features/kasir/presentation/widgets/cart_sheet.dart';
import 'package:tuleh_pos/features/pesanan/domain/logic/ref_nota.dart';
import 'package:tuleh_pos/features/toko/presentation/providers/toko_providers.dart';

class _TokoAktifPalsu extends ActiveTokoNotifier {
  @override
  Future<String?> build() async => 'toko-a';

  @override
  Future<void> select(String id) async => state = AsyncData(id);
}

class _AuthPalsu extends AuthController {
  @override
  Future<User?> build() async => const User(id: 'A', name: 'Sari');

  void ganti(User u) => state = AsyncData(u);
}

void main() {
  late ProviderContainer c;
  const ref = RefNota(ref: 'ref-1', sidik: 'sidik-1');

  setUp(() async {
    c = ProviderContainer(overrides: [
      activeTokoIdProvider.overrideWith(_TokoAktifPalsu.new),
      authControllerProvider.overrideWith(_AuthPalsu.new),
    ]);
    await c.read(activeTokoIdProvider.future);
    await c.read(authControllerProvider.future);
    c.listen(refNotaProvider, (_, _) {});
    c.read(refNotaProvider.notifier).state = ref;
  });
  tearDown(() => c.dispose());

  test('ref bertahan selama toko & pengguna sama', () {
    expect(c.read(refNotaProvider), same(ref));
  });

  test('ganti toko aktif → ref nota dibuang', () async {
    await c.read(activeTokoIdProvider.notifier).select('toko-b');
    expect(c.read(refNotaProvider), isNull);
  });

  test('ganti pengguna → ref nota dibuang', () {
    (c.read(authControllerProvider.notifier) as _AuthPalsu).ganti(const User(id: 'B', name: 'Budi'));
    expect(c.read(refNotaProvider), isNull);
  });
}
