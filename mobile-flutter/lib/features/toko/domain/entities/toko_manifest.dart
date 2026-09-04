/// Manifest toko (`GET /tokos/{id}/manifest`) — "wajah" aplikasi per bidang
/// usaha: menu, kapabilitas, alur transaksi, tahapan pesanan, jenis stasiun.
/// Bentuk server dinormalkan di [TokoManifest.fromJson] (cermin
/// `normalizeManifest` di app.js desktop) sehingga bidang usaha baru yang
/// dikirim server (bengkel, doorsmeer, salon, …) langsung terbaca tanpa rilis.
class ManifestMenu {
  const ManifestMenu({
    required this.id,
    required this.label,
    required this.routeKey,
    this.order = 0,
  });

  final String id;
  final String label;
  final String routeKey;
  final int order;
}

class StationType {
  const StationType({required this.type, required this.label, this.min = 0});

  final String type;
  final String label;
  final int min;
}

class TokoManifest {
  const TokoManifest({
    this.verticalCode,
    this.menus = const [],
    this.capabilities = const [],
    this.transactionFlow = const [],
    this.lifecycleStates = const [],
    this.stationTypes = const [],
    this.paymentModes = const [],
  });

  final String? verticalCode;
  final List<ManifestMenu> menus;
  final List<String> capabilities;
  final List<String> transactionFlow;

  /// Tahap pesanan berurutan; tahap terakhir = terminal (SELESAI).
  final List<String> lifecycleStates;
  final List<StationType> stationTypes;
  final List<String> paymentModes;

  /// Route_key menu yang membuka papan pesanan (KDS / Antrian / Papan Proses).
  static const papanRouteKeys = {'dapur', 'antrian', 'proses'};

  /// Toko memakai alur pesanan bertahap → papan pesanan tersedia.
  bool get punyaPapanPesanan => lifecycleStates.length >= 2;

  /// Nota boleh disimpan tanpa bayar (pelunasan saat serah/ambil).
  bool get bolehBayarNanti => transactionFlow.contains('PAYMENT_OR_LATER');

  /// Menu papan pesanan dari server (label mengikuti bidang usaha), bila ada.
  ManifestMenu? get menuPapan {
    for (final m in menus) {
      if (papanRouteKeys.contains(m.routeKey)) return m;
    }
    return null;
  }

  /// Bentuk server (`menus` objek/string, `lifecycle.states`, …) → entitas.
  factory TokoManifest.fromJson(Map<String, dynamic> raw) {
    final menus = <ManifestMenu>[];
    final rawMenus = raw['menus'];
    if (rawMenus is List) {
      for (final e in rawMenus) {
        if (e is String) {
          menus.add(ManifestMenu(id: e, label: e, routeKey: e));
        } else if (e is Map && e['id'] is String) {
          final id = e['id'] as String;
          menus.add(
            ManifestMenu(
              id: id,
              label: (e['label'] ?? id).toString(),
              routeKey: (e['route_key'] ?? id).toString(),
              order: int.tryParse('${e['order'] ?? 0}') ?? 0,
            ),
          );
        }
      }
    }

    final lifecycle = raw['lifecycle'];
    final states = lifecycle is Map ? _strings(lifecycle['states']) : <String>[];

    final stations = <StationType>[];
    final rawStations = raw['station_types'];
    if (rawStations is List) {
      for (final e in rawStations) {
        if (e is Map && e['type'] != null) {
          stations.add(
            StationType(
              type: e['type'].toString(),
              label: (e['label'] ?? e['type']).toString(),
              min: int.tryParse('${e['min'] ?? 0}') ?? 0,
            ),
          );
        }
      }
    }

    return TokoManifest(
      verticalCode: raw['vertical_code']?.toString(),
      menus: menus,
      capabilities: _strings(raw['capabilities']),
      transactionFlow: _strings(raw['transaction_flow']),
      lifecycleStates: states,
      stationTypes: stations,
      paymentModes: _strings(raw['payment_modes']),
    );
  }

  static List<String> _strings(dynamic v) =>
      v is List ? [for (final e in v) if (e != null) e.toString()] : const [];
}
