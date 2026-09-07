import 'package:flutter/material.dart';

/// Ambang tablet: mulai lebar ini kerangka memakai rail samping dan layar
/// menampilkan tata letak ala desktop (dua panel, konten dibatasi lebarnya).
const lebarTablet = 720.0;

bool layarLebar(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= lebarTablet;

/// Batasi lebar konten daftar di layar lebar agar baris tidak terentang
/// selebar tablet; di ponsel tidak berpengaruh.
class LebarKonten extends StatelessWidget {
  const LebarKonten({super.key, required this.child, this.maksimal = 820});

  final Widget child;
  final double maksimal;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maksimal),
        child: child,
      ),
    );
  }
}

/// Dialog berlebar tetap untuk lembar yang di ponsel tampil sebagai bottom
/// sheet (hasil transaksi, keranjang) — di tablet lembar selebar layar
/// terasa janggal.
Future<T?> tampilkanLembar<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double lebarDialog = 480,
  bool useRootNavigator = true,
}) {
  if (layarLebar(context)) {
    return showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: lebarDialog, maxHeight: 760),
          child: builder(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: builder,
  );
}
