import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../products/domain/entities/pilihan_produk.dart';
import '../../../products/presentation/providers/products_provider.dart';
import '../../domain/entities/profil_usaha.dart';
import '../providers/pengaturan_providers.dart';

/// Layar Profil Usaha — edit nama/alamat/telepon/email + footer & logo struk.
class ProfilUsahaScreen extends ConsumerWidget {
  const ProfilUsahaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profil = ref.watch(profilUsahaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profil Usaha')),
      body: profil.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(e is ApiException ? e.message : 'Gagal memuat profil.',
                textAlign: TextAlign.center),
          ),
        ),
        data: (p) => _Form(profil: p),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.profil});
  final ProfilUsaha profil;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _alamat;
  late final TextEditingController _telepon;
  late final TextEditingController _email;
  late final TextEditingController _footer;
  late bool _tampilLogo;
  bool _loading = false;

  /// Master `/satuan`; null = masih dimuat / gagal dimuat (picker nonaktif).
  List<SatuanPilihan>? _satuanList;
  bool _satuanGagal = false;

  /// Id satuan terpilih ('' = belum diatur). null = belum dicocokkan.
  String? _satuanBawaanId;
  String? _galatSatuan;

  @override
  void initState() {
    super.initState();
    final p = widget.profil;
    _nama = TextEditingController(text: p.nama);
    _alamat = TextEditingController(text: p.alamat ?? '');
    _telepon = TextEditingController(text: p.telepon ?? '');
    _email = TextEditingController(text: p.email ?? '');
    _footer = TextEditingController(text: p.strukFooter ?? '');
    _tampilLogo = p.strukTampilLogo;
    _muatSatuan();
  }

  Future<void> _muatSatuan() async {
    final r = await ref.read(productRepositoryProvider).satuan();
    if (!mounted) return;
    final daftar = r.valueOrNull;
    setState(() {
      _satuanList = daftar;
      _satuanGagal = daftar == null;
      _satuanBawaanId = _cocokkan(daftar ?? const [], widget.profil.satuanBawaan);
    });
  }

  /// Id terenkripsi server tidak deterministik → cocokkan lewat kode, lalu nama.
  static String _cocokkan(List<SatuanPilihan> daftar, SatuanPilihan? bawaan) {
    if (bawaan == null) return '';
    for (final s in daftar) {
      if (bawaan.kode != null && s.kode == bawaan.kode) return s.id;
    }
    for (final s in daftar) {
      if (s.nama == bawaan.nama) return s.id;
    }
    return '';
  }

  /// true bila pilihan berbeda dari nilai server (hanya itu yang dikirim).
  bool get _satuanBerubah {
    final pilih = _satuanBawaanId;
    if (pilih == null || _satuanList == null) return false;
    return pilih != _cocokkan(_satuanList!, widget.profil.satuanBawaan);
  }

  @override
  void dispose() {
    _nama.dispose();
    _alamat.dispose();
    _telepon.dispose();
    _email.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _galatSatuan = null;
    });
    final r = await ref.read(pengaturanRepositoryProvider).simpanProfil(
          nama: _nama.text.trim(),
          alamat: _alamat.text,
          telepon: _telepon.text,
          email: _email.text,
          strukFooter: _footer.text,
          strukTampilLogo: _tampilLogo,
          ubahSatuanBawaan: _satuanBerubah,
          satuanBawaanId: _satuanBawaanId,
        );
    if (!mounted) return;
    r.when(
      ok: (_) {
        ref.invalidate(profilUsahaProvider);
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              backgroundColor: AppColors.success,
              content: Text('Profil usaha tersimpan.')));
      },
      err: (e) {
        final galatSatuan = e.errors?['satuan_bawaan_id'];
        setState(() {
          _loading = false;
          if (galatSatuan != null && galatSatuan.isNotEmpty) _galatSatuan = galatSatuan.first;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: AppColors.danger,
              content: Text(e.firstError() ?? e.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _nama,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Nama usaha', prefixIcon: Icon(Icons.storefront_outlined)),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Nama usaha wajib diisi.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _alamat,
            textInputAction: TextInputAction.next,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Alamat', prefixIcon: Icon(Icons.location_on_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telepon,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Telepon', prefixIcon: Icon(Icons.phone_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
          ),
          const SizedBox(height: 24),
          Text('Produk',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _kolomSatuanBawaan(),
          const SizedBox(height: 24),
          Text('Struk',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _footer,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Catatan kaki struk',
                hintText: 'Terima kasih atas kunjungan Anda',
                prefixIcon: Icon(Icons.notes_outlined)),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tampilkan logo di struk'),
            value: _tampilLogo,
            onChanged: (v) => setState(() => _tampilLogo = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('profil-simpan'),
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AppColors.mint900))
                : const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  /// Satuan bawaan produk baru — daftar dari master `/satuan` server; tidak
  /// ada nama satuan yang dikarang aplikasi.
  Widget _kolomSatuanBawaan() {
    final daftar = _satuanList;
    final petunjuk = _satuanGagal
        ? 'Daftar satuan tidak dapat dimuat'
        : (daftar == null ? 'Memuat…' : 'Belum diatur');
    return DropdownButtonFormField<String>(
      key: ValueKey('satuan-bawaan-${daftar?.length}'),
      initialValue: daftar == null ? null : _satuanBawaanId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Satuan bawaan',
        helperText: 'Dipakai produk baru yang disimpan tanpa memilih satuan.',
        helperMaxLines: 2,
        errorText: _galatSatuan,
        prefixIcon: const Icon(Icons.straighten_outlined),
      ),
      hint: Text(petunjuk),
      disabledHint: Text(petunjuk),
      items: [
        if (daftar != null) const DropdownMenuItem(value: '', child: Text('Belum diatur')),
        for (final s in daftar ?? const <SatuanPilihan>[])
          DropdownMenuItem(value: s.id, child: Text(s.nama)),
      ],
      onChanged: daftar == null || _loading
          ? null
          : (v) => setState(() {
                _satuanBawaanId = v ?? '';
                _galatSatuan = null;
              }),
    );
  }
}
