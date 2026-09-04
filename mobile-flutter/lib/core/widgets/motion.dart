import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Kumpulan gerak (motion) yang dipakai seluruh aplikasi.
///
/// Prinsipnya: gerak menjelaskan alur, bukan menghias. Durasi pendek, kurva
/// meredam di akhir, dan selalu menghormati "kurangi gerak" pada setelan
/// aksesibilitas perangkat.
class Gerak {
  Gerak._();

  static const cepat = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 260);
  static const masuk = Duration(milliseconds: 420);
  static const kurva = Curves.easeOutCubic;

  /// Pengguna meminta gerak dikurangi (TalkBack / setelan animasi mati).
  static bool dikurangi(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;
    return media.disableAnimations || media.accessibleNavigation;
  }
}

/// Muncul bertahap: tiap anak masuk sedikit lebih lambat dari sebelumnya,
/// sehingga daftar terasa "tersusun", bukan berkedip sekaligus.
class MunculBertahap extends StatefulWidget {
  const MunculBertahap({
    super.key,
    required this.child,
    this.urutan = 0,
    this.jeda = const Duration(milliseconds: 55),
    this.geser = const Offset(0, 0.06),
  });

  final Widget child;

  /// Posisi anak dalam daftar — menentukan besar penundaan.
  final int urutan;
  final Duration jeda;
  final Offset geser;

  @override
  State<MunculBertahap> createState() => _MunculBertahapState();
}

class _MunculBertahapState extends State<MunculBertahap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Gerak.masuk,
  );
  bool _mulai = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mulai) return;
    _mulai = true;
    if (Gerak.dikurangi(context)) {
      _c.value = 1;
      return;
    }
    // Penundaan dibatasi agar item ke-20 tidak menunggu terlalu lama.
    final tunda = widget.jeda * widget.urutan.clamp(0, 8);
    Future<void>.delayed(tunda, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _c, curve: Gerak.kurva);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.geser,
          end: Offset.zero,
        ).animate(anim),
        child: widget.child,
      ),
    );
  }
}

/// Angka yang berubah dengan animasi hitung — dipakai untuk total & omzet
/// agar perubahan nilai terlihat, bukan melompat diam-diam.
class AngkaBerubah extends StatelessWidget {
  const AngkaBerubah({
    super.key,
    required this.nilai,
    required this.format,
    this.style,
    this.durasi = Gerak.normal,
  });

  final double nilai;
  final String Function(double) format;
  final TextStyle? style;
  final Duration durasi;

  @override
  Widget build(BuildContext context) {
    if (Gerak.dikurangi(context)) {
      return Text(format(nilai), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: nilai, end: nilai),
      duration: durasi,
      curve: Gerak.kurva,
      builder: (_, v, _) => Text(format(v), style: style),
    );
  }
}

/// Transisi halaman: memudar sambil naik sedikit — terasa berlapis, bukan
/// bergeser penuh ala iOS yang mengganggu di aplikasi bertab.
CustomTransitionPage<T> halamanBeranimasi<T>({
  required Widget child,
  required LocalKey key,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: Gerak.normal,
    reverseTransitionDuration: Gerak.cepat,
    transitionsBuilder: (context, animation, secondary, child) {
      if (Gerak.dikurangi(context)) return child;
      final kurva = CurvedAnimation(parent: animation, curve: Gerak.kurva);
      return FadeTransition(
        opacity: kurva,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(kurva),
          child: child,
        ),
      );
    },
  );
}
