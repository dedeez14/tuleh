import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_result.dart';
import '../../../../core/offline/antrean.dart';
import '../../../../core/offline/antrean_tulis.dart';
import '../../../../core/offline/rujukan_lokal.dart';
import '../../domain/entities/bill_detail.dart';
import '../../domain/entities/meja.dart';
import '../../domain/repositories/meja_repository.dart';
import '../datasources/meja_remote_datasource.dart';

/// Bon meja offline (fase 3): buka bon, tambah ronde, dan bayar diantrekan
/// saat server tak terjangkau, lalu peta meja & detail bon menampilkan
/// keadaan seolah sudah terjadi.
///
/// - Bon yang dibuka offline memakai id `lokal:<client_ref>`; ronde & bayar
///   untuk bon itu merujuk id tersebut di path dan diganti id server oleh
///   pengurai setelah baris buka-bon terkirim (FIFO menjamin urutannya).
/// - Bon server yang dibayar offline tampil kosong di peta sampai terkirim.
/// - Nama & harga item ronde disimpan di kunci `_tampilan` (tidak dikirim).
class MejaOfflineRepository implements MejaRepository {
  MejaOfflineRepository({
    required this.remote,
    required this.antrean,
    required this.tulis,
    this.tokoId,
  });

  final MejaRemoteDataSource remote;
  final AntreanStore antrean;
  final AntreanTulis tulis;
  final String? tokoId;

  static const jenisBuka = 'BILL_BUKA';
  static const jenisRonde = 'BILL_RONDE';
  static const jenisBayar = 'BILL_BAYAR';

  /// Baris antrean bon toko ini yang belum terkirim, urut FIFO.
  Future<List<PesanAntrean>> _tertunda() async => [
    for (final p in await antrean.semua())
      if (p.status != StatusAntrean.terkirim &&
          p.jenis.startsWith('BILL_') &&
          (tokoId == null || p.tokoId == null || p.tokoId == tokoId))
        p,
  ];

  /// `/bills/<id>/rounds` → `<id>` (id server atau `lokal:<ref>`).
  static String? billIdDariPath(String path) {
    final seg = path.split('/');
    final i = seg.indexOf('bills');
    return i >= 0 && i + 1 < seg.length && seg[i + 1].isNotEmpty ? seg[i + 1] : null;
  }

  static List<BillItem> _itemRonde(PesanAntrean p) {
    final tampilan = p.body['_tampilan'];
    if (tampilan is! List) return const [];
    return [
      for (final t in tampilan)
        if (t is Map)
          BillItem(
            nama: (t['nama'] ?? '-').toString(),
            kuantitas: _angka(t['kuantitas']),
            harga: _angka(t['harga']),
            subtotal: _angka(t['harga']) * _angka(t['kuantitas']),
            satuan: t['satuan']?.toString(),
          ),
    ];
  }

  static double _angka(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  static double _totalRonde(PesanAntrean p) =>
      _itemRonde(p).fold(0, (s, it) => s + it.subtotal);

  @override
  Future<Result<List<Meja>>> peta() async {
    final List<Meja> daftar;
    try {
      daftar = await remote.peta();
    } on ApiException catch (e) {
      return Err(e);
    }
    final tertunda = await _tertunda();
    if (tertunda.isEmpty) return Ok(daftar);

    final dibayar = <String>{};
    final bukaUntukMeja = <String, PesanAntrean>{};
    final rondeTotal = <String, double>{};
    for (final p in tertunda) {
      switch (p.jenis) {
        case jenisBayar:
          final id = billIdDariPath(p.path);
          if (id != null) dibayar.add(id);
        case jenisBuka:
          bukaUntukMeja['${p.body['meja_id']}'] = p;
        case jenisRonde:
          final id = billIdDariPath(p.path);
          if (id != null) rondeTotal[id] = (rondeTotal[id] ?? 0) + _totalRonde(p);
      }
    }

    return Ok([
      for (final m in daftar) _gabung(m, dibayar, bukaUntukMeja, rondeTotal),
    ]);
  }

  Meja _gabung(
    Meja m,
    Set<String> dibayar,
    Map<String, PesanAntrean> bukaUntukMeja,
    Map<String, double> rondeTotal,
  ) {
    String? billId = m.billId;
    double? total = m.billTotal;
    int? pax = m.pax;
    if (billId != null && dibayar.contains(billId)) {
      billId = null;
      total = null;
      pax = null;
    }
    if (billId == null) {
      final buka = bukaUntukMeja[m.id];
      if (buka != null && !dibayar.contains(rujukanLokal(buka.clientRef))) {
        billId = rujukanLokal(buka.clientRef);
        total = 0;
        final px = buka.body['pax'];
        pax = px is num ? px.toInt() : int.tryParse('$px');
      }
    }
    if (billId != null && rondeTotal[billId] != null) {
      total = (total ?? 0) + rondeTotal[billId]!;
    }
    if (billId == m.billId && total == m.billTotal && pax == m.pax) return m;
    return Meja(id: m.id, nomor: m.nomor, kode: m.kode, billId: billId, billTotal: total, pax: pax);
  }

  @override
  Future<Result<HasilTulis>> bukaBon(String mejaId, {int pax = 1}) async {
    try {
      final hasil = await tulis.jalankan(
        jenis: jenisBuka,
        path: '/bills',
        body: {'meja_id': mejaId, 'meja_id_dec': mejaId, 'pax': pax},
        kirim: (badan) => remote.bukaBonBody(badanKirim(badan)),
      );
      return Ok(hasil);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<BillDetail>> detail(String billId) async {
    final tertunda = await _tertunda();
    final rondeLokal = [
      for (final p in tertunda)
        if (p.jenis == jenisRonde && billIdDariPath(p.path) == billId) p,
    ];
    final itemLokal = [for (final p in rondeLokal) ..._itemRonde(p)];
    final totalLokal = itemLokal.fold<double>(0, (s, it) => s + it.subtotal);

    if (adalahRujukanLokal(billId)) {
      return Ok(BillDetail(
        id: billId,
        nomor: 'Bon offline',
        status: 'BUKA',
        total: totalLokal,
        items: _gabungItem(const [], itemLokal),
      ));
    }
    try {
      final d = await remote.detail(billId);
      if (itemLokal.isEmpty) return Ok(d);
      return Ok(BillDetail(
        id: d.id,
        nomor: d.nomor,
        label: d.label,
        pax: d.pax,
        status: d.status,
        total: d.total + totalLokal,
        items: _gabungItem(d.items, itemLokal),
      ));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  /// Agregasi item per nama (+ harga) seperti tampilan server.
  static List<BillItem> _gabungItem(List<BillItem> server, List<BillItem> lokal) {
    if (lokal.isEmpty) return server;
    final urut = <String>[];
    final peta = <String, BillItem>{};
    for (final it in [...server, ...lokal]) {
      final k = '${it.nama}|${it.harga ?? ''}';
      final ada = peta[k];
      if (ada == null) {
        urut.add(k);
        peta[k] = it;
      } else {
        peta[k] = BillItem(
          nama: it.nama,
          kuantitas: ada.kuantitas + it.kuantitas,
          harga: it.harga,
          subtotal: ada.subtotal + it.subtotal,
          satuan: it.satuan ?? ada.satuan,
        );
      }
    }
    return [for (final k in urut) peta[k]!];
  }

  @override
  Future<Result<HasilTulis>> tambahRonde(
    String billId,
    List<Map<String, dynamic>> items, {
    List<Map<String, dynamic>> tampilan = const [],
  }) async {
    try {
      final hasil = await tulis.jalankan(
        jenis: jenisRonde,
        path: '/bills/$billId/rounds',
        body: {'items': items, if (tampilan.isNotEmpty) '_tampilan': tampilan},
        langsungAntre: adalahRujukanLokal(billId),
        kirim: (badan) => remote.tambahRondeBody(billId, badanKirim(badan)),
      );
      return Ok(hasil);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  /// Stok berkurang saat bon DIBAYAR (bukan saat ronde), mengikuti server.
  /// Delta hanya dari ronde yang masih di antrean (punya id produk); ronde
  /// yang sudah tercatat di server tidak diketahui id produknya.
  Future<Map<String, double>> _deltaStokBon(String billId) async {
    final delta = <String, double>{};
    for (final p in await _tertunda()) {
      if (p.jenis != jenisRonde || billIdDariPath(p.path) != billId) continue;
      final tampilan = p.body['_tampilan'];
      if (tampilan is! List) continue;
      for (final t in tampilan) {
        if (t is! Map || t['kelola_stok'] != true) continue;
        final id = '${t['id_produk'] ?? ''}';
        if (id.isEmpty) continue;
        delta[id] = (delta[id] ?? 0) - _angka(t['kuantitas']);
      }
    }
    return delta;
  }

  @override
  Future<Result<HasilTulis>> bayar(
    String billId, {
    required String tipe,
    required double dibayar,
  }) async {
    try {
      final hasil = await tulis.jalankan(
        jenis: jenisBayar,
        path: '/bills/$billId/settle',
        body: {'tipe_pembayaran': tipe, 'dibayar': dibayar},
        langsungAntre: adalahRujukanLokal(billId),
        deltaStok: await _deltaStokBon(billId),
        kirim: (badan) => remote.bayarBody(billId, badanKirim(badan)),
      );
      return Ok(hasil);
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  // Kelola meja tidak punya jalur offline — diteruskan apa adanya.
  @override
  Future<Result<List<Meja>>> daftarMeja({bool semua = false}) async {
    try {
      return Ok(await remote.daftarMeja(semua: semua));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<Meja>> tambahMeja(String nomor) async {
    try {
      return Ok(await remote.tambahMeja(nomor));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<Meja>> ubahMeja(String id, String nomor) async {
    try {
      return Ok(await remote.ubahMeja(id, nomor));
    } on ApiException catch (e) {
      return Err(e);
    }
  }

  @override
  Future<Result<Meja>> nonaktifkanMeja(String id) async {
    try {
      return Ok(await remote.nonaktifkanMeja(id));
    } on ApiException catch (e) {
      return Err(e);
    }
  }
}
