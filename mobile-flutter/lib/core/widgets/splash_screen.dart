import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Splash saat auto-login berjalan — brand Tuléh berkedalaman (gradient + glow).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _glowOpacity;
  late final Animation<double> _heroOpacity;
  late final Animation<Offset> _heroSlide;
  late final Animation<double> _heroScale;
  late final Animation<double> _footerOpacity;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _glowOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, 0.48, curve: Curves.easeOut),
    );
    _heroOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
    );
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0, 0.74, curve: Curves.easeOutCubic),
          ),
        );
    _heroScale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.08, 0.7, curve: Curves.easeOutBack),
      ),
    );
    _footerOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.45, 1, curve: Curves.easeOut),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _prefersReducedMotion(context);

    final heroIcon = Container(
      height: 92,
      width: 92,
      decoration: BoxDecoration(
        color: AppColors.mint400,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.mint400.withValues(alpha: 0.4),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.point_of_sale_rounded,
        color: AppColors.mint900,
        size: 48,
      ),
    );

    final heroBody = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        reduceMotion
            ? heroIcon
            : ScaleTransition(scale: _heroScale, child: heroIcon),
        const SizedBox(height: 26),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: Colors.white,
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
          'Kasir modern untuk usaha Anda',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 14,
          ),
        ),
      ],
    );

    final hero = reduceMotion
        ? heroBody
        : FadeTransition(
            opacity: _heroOpacity,
            child: SlideTransition(position: _heroSlide, child: heroBody),
          );

    final footer = Column(
      children: [
        const SizedBox(
          height: 26,
          width: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: AppColors.mint400,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Memuat…',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
      ],
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.mint900, AppColors.mint800],
          ),
        ),
        child: Stack(
          children: [
            reduceMotion
                ? const _Glow(
                    top: -90,
                    right: -70,
                    size: 260,
                    color: AppColors.mint500,
                  )
                : FadeTransition(
                    opacity: _glowOpacity,
                    child: const _Glow(
                      top: -90,
                      right: -70,
                      size: 260,
                      color: AppColors.mint500,
                    ),
                  ),
            reduceMotion
                ? const _Glow(
                    bottom: -80,
                    left: -60,
                    size: 240,
                    color: AppColors.mint700,
                  )
                : FadeTransition(
                    opacity: _glowOpacity,
                    child: const _Glow(
                      bottom: -80,
                      left: -60,
                      size: 240,
                      color: AppColors.mint700,
                    ),
                  ),
            Center(child: hero),
            Positioned(
              left: 0,
              right: 0,
              bottom: 54,
              child: reduceMotion
                  ? footer
                  : FadeTransition(opacity: _footerOpacity, child: footer),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.color,
  });
  final double? top, bottom, left, right;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          height: size,
          width: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.35),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
