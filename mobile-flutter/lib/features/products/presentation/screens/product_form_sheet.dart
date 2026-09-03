import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/product.dart';
import '../providers/products_provider.dart';

/// Form tambah/edit produk (bottom sheet). [product] null = tambah.
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

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nama = TextEditingController(text: p?.nama ?? '');
    _hargaJual = TextEditingController(text: p != null ? p.harga.toInt().toString() : '');
    _hargaBeli = TextEditingController(text: p?.hargaBeli != null ? p!.hargaBeli!.toInt().toString() : '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _tipe = (p?.tipe == 'JASA') ? 'JASA' : 'PRODUK';
  }

  @override
  void dispose() {
    _nama.dispose();
    _hargaJual.dispose();
    _hargaBeli.dispose();
    _barcode.dispose();
    super.dispose();
  }

  double? _num(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim());

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final repo = ref.read(productRepositoryProvider);
    final hargaJual = _num(_hargaJual.text) ?? 0;
    final hargaBeli = _num(_hargaBeli.text);
    final barcode = _barcode.text.trim();

    final result = _isEdit
        ? await repo.update(
            id: widget.product!.id,
            nama: _nama.text.trim(),
            hargaJual: hargaJual,
            hargaBeli: hargaBeli,
            barcode: barcode, // '' → kosongkan
          )
        : await repo.create(
            nama: _nama.text.trim(),
            tipe: _tipe,
            hargaJual: hargaJual,
            hargaBeli: hargaBeli,
            barcode: barcode.isEmpty ? null : barcode,
          );

    if (!mounted) return;
    result.when(
      ok: (_) {
        ref.invalidate(productsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              backgroundColor: AppColors.success,
              content: Text(_isEdit ? 'Produk diperbarui.' : 'Produk ditambahkan.')));
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
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              decoration: const InputDecoration(
                  labelText: 'Barcode (opsional)',
                  prefixIcon: Icon(Icons.qr_code_2_outlined)),
            ),
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
    );
  }
}
