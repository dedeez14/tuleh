import 'package:flutter/material.dart';

import '../../../../core/utils/rupiah_input.dart';

/// Dialog input "kas awal" untuk buka sesi. Return nominal (double), atau null
/// bila dibatalkan.
///
/// Controller dikelola StatefulWidget & dibuang di [State.dispose] (SETELAH rute
/// benar-benar tertutup). JANGAN `TextEditingController.dispose()` manual tepat
/// setelah showDialog — animasi keluar dialog masih me-rebuild TextField →
/// "A TextEditingController was used after being disposed" (lalu meng-cascade ke
/// assertion _dependents.isEmpty).
Future<double?> showBukaSesiDialog(BuildContext context) {
  return showDialog<double>(
    context: context,
    builder: (_) => const _BukaSesiDialog(),
  );
}

class _BukaSesiDialog extends StatefulWidget {
  const _BukaSesiDialog();

  @override
  State<_BukaSesiDialog> createState() => _BukaSesiDialogState();
}

class _BukaSesiDialogState extends State<_BukaSesiDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buka Sesi Kasir'),
      content: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: const [RupiahInputFormatter()],
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Kas awal (Rp)',
          prefixText: 'Rp ',
          hintText: '0',
          helperText: 'Uang tunai di laci saat mulai, mis. 100.000',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, parseRupiah(_ctrl.text)),
          child: const Text('Buka'),
        ),
      ],
    );
  }
}
