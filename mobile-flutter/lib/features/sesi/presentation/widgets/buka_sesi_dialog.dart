import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _ctrl = TextEditingController(text: '0');

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
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Kas awal (Rp)', prefixText: 'Rp '),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, double.tryParse(_ctrl.text.trim()) ?? 0),
          child: const Text('Buka'),
        ),
      ],
    );
  }
}
