import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../../../core/widgets/pindai_barcode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/rupiah_input.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../toko/domain/entities/toko.dart';
import '../../../toko/presentation/providers/toko_providers.dart';
import '../../domain/entities/pilihan_produk.dart';
import '../../domain/entities/product.dart';
import '../providers/products_provider.dart';

/// Form tambah/edit produk (bottom sheet). [product] null = tambah.
///
/// Selain nama/harga/barcode, formulir memuat pilihan dari master server
/// (2026-09-14, cermin `bukaForm` di products.js desktop): satuan, cara input
/// jumlah di kasir (per satuan / per ukuran / per ukuran atau rupiah), dan toko
/// yang menjual produk (hanya bila pengguna punya ≥ 2 toko). Server lama tanpa
/// `/mode-jual` atau `/produk-toko` → kolomnya tetap tersembunyi.
class ProductFormSheet extends ConsumerStatefulWidget {
  const ProductFormSheet({super.key, this.product});
  final Product? product;

  @override
  ConsumerState<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _hargaJual;
  late final TextEditingController _hargaBeli;
  late final TextEditingController _barcode;
  String _tipe = 'PRODUK';
  bool _loading = false;

  /// Master satuan; null = masih dimuat, kosong = gagal/tidak ada.
  List<SatuanPilihan>? _satuanList;
  String? _satuanId;

  /// Galat server untuk kolom satuan (`errors.satuan_id`, mis. satuan bawaan
  /// usaha belum diatur) — ditampilkan di bawah kolomnya, bukan hanya snackbar.
  String? _galatSatuan;

  /// Nama satuan produk saat formulir dibuka (dicocokkan ke master lewat nama).
  String _satuanAwal = '';

  /// Master mode jual; null = server lama / gagal → pilihan disembunyikan.
  List<ModeJualPilihan>? _modeList;

  /// '' = otomatis ikut satuan.
  String _modeKode = '';
  String _modeAwal = '';

  /// Toko yang bisa dipilih; null = bagian toko tidak ditampilkan.
  List<TokoProduk>? _tokoList;
  final Set<String> _tokoDipilih = {};
  Set<String> _tokoAwal = const {};

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nama = TextEditingController(text: p?.nama ?? '');
    _hargaJual = TextEditingController(text: p != null ? teksRupiah(p.harga) : '');
    _hargaBeli = TextEditingController(text: p?.hargaBeli != null ? teksRupiah(p!.hargaBeli!) : '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _tipe = (p?.tipe == 'JASA') ? 'JASA' : 'PRODUK';
    final satuan = p?.satuan?.trim() ?? '';
    _satuanAwal = satuan == '-' ? '' : satuan;
    // Mode otomatis (asal SATUAN) tidak dipilih ulang, agar tetap mengikuti satuan.
    _modeAwal = p != null && p.modeJualAsal == 'PRODUK' ? (p.modeJual ?? '') : '';
    _modeKode = _modeAwal;
    _muatSatuanDanMode();
    _muatToko();
  }

  @override
  void dispose() {
    _nama.dispose();
    _hargaJual.dispose();
    _hargaBeli.dispose();
    _barcode.dispose();
    super.dispose();
  }

  Future<void> _muatSatuanDanMode() async {
    final repo = ref.read(productRepositoryProvider);
    final satuanF = repo.satuan();
    final modeF = repo.modeJual();
    final satuan = (await satuanF).valueOrNull ?? const <SatuanPilihan>[];
    final mode = (await modeF).valueOrNull;
    if (!mounted) return;
    setState(() {
      _satuanList = satuan;
      for (final s in satuan) {
        if (s.nama == _satuanAwal) _satuanId = s.id;
      }
      _modeList = mode == null || mode.isEmpty ? null : mode;
      if (!(_modeList?.any((m) => m.kode == _modeAwal) ?? false)) {
        _modeAwal = '';
        _modeKode = '';
      }
    });
  }

  Future<void> _muatToko() async {
    List<Toko> tokos;
    try {
      tokos = await ref.read(tokoListProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted || tokos.length < 2) return;
    if (!_isEdit) {
      setState(() => _tokoList = [for (final t in tokos) TokoProduk(id: t.id, nama: t.nama)]);
      return;
    }
    // Id toko terenkripsi tidak deterministik: tanda "dijual" wajib dari server.
    final r = await ref.read(productRepositoryProvider).tokoProduk(widget.product!.id);
    final d = r.valueOrNull;
    if (!mounted || d == null || d.tokos.length < 2) return;
    setState(() {
      _tokoList = d.tokos;
      _tokoAwal = {for (final t in d.tokos) if (t.dijual) t.id};
      _tokoDipilih
        ..clear()
        ..addAll(_tokoAwal);
    });
  }

  double? _num(String s) => s.trim().isEmpty ? null : parseRupiah(s);

  String? _namaSatuan(String? id) {
    for (final s in _satuanList ?? const <SatuanPilihan>[]) {
      if (s.id == id) return s.nama;
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _galatSatuan = null;
    });
    final repo = ref.read(productRepositoryProvider);
    final hargaJual = _num(_hargaJual.text) ?? 0;
    final hargaBeli = _num(_hargaBeli.text);
    final barcode = _barcode.text.trim();
    final satuanBerubah = _satuanId != null && _namaSatuan(_satuanId) != _satuanAwal;
    final modeTampil = _modeList != null;
    final tokoTampil = _tokoList != null;

    var result = _isEdit
        ? await repo.update(
            id: widget.product!.id,
            nama: _nama.text.trim(),
            hargaJual: hargaJual,
            hargaBeli: hargaBeli,
            barcode: barcode, // '' → kosongkan
            satuanId: satuanBerubah ? _satuanId : null,
            // '' = kembali otomatis ikut satuan.
            modeJual: modeTampil && _modeKode != _modeAwal ? _modeKode : null,
          )
        : await repo.create(
            nama: _nama.text.trim(),
            tipe: _tipe,
            hargaJual: hargaJual,
            hargaBeli: hargaBeli,
            barcode: barcode.isEmpty ? null : barcode,
            satuanId: _satuanId,
            modeJual: modeTampil && _modeKode.isNotEmpty ? _modeKode : null,
            tokoIds: tokoTampil && _tokoDipilih.isNotEmpty ? _tokoDipilih.toList() : null,
          );
    if (_isEdit && result.isOk && tokoTampil && !setEquals(_tokoDipilih, _tokoAwal)) {
      result = await repo.aturToko(widget.product!.id, _tokoDipilih.toList());
    }

    if (!mounted) return;
    result.when(
      ok: (_) {
        ref.invalidate(productsProvider);
        ref.invalidate(produkKelolaProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: AppColors.success,
              content: Text(_isEdit ? 'Produk diperbarui.' : 'Produk ditambahkan.')));
      },
      err: (e) {
        final galatSatuan = e.errors?['satuan_id'];
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
    final cs = Theme.of(context).colorScheme;
    final redup = TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.65));
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        // Kolom satuan, cara input, dan toko membuat formulir lebih tinggi dari
        // layar ponsel kecil (apalagi saat papan ketik terbuka).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Edit Produk' : 'Tambah Produk',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nama,
                autofocus: !_isEdit,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Nama produk', prefixIcon: Icon(Icons.label_outline)),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nama wajib diisi.' : null,
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'PRODUK', label: Text('Produk'), icon: Icon(Icons.inventory_2_outlined)),
                    ButtonSegment(value: 'JASA', label: Text('Jasa'), icon: Icon(Icons.handyman_outlined)),
                  ],
                  selected: {_tipe},
                  onSelectionChanged: (s) => setState(() => _tipe = s.first),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _hargaJual,
                keyboardType: TextInputType.number,
                inputFormatters: const [RupiahInputFormatter()],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Harga jual (Rp)', prefixIcon: Icon(Icons.sell_outlined)),
                validator: (v) {
                  final n = _num(v ?? '');
                  if (n == null || n <= 0) return 'Harga jual wajib diisi.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hargaBeli,
                keyboardType: TextInputType.number,
                inputFormatters: const [RupiahInputFormatter()],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Harga beli (opsional)',
                    prefixIcon: Icon(Icons.shopping_bag_outlined)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _loading ? null : _save(),
                decoration: InputDecoration(
                  labelText: 'Barcode (opsional)',
                  prefixIcon: const Icon(Icons.qr_code_2_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Pindai dengan kamera',
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: () async {
                      final kode = await PindaiBarcodeScreen.sekali(context, judul: 'Pindai barcode produk');
                      if (kode != null && mounted) setState(() => _barcode.text = kode);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _kolomSatuan(),
              if (_modeList != null) ...[
                const SizedBox(height: 12),
                _kolomModeJual(),
                const SizedBox(height: 4),
                Text(_keteranganMode(), style: redup),
              ],
              if (_tokoList != null) ...[
                const SizedBox(height: 14),
                const Text('Dijual di toko', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final t in _tokoList!)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(t.nama),
                    value: _tokoDipilih.contains(t.id),
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _tokoDipilih.add(t.id);
                      } else {
                        _tokoDipilih.remove(t.id);
                      }
                    }),
                  ),
                Text('Tidak ada yang dicentang = dijual di semua toko.', style: redup),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.mint900))
                    : Text(_isEdit ? 'Simpan Perubahan' : 'Tambah Produk'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Satuan jual — dari master; nilai awal dicocokkan lewat nama satuan produk.
  Widget _kolomSatuan() {
    final daftar = _satuanList;
    final petunjuk = daftar == null
        ? (_satuanAwal.isEmpty ? 'Memuat…' : _satuanAwal)
        : (_satuanAwal.isEmpty ? 'Bawaan' : _satuanAwal);
    return DropdownButtonFormField<String>(
      // Dibangun ulang setelah master termuat agar nilai awal terpasang.
      key: ValueKey('satuan-${daftar?.length}'),
      initialValue: _satuanId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Satuan',
        prefixIcon: const Icon(Icons.straighten_outlined),
        errorText: _galatSatuan,
        errorMaxLines: 3,
      ),
      hint: Text(petunjuk),
      disabledHint: Text(petunjuk),
      items: [
        for (final s in daftar ?? const <SatuanPilihan>[])
          DropdownMenuItem(value: s.id, child: Text(s.nama)),
      ],
      onChanged: daftar == null || daftar.isEmpty
          ? null
          : (v) => setState(() {
                _satuanId = v;
                _galatSatuan = null;
              }),
    );
  }

  /// Cara input jumlah di kasir — "Otomatis" + master `/mode-jual`.
  Widget _kolomModeJual() => DropdownButtonFormField<String>(
    key: const ValueKey('mode-jual'),
    initialValue: _modeKode,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Cara input di kasir',
      prefixIcon: Icon(Icons.scale_outlined),
    ),
    items: [
      const DropdownMenuItem(value: '', child: Text('Otomatis (ikut satuan)')),
      for (final m in _modeList!) DropdownMenuItem(value: m.kode, child: Text(m.nama)),
    ],
    onChanged: (v) => setState(() => _modeKode = v ?? ''),
  );

  String _keteranganMode() {
    for (final m in _modeList ?? const <ModeJualPilihan>[]) {
      if (m.kode == _modeKode) return m.keterangan ?? '';
    }
    return 'Kg, liter, atau meter otomatis bisa diisi per ukuran dan per rupiah; '
        'satuan lain per jumlah bulat.';
  }
}
