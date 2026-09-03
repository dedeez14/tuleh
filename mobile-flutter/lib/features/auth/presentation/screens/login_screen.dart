import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../controllers/auth_controller.dart';

/// Layar masuk — hero mint berkedalaman + kartu form mengambang (overlap).
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
  late final Animation<double> _heroAnimation;
  late final Animation<double> _formAnimation;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _heroAnimation = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
    );
    _formAnimation = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.18, 1, curve: Curves.easeOutCubic),
    );
  }

  bool _prefersReducedMotion(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;
    return media.disableAnimations || media.accessibleNavigation;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefersReducedMotion(context)) {
      _entryController.value = 1;
      return;
    }
    if (_entryController.status == AnimationStatus.dismissed) {
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

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (prev, next) {
      if (next is AsyncError) {
        final e = next.error;
        final msg = e is ApiException
            ? (e.firstError() ?? e.message)
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
    final reduceMotion = _prefersReducedMotion(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.mint100, AppColors.bgLight],
            stops: [0, 0.36],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              final maxWidth = isWide ? 980.0 : 560.0;

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomInset),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 11,
                                child: _withEntryTransition(
                                  child: const _Hero(),
                                  animation: _heroAnimation,
                                  reduceMotion: reduceMotion,
                                  begin: const Offset(-0.04, 0.02),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 10,
                                child: _withEntryTransition(
                                  child: _formCard(loading, compact: false),
                                  animation: _formAnimation,
                                  reduceMotion: reduceMotion,
                                  begin: const Offset(0.04, 0.02),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _withEntryTransition(
                                child: const _Hero(),
                                animation: _heroAnimation,
                                reduceMotion: reduceMotion,
                              ),
                              const SizedBox(height: 14),
                              _withEntryTransition(
                                child: _formCard(loading, compact: true),
                                animation: _formAnimation,
                                reduceMotion: reduceMotion,
                                begin: const Offset(0, 0.06),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _withEntryTransition({
    required Widget child,
    required Animation<double> animation,
    required bool reduceMotion,
    Offset begin = const Offset(0, 0.04),
  }) {
    if (reduceMotion) return child;
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

  Widget _formCard(bool loading, {required bool compact}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: compact ? 8 : 5,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, compact ? 22 : 24, 20, 22),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Selamat datang',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Masuk untuk mulai berjualan.',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.62)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.75),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shield_moon_outlined,
                        size: 18,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Akun terhubung aman ke server toko Anda.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _login,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Email / Username',
                    hintText: 'kasir@toko.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Email/username wajib diisi.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Kata sandi',
                    hintText: '********',
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
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Kata sandi wajib diisi.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _device,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => loading ? null : _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Nama perangkat (opsional)',
                    hintText: 'Kasir-01',
                    prefixIcon: Icon(Icons.smartphone_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: loading ? null : _submit,
                  icon: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.mint900,
                          ),
                        )
                      : const Icon(Icons.login_rounded, size: 20),
                  label: Text(loading ? 'Memproses...' : 'Masuk'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.mint900, AppColors.mint700],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.mint900.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -42,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -54,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: AppColors.mint400,
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.mint400.withValues(alpha: 0.35),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: AppColors.mint900,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                  children: [
                    TextSpan(text: 'Tul'),
                    TextSpan(
                      text: 'éh',
                      style: TextStyle(color: AppColors.mint400),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Kasir cepat, laporan rapi, semua dalam genggaman.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
              const SizedBox(height: 16),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroPill(
                    icon: Icons.sync_rounded,
                    label: 'Sinkron realtime',
                  ),
                  _HeroPill(
                    icon: Icons.lock_outline_rounded,
                    label: 'Akses aman',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
