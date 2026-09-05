import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/splash_screen.dart' show BrandAssets;
import '../../auth/presentation/controllers/auth_controller.dart';
import '../data/masa_coba_service.dart';

/// Verifikasi identitas untuk masa coba (lapis 3): nomor WhatsApp atau email
/// → kode OTP dari server → masa coba terikat ke identitas itu. Setelah kode
/// benar, Mode Demo dibuka otomatis.
class DemoIdentitasScreen extends ConsumerStatefulWidget {
  const DemoIdentitasScreen({super.key});

  @override
  ConsumerState<DemoIdentitasScreen> createState() =>
      _DemoIdentitasScreenState();
}

class _DemoIdentitasScreenState extends ConsumerState<DemoIdentitasScreen> {
  String _jenis = 'wa';
  bool _tahapKode = false;
  bool _sibuk = false;
  String? _galat;
  final _tujuan = TextEditingController();
  final _kode = TextEditingController();

  @override
  void dispose() {
    _tujuan.dispose();
    _kode.dispose();
    super.dispose();
  }

  Future<void> _kirim() async {
    final tujuan = _tujuan.text.trim();
    if (tujuan.isEmpty) {
      setState(
        () => _galat = _jenis == 'wa'
            ? 'Isi nomor WhatsApp.'
            : 'Isi alamat email.',
      );
      return;
    }
    setState(() {
      _sibuk = true;
      _galat = null;
    });
    final galat = await ref
        .read(masaCobaServiceProvider)
        .remote
        .otpKirim(jenis: _jenis, tujuan: tujuan);
    if (!mounted) return;
    setState(() {
      _sibuk = false;
      _galat = galat;
      if (galat == null) _tahapKode = true;
    });
  }

  Future<void> _verifikasi() async {
    final kode = _kode.text.trim();
    if (kode.length < 4) {
      setState(() => _galat = 'Masukkan kode yang dikirim.');
      return;
    }
    setState(() {
      _sibuk = true;
      _galat = null;
    });
    final svc = ref.read(masaCobaServiceProvider);
    final r = await svc.remote.otpVerifikasi(
      jenis: _jenis,
      tujuan: _tujuan.text.trim(),
      kode: kode,
    );
    if (!mounted) return;
    if (r.galat != null || r.token == null) {
      setState(() {
        _sibuk = false;
        _galat = r.galat ?? 'Verifikasi gagal.';
      });
      return;
    }
    await svc.simpanIdentitasToken(r.token);
    if (!mounted) return;
    // Coba buka demo lagi; hasilnya (aktif / berakhir) ditangani layar masuk.
    context.go('/login');
    await ref.read(authControllerProvider.notifier).startDemo();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wa = _jenis == 'wa';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/login')),
        title: const Text('Verifikasi masa coba'),
      ),
      body: AppBackground(
        pola: true,
        ombak: false,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  Center(
                    child: Image.asset(
                      BrandAssets.icon,
                      height: 64,
                      semanticLabel: 'Logo Tuléh',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Masa coba Mode Demo 7 hari terikat ke satu nomor '
                    'WhatsApp atau email, supaya adil untuk semua pengguna. '
                    'Kami memakainya hanya untuk masa coba dan penawaran Tuléh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: cs.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'wa',
                        label: Text('WhatsApp'),
                        icon: Icon(Icons.chat_outlined),
                      ),
                      ButtonSegment(
                        value: 'email',
                        label: Text('Email'),
                        icon: Icon(Icons.mail_outline_rounded),
                      ),
                    ],
                    selected: {_jenis},
                    onSelectionChanged: _tahapKode || _sibuk
                        ? null
                        : (s) => setState(() => _jenis = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tujuan,
                    readOnly: _tahapKode,
                    keyboardType: wa
                        ? TextInputType.phone
                        : TextInputType.emailAddress,
                    autofillHints: [
                      wa ? AutofillHints.telephoneNumber : AutofillHints.email,
                    ],
                    decoration: InputDecoration(
                      labelText: wa ? 'Nomor WhatsApp' : 'Alamat email',
                      hintText: wa ? '08xxxxxxxxxx' : 'nama@contoh.com',
                      prefixIcon: Icon(
                        wa ? Icons.phone_android_rounded : Icons.alternate_email,
                      ),
                    ),
                    onSubmitted: (_) => _tahapKode ? null : _kirim(),
                  ),
                  if (_tahapKode) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _kode,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      autofillHints: const [AutofillHints.oneTimeCode],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Kode verifikasi',
                        hintText: '••••••',
                        helperText: 'Kode dikirim ke tujuan di atas, berlaku 5 menit.',
                      ),
                      onSubmitted: (_) => _verifikasi(),
                    ),
                  ],
                  if (_galat != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _galat!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _sibuk
                        ? null
                        : (_tahapKode ? _verifikasi : _kirim),
                    child: _sibuk
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.mint900,
                            ),
                          )
                        : Text(_tahapKode ? 'Verifikasi' : 'Kirim kode'),
                  ),
                  if (_tahapKode) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _sibuk
                          ? null
                          : () => setState(() {
                              _tahapKode = false;
                              _kode.clear();
                              _galat = null;
                            }),
                      child: const Text('Ganti nomor / kirim ulang'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
