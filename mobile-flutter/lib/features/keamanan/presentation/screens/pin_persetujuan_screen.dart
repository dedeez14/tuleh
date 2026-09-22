import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/lebar.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../domain/entities/otorisasi.dart';
import '../../domain/galat_pin.dart';
import '../providers/keamanan_providers.dart';

/// "PIN persetujuan saya" (Tahap B §2c) — pemegang hak batal/refund memasang
/// PIN yang dipakai menyetujui pembatalan & refund dari perangkat kasir lain.
///
/// PIN hanya lewat: diketik, dikirim, lalu isian dikosongkan. Tidak pernah
/// disimpan di perangkat dan tidak pernah dikembalikan server.
class PinPersetujuanScreen extends ConsumerStatefulWidget {
  const PinPersetujuanScreen({super.key});

  @override
  ConsumerState<PinPersetujuanScreen> createState() => _PinPersetujuanScreenState();
}

class _PinPersetujuanScreenState extends ConsumerState<PinPersetujuanScreen> {
  final _pinBaru = TextEditingController();
  final _pinLama = TextEditingController();

  String? _galat;
  bool _sibuk = false;

  /// Sisa kuncian PIN di server (detik); 0 = tidak terkunci.
  int _sisaKunci = 0;
  Timer? _hitungMundur;

  @override
  void dispose() {
    _hitungMundur?.cancel();
    _pinBaru.dispose();
    _pinLama.dispose();
    super.dispose();
  }

  bool get _bisaAksi => !_sibuk && _sisaKunci == 0;

  /// Hitung mundur kuncian: angkanya dari server (`data.terkunci_detik`), yang
  /// berjalan di sini hanya penampilannya. Timer WAJIB mati saat layar lepas.
  void _mulaiKunci(int detik) {
    _hitungMundur?.cancel();
    setState(() {
      _sisaKunci = detik;
      _galat = kalimatTerkunci(detik);
    });
    _hitungMundur = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _sisaKunci -= 1;
        if (_sisaKunci <= 0) {
          _sisaKunci = 0;
          _galat = null;
          t.cancel();
          _hitungMundur = null;
        } else {
          _galat = kalimatTerkunci(_sisaKunci);
        }
      });
    });
  }

  /// Kalimat server apa adanya. `firstError()` sudah menyaring kode mesin
  /// (`PIN_TERKUNCI`) — kode itu untuk program, bukan untuk dibaca pengguna.
  void _tampilkanGalat(ApiException e) {
    final detik = detikTerkunci(e);
    if (detik > 0) {
      _mulaiKunci(detik);
      return;
    }
    setState(() => _galat = pesanTerkunci(e) ?? e.firstError() ?? e.message);
  }

  void _beritahu(String pesan) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(pesan)));
  }

  /// Layar bisa ditutup selagi permintaan melayang. Sesudah `await`, jawaban
  /// yang datang belakangan TIDAK boleh mengaku sukses ke layar yang sudah
  /// tidak ada (temuan review dialog persetujuan desktop, 5c75ff9).
  Future<void> _kirim(Future<void> Function() aksi, String sukses) async {
    setState(() {
      _galat = null;
      _sibuk = true;
    });
    try {
      await aksi();
      if (!mounted) return;
      _pinBaru.clear();
      _pinLama.clear();
      ref.invalidate(statusPinProvider);
      _beritahu(sukses);
    } on ApiException catch (e) {
      if (!mounted) return;
      _tampilkanGalat(e);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _simpan({required bool ada}) {
    final pin = _pinBaru.text.trim();
    final lama = _pinLama.text.trim();
    final ds = ref.read(keamananDataSourceProvider);
    return _kirim(
      () => ds.simpanPin(pin: pin, pinLama: ada ? lama : null),
      'PIN persetujuan tersimpan.',
    );
  }

  /// PIN lama WAJIB untuk menghapus (server 1f627b45): tanpa gerbang itu,
  /// "hapus lalu pasang baru" adalah jalan pintas mengganti PIN orang lain
  /// dari sesi yang ditinggal terbuka. Isian kosong dijawab di sini supaya
  /// konfirmasi tidak dibuka untuk sesuatu yang pasti ditolak.
  Future<void> _hapus() async {
    final lama = _pinLama.text.trim();
    if (lama.isEmpty) {
      setState(() => _galat = 'Isi PIN lama untuk menghapus PIN.');
      return;
    }
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus PIN persetujuan?'),
        content: const Text(
          'Nama Anda hilang dari daftar pemberi persetujuan — kasir tidak bisa '
          'meminta persetujuan Anda sampai PIN dipasang lagi.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            key: const Key('pin-hapus-ya'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    final ds = ref.read(keamananDataSourceProvider);
    await _kirim(
      () => ds.hapusPin(pinLama: lama),
      'PIN persetujuan dihapus — Anda tidak lagi muncul sebagai pemberi persetujuan.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(statusPinProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('PIN persetujuan saya')),
      body: LebarKonten(
        child: status.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _gagalMuat(e),
          data: (s) => s.bolehSetel ? _formulir(s) : _tanpaHak(),
        ),
      ),
    );
  }

  Widget _gagalMuat(Object e) {
    final pesan = e is ApiException
        ? (e.firstError() ?? e.message)
        : 'Status PIN tidak bisa dimuat. Periksa sambungan lalu coba lagi.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pesan, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(statusPinProvider),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }

  /// `boleh_setel` false = server menilai akun ini tak berhak membatalkan atau
  /// merefund, jadi PIN-nya tak akan pernah dipakai menyetujui apa pun.
  /// Alasannya dijelaskan, formulirnya tidak ditawarkan (gagal-tertutup).
  Widget _tanpaHak() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'PIN persetujuan belum berlaku untuk akun Anda',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'PIN ini hanya dipakai untuk menyetujui pembatalan atau refund '
                'transaksi yang diminta kasir. Akun Anda belum diberi hak '
                'membatalkan atau merefund, jadi PIN-nya tak akan bisa dipakai '
                'menyetujui apa pun. Hak akses diatur pemilik usaha lewat '
                'pengaturan hak akses.',
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _formulir(StatusPin s) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Kasir tanpa hak membatalkan/merefund bisa meminta persetujuan Anda '
          'di perangkatnya — cukup PIN ini, tanpa kata sandi akun. Nama Anda '
          'tercatat pada transaksi yang disetujui.',
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 18),
        _isian(
          kunci: 'pin-baru',
          controller: _pinBaru,
          label: s.ada ? 'PIN baru' : 'PIN (4–8 digit)',
        ),
        if (s.ada) ...[
          const SizedBox(height: 12),
          _isian(kunci: 'pin-lama', controller: _pinLama, label: 'PIN lama'),
        ],
        if (_galat != null) ...[
          const SizedBox(height: 4),
          Text(_galat!, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          key: const Key('pin-simpan'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _bisaAksi ? () => _simpan(ada: s.ada) : null,
          child: Text(s.ada ? 'Ganti PIN' : 'Pasang PIN'),
        ),
        if (s.ada) ...[
          const SizedBox(height: 4),
          TextButton(
            key: const Key('pin-hapus'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _bisaAksi ? _hapus : null,
            child: const Text('Hapus PIN'),
          ),
        ],
        if (s.diubahPada != null && s.diubahPada!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Terakhir diubah ${fmtTanggal(s.diubahPada)}',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ],
    );
  }

  Widget _isian({
    required String kunci,
    required TextEditingController controller,
    required String label,
  }) => TextField(
    key: Key(kunci),
    controller: controller,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 8,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      counterText: '',
    ),
  );
}
