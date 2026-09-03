import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
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
    setState(() => _loading = true);
    final r = await ref.read(pengaturanRepositoryProvider).simpanProfil(
          nama: _nama.text.trim(),
          alamat: _alamat.text,
          telepon: _telepon.text,
          email: _email.text,
          strukFooter: _footer.text,
          strukTampilLogo: _tampilLogo,
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
        setState(() => _loading = false);
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
}
