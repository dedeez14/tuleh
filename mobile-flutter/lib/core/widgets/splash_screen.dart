import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Aset merek Tuléh — logo yang sama dengan desktop & aplikasi Android lama.
abstract final class BrandAssets {
  /// Notepad + wordmark "Tuléh" (transparan). Untuk splash & panel login lebar.
  static const String logo = 'assets/brand/logo.png';

  /// Notepad + pensil saja (transparan). Untuk tanda merek kecil.
  static const String icon = 'assets/brand/icon.png';
}

/// Splash saat auto-login berjalan. Meniru splash desktop (index.html
/// `#splash`): latar radial putih→mint muda, logo Tuléh mengambang dengan
/// bayangan, bilah kemajuan mint. Latar putih di tengah menyambung mulus dari
/// splash native Android (flutter_native_splash, warna #FFFFFF), sehingga tak
/// ada kilatan warna saat engine Flutter mulai.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const Color _teks = Color(0xFF2F5B50);
  static const Color _bayangan = Color(0x3812463C);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _masuk;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _kakiOpacity;

  @override
  void initState() {
    super.initState();
    _masuk = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    final lengkung = CurvedAnimation(
      parent: _masuk,
      curve: const Interval(0, 0.8, curve: Curves.easeOutCubic),
    );
    _logoOpacity = lengkung;
    _logoScale = Tween<double>(begin: 0.9, end: 1).animate(lengkung);
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(lengkung);
    _kakiOpacity = CurvedAnimation(
      parent: _masuk,
      curve: const Interval(0.4, 1, curve: Curves.easeOut),
    );
  }

  bool _kurangiGerak(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;
    return media.disableAnimations || media.accessibleNavigation;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kurangiGerak(context)) {
      _masuk.value = 1;
      return;
    }
    if (_masuk.status == AnimationStatus.dismissed) _masuk.forward();
  }

  @override
  void dispose() {
    _masuk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diam = _kurangiGerak(context);
    final lebar = MediaQuery.sizeOf(context).width;
    // Desktop: width 60vw, max 232px.
    final lebarLogo = (lebar * 0.6).clamp(120.0, 232.0);

    final logo = _LogoBerbayang(lebar: lebarLogo);

    final logoBergerak = diam
        ? logo
        : FadeTransition(
            opacity: _logoOpacity,
            child: SlideTransition(
              position: _logoSlide,
              child: ScaleTransition(scale: _logoScale, child: logo),
            ),
          );

    final kaki = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: (lebar * 0.56).clamp(120.0, 220.0),
          child: const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(999)),
            child: LinearProgressIndicator(
              minHeight: 5,
              color: AppColors.mint500,
              backgroundColor: Color(0x24125042),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'MEMUAT…',
          style: TextStyle(
            color: SplashScreen._teks,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.28),
            radius: 1.1,
            colors: [Color(0xFFFFFFFF), Color(0xFFEAFAF4), Color(0xFFD2EFE6)],
            stops: [0, 0.58, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: Center(child: logoBergerak)),
              Padding(
                padding: const EdgeInsets.only(bottom: 44),
                child: diam
                    ? kaki
                    : FadeTransition(opacity: _kakiOpacity, child: kaki),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logo dengan bayangan mengikuti bentuk (padanan CSS `filter: drop-shadow`),
/// bukan bayangan kotak: salinan logo yang diwarnai lalu diburamkan di bawahnya.
class _LogoBerbayang extends StatelessWidget {
  const _LogoBerbayang({required this.lebar});
  final double lebar;

  @override
  Widget build(BuildContext context) {
    final gambar = Image.asset(
      BrandAssets.logo,
      width: lebar,
      fit: BoxFit.contain,
      semanticLabel: 'Tuléh',
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                SplashScreen._bayangan,
                BlendMode.srcIn,
              ),
              child: ExcludeSemantics(child: gambar),
            ),
          ),
        ),
        gambar,
      ],
    );
  }
}
