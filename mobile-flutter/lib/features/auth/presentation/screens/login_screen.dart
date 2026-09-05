import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_config.dart';
import '../../../../core/network/api_exception.dart';
import '../../../demo/domain/masa_coba.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_background.dart' show PolaTitikPainter;
import '../../../../core/widgets/splash_screen.dart' show BrandAssets;
import '../controllers/auth_controller.dart';

/// Layar masuk — panel merek + satu kartu form.
///
/// Hierarki sengaja dijaga tipis: merek di atas (identitas), satu blok form
/// (tugas utama), lalu jalur sekunder (Mode Demo) dan keterangan server.
/// Kolom yang jarang dipakai (nama perangkat) disembunyikan di "Opsi lanjutan"
/// agar form utama tinggal dua kolom dan terbaca sekali lihat.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _device = TextEditingController(text: 'Android');

  late final AnimationController _entryController;
  late final Animation<double> _brandAnimation;
  late final Animation<double> _formAnimation;

  bool _obscure = true;
  bool _opsiLanjutan = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _brandAnimation = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
    );
    _formAnimation = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.16, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion) {
      _entryController.value = 1;
    } else if (_entryController.status == AnimationStatus.dismissed) {
      _entryController.forward();
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _login.dispose();
    _password.dispose();
    _device.dispose();
    super.dispose();
  }

  bool get _reduceMotion {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;
    return media.disableAnimations || media.accessibleNavigation;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final device = _device.text.trim();
    await ref
        .read(authControllerProvider.notifier)
        .login(
          login: _login.text.trim(),
          password: _password.text,
          deviceName: device.isEmpty ? 'Android' : device,
        );
  }

  Future<void> _mulaiDemo() async {
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).startDemo();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (prev, next) {
      if (next is AsyncError) {
        final e = next.error;
        if (e is MasaCobaException) {
          switch (e.status.kode) {
            case KodeMasaCoba.butuhIdentitas:
              context.go('/demo-identitas');
              return;
            case KodeMasaCoba.berakhir:
            case KodeMasaCoba.diblokir:
            case KodeMasaCoba.rusak:
              context.go('/demo-berakhir');
              return;
            case KodeMasaCoba.butuhKoneksi:
            case KodeMasaCoba.aktif:
              break;
          }
        }
        final msg = e is ApiException
            ? (e.firstError() ?? e.message)
            : e is MasaCobaException
            ? e.pesan
            : 'Gagal masuk.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
          );
      }
    });

    final loading = ref.watch(authControllerProvider).isLoading;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: DecoratedBox(
        // Latar: semburat mint di puncak layar, meredup ke warna dasar tema.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [AppColors.mint900, AppColors.bgDark]
                : [AppColors.mint100, AppColors.bgLight],
            stops: const [0, 0.42],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: PolaTitikPainter(
                    warna: isDark ? AppColors.mint400 : AppColors.mint700,
                    alphaMaks: isDark ? 0.22 : 0.2,
                    tinggiPudar: 0.7,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 860;

                  final brand = _Brand(compact: !isWide);
                  final form = _formCard(loading: loading, cs: cs);
                  final footer = _ServerFooter(host: _host());

                  if (isWide) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(
                            28,
                            24,
                            28,
                            24 + bottomInset,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 5,
                                child: _entry(
                                  _brandAnimation,
                                  brand,
                                  begin: const Offset(-0.03, 0),
                                ),
                              ),
                              const SizedBox(width: 40),
                              Expanded(
                                flex: 5,
                                child: _entry(
                                  _formAnimation,
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      form,
                                      const SizedBox(height: 14),
                                      footer,
                                    ],
                                  ),
                                  begin: const Offset(0.03, 0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          20,
                          28,
                          20,
                          20 + bottomInset,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _entry(_brandAnimation, brand),
                            const SizedBox(height: 26),
                            _entry(
                              _formAnimation,
                              form,
                              begin: const Offset(0, 0.05),
                            ),
                            const SizedBox(height: 14),
                            _entry(_formAnimation, footer),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _host() =>
      Uri.tryParse(AppConfig.defaultBaseUrl)?.host ?? AppConfig.defaultBaseUrl;

  Widget _entry(
    Animation<double> animation,
    Widget child, {
    Offset begin = const Offset(0, 0.035),
  }) {
    if (_reduceMotion) return child;
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: begin,
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _formCard({required bool loading, required ColorScheme cs}) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Masuk ke akun',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Gunakan akun POS toko Anda.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _login,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                enabled: !loading,
                decoration: const InputDecoration(
                  labelText: 'Email atau username',
                  hintText: 'kasir@toko.com',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Email atau username wajib diisi.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                enabled: !loading,
                onFieldSubmitted: (_) => loading ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Kata sandi',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? 'Tampilkan kata sandi'
                        : 'Sembunyikan kata sandi',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Kata sandi wajib diisi.' : null,
              ),
              _OpsiLanjutan(
                terbuka: _opsiLanjutan,
                onToggle: () => setState(() => _opsiLanjutan = !_opsiLanjutan),
                child: TextFormField(
                  controller: _device,
                  textInputAction: TextInputAction.done,
                  enabled: !loading,
                  decoration: const InputDecoration(
                    labelText: 'Nama perangkat',
                    hintText: 'Kasir-01',
                    helperText: 'Muncul di daftar perangkat yang masuk.',
                    prefixIcon: Icon(Icons.smartphone_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: loading ? null : _submit,
                child: loading
                    ? const SizedBox(
                        height: 21,
                        width: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.mint900,
                        ),
                      )
                    : const Text('Masuk'),
              ),
              const SizedBox(height: 20),
              _Pemisah(label: 'atau', color: cs.outline),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: loading ? null : _mulaiDemo,
                icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                label: const Text('Coba Mode Demo'),
              ),
              const SizedBox(height: 10),
              Text(
                'Jelajahi enam toko contoh tanpa akun. Data simulasi tersimpan '
                'di perangkat ini saja.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel merek — logo, wordmark, dan janji produk.
class _Brand extends StatelessWidget {
  const _Brand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onMint = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : AppColors.mint900;

    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        // Logo Tuléh (notepad + pensil) — aset yang sama dengan desktop dan
        // ikon peluncur, bukan ikon generik.
        Image.asset(
          BrandAssets.icon,
          height: compact ? 64 : 80,
          fit: BoxFit.contain,
          semanticLabel: 'Logo Tuléh',
        ),
        SizedBox(height: compact ? 18 : 26),
        // Text.rich (bukan RichText) agar wordmark ikut tipografi tema.
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Tul'),
              TextSpan(
                text: 'éh',
                style: TextStyle(color: cs.primary),
              ),
            ],
          ),
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 36 : 46,
            fontWeight: FontWeight.w800,
            height: 1.02,
            letterSpacing: -1,
            color: onMint,
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          compact
              ? 'Kasir cepat, laporan rapi, dalam genggaman.'
              : 'Kasir cepat, laporan rapi, dan pesanan terpantau — '
                    'satu aplikasi untuk semua bidang usaha.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 14 : 16,
            height: 1.5,
            color: cs.onSurface.withValues(alpha: 0.62),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 26),
          const _Keunggulan(
            icon: Icons.storefront_outlined,
            judul: 'Menyesuaikan bidang usaha',
            detail: 'Menu dan alur kerja mengikuti jenis toko Anda.',
          ),
          const SizedBox(height: 14),
          const _Keunggulan(
            icon: Icons.view_kanban_outlined,
            judul: 'Pesanan terpantau',
            detail: 'Papan tahapan dari antrian sampai siap diambil.',
          ),
          const SizedBox(height: 14),
          const _Keunggulan(
            icon: Icons.lock_outline_rounded,
            judul: 'Akses aman',
            detail: 'Token tersimpan terenkripsi di perangkat.',
          ),
        ],
      ],
    );
  }
}

class _Keunggulan extends StatelessWidget {
  const _Keunggulan({
    required this.icon,
    required this.judul,
    required this.detail,
  });

  final IconData icon;
  final String judul;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: cs.primary),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                judul,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bagian opsional yang dilipat — menjaga form utama tetap dua kolom.
class _OpsiLanjutan extends StatelessWidget {
  const _OpsiLanjutan({
    required this.terbuka,
    required this.onToggle,
    required this.child,
  });

  final bool terbuka;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurface.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            icon: AnimatedRotation(
              turns: terbuka ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
            label: const Text('Opsi lanjutan'),
          ),
        ),
        // Saat terlipat kolomnya benar-benar tidak dirender (bukan sekadar
        // disembunyikan), agar tidak ikut terjaring fokus & pembaca layar.
        AnimatedSize(
          alignment: Alignment.topCenter,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: terbuka
              ? Padding(padding: const EdgeInsets.only(top: 4), child: child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Pemisah extends StatelessWidget {
  const _Pemisah({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

/// Keterangan server — transparansi ke mana aplikasi terhubung.
class _ServerFooter extends StatelessWidget {
  const _ServerFooter({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: cs.onSurface.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Terhubung aman ke $host',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}
