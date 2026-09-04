import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Latar bermerek Tuléh — semburat mint di puncak, dua cahaya lembut, dan
/// ombak tipis di kaki layar (identitas yang sama dengan aplikasi desktop).
///
/// Dipakai sebagai alas layar utama supaya kartu dan tombol punya kedalaman,
/// bukan mengambang di atas bidang datar. Semua warna diambil dari tema
/// sehingga mode gelap ikut menyesuaikan.
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.ombak = true,
    this.intensitas = 1,
  });

  final Widget child;

  /// Ombak di kaki layar. Dimatikan pada layar yang penuh daftar panjang.
  final bool ombak;

  /// Pengali kekuatan semburat (0–1.4). Layar padat memakai nilai kecil.
  final double intensitas;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dasar = Theme.of(context).scaffoldBackgroundColor;
    final k = intensitas.clamp(0.0, 1.4);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  Color.lerp(dasar, AppColors.mint900, 0.85 * k)!,
                  dasar,
                  dasar,
                ]
              : [
                  Color.lerp(dasar, AppColors.mint200, 0.55 * k)!,
                  dasar,
                  dasar,
                ],
          stops: const [0, 0.34, 1],
        ),
      ),
      child: Stack(
        children: [
          // Cahaya lembut — memberi kedalaman tanpa mengganggu keterbacaan.
          _Cahaya(
            top: -120,
            right: -90,
            size: 300,
            color: AppColors.mint400,
            opacity: (isDark ? 0.16 : 0.28) * k,
          ),
          _Cahaya(
            top: 140,
            left: -110,
            size: 260,
            color: isDark ? AppColors.mint600 : AppColors.mint300,
            opacity: (isDark ? 0.12 : 0.22) * k,
          ),
          if (ombak)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size(double.infinity, 190),
                  painter: _OmbakPainter(
                    warna: isDark ? AppColors.mint700 : AppColors.mint300,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _Cahaya extends StatelessWidget {
  const _Cahaya({
    this.top,
    this.left,
    this.right,
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double? top, left, right;
  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    return Positioned(
      top: top,
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
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiga lapis ombak dengan opasitas menurun — dekorasi kaki layar.
class _OmbakPainter extends CustomPainter {
  const _OmbakPainter({required this.warna, required this.isDark});

  final Color warna;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final lapis = [
      (dy: 0.55, alpha: isDark ? 0.10 : 0.16, geser: 0.0),
      (dy: 0.72, alpha: isDark ? 0.14 : 0.22, geser: 0.35),
      (dy: 0.88, alpha: isDark ? 0.18 : 0.30, geser: 0.7),
    ];

    for (final l in lapis) {
      final path = Path();
      final dasar = size.height * l.dy;
      final amplitudo = size.height * 0.12;
      path.moveTo(0, dasar);
      path.cubicTo(
        size.width * (0.22 + l.geser * 0.05),
        dasar - amplitudo,
        size.width * (0.55 + l.geser * 0.05),
        dasar + amplitudo,
        size.width,
        dasar - amplitudo * 0.35,
      );
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      canvas.drawPath(
        path,
        Paint()..color = warna.withValues(alpha: l.alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_OmbakPainter old) =>
      old.warna != warna || old.isDark != isDark;
}
