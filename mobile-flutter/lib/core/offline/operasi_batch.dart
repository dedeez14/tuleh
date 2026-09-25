import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'antrean.dart';
import 'rujukan_lokal.dart';
import 'waktu_klien.dart';

// Operasi `POST /sync/v2/batch` (Fase 4, rancangan §B–§C) dari baris antrean —
// padanan desktop `frontend/src/main/offline/operasi-batch.js`. Murni (tanpa
// penyimpanan), kecuali [ambilKonfigSyncBatch] yang membaca `GET /config`.

/// Rute BARU (bukan `/sync/batch`): server lama / rollback menjawab 404 →
/// pengurai kembali ke kiriman per baris, alih-alih server v1 memproses amplop
/// v2 dengan aturan lama (diskon & toko dibuang).
const jalurSyncBatch = '/sync/v2/batch';

/// Jenis antrean yang dikirim lewat batch → `type` server. Jenis lain
/// (pengeluaran, stok masuk, opname, buka sesi, buka bon, ronde bon) tetap per
/// baris ke endpoint aslinya.
const jenisBatch = <String, String>{
  'CHECKOUT': 'checkout',
  'REFUND': 'refund',
  'BATAL': 'batal',
  'BILL_BAYAR': 'bills.settle',
  'ORDER_TRANSISI': 'orders.transition',
};

/// Segmen kecil: satu batch selesai jauh di bawah anggaran waktu server dan
/// tidak menahan worker PHP lama (paritas desktop).
const batasOpSegmen = 25;
const batasByteSegmen = 1500000;

/// Kunci data bantu di `body_json` (dibuang [badanKirim]): generasi "Kirim
/// ulang" — ikut sidik `client_ref` batch supaya kiriman ulang dari TINJAU
/// selalu dinilai ulang server, bukan dijawab replay batch lama.
const kunciKirimUlang = '_kirim_ulang';

const _labelKode = <String, String>{
  'OK': 'Terkirim',
  'VALIDASI': 'Data ditolak',
  'HAK_AKSES': 'Di luar akses toko Anda',
  'OTORISASI_WAJIB': 'Butuh persetujuan atasan — ulangi saat online',
  'SESI_TIDAK_ADA': 'Buka sesi kasir di toko ini',
  'SESI_BEDA_TOKO': 'Sesi kasir terbuka di toko lain',
  'STOK_KURANG': 'Stok tidak cukup',
  'PRASYARAT': 'Menunggu transaksi asal tercatat',
  'TIDAK_DITEMUKAN': 'Tidak ditemukan di server',
  'KONFLIK': 'Bentrok dengan data di server',
  'PELUNASAN_HARUS_REFUND': 'Transaksi pelunasan — gunakan Refund',
  'DITUNDA': 'Ditunda server',
  'LANGGANAN': 'Langganan berakhir',
  'GALAT_SERVER': 'Galat server',
  'INDUK_TINJAU': 'Menunggu transaksi asal ditinjau',
  'INDUK_TIDAK_DIKENAL': 'Transaksi asal tidak bisa dirujuk',
  'BATCH_TERLALU_BESAR': 'Data terlalu besar',
  'BATCH_BERJALAN': 'Server masih memproses kiriman sebelumnya',
};

const _labelPeringatan = <String, String>{
  'SELISIH_STOK': 'Selisih stok',
  'SESI_TUTUP': 'Masuk sesi yang sudah ditutup',
  'SUDAH_DIBATALKAN': 'Sudah dibatalkan sebelumnya',
  'SUDAH_DI_TAHAP': 'Pesanan sudah di tahap itu',
  'SESI_BERBEDA': 'Masuk sesi yang dibuka setelahnya',
  'JAM_PERANGKAT': 'Jam perangkat tidak tepat',
};

/// Istilah kasir untuk kode mesin server (§B.4) & kode lokal app; kode asing
/// ditampilkan apa adanya.
String labelKode(String? kode) =>
    _labelKode[kode] ?? ((kode == null || kode.isEmpty) ? 'Ditolak server' : kode);

List<String> labelPeringatan(Object? daftar) => [
  if (daftar is List)
    for (final k in daftar) _labelPeringatan['$k'] ?? '$k',
];

/// `galat_terakhir` berkode: `[KODE] pesan` (rancangan R-18 — kode tidak punya
/// kolom sendiri; pengurai & layar mengurai awalannya).
String galatBerkode(String kode, String pesan) => '[$kode] $pesan';

final _polaKode = RegExp(r'^\[([A-Z][A-Z0-9_]*)\] ?');

/// Kode mesin dari `galat_terakhir`, atau null (galat lama tanpa kode).
String? kodeGalat(String? galat) => galat == null ? null : _polaKode.firstMatch(galat)?.group(1);

/// Pesan manusia tanpa awalan kode.
String pesanGalat(String galat) => galat.replaceFirst(_polaKode, '');

/// Blok `sync_batch` dari `GET /config` (kontrak §13.1).
class KonfigSyncBatch {
  const KonfigSyncBatch({required this.versi, this.maksOperasi, this.maksByte, this.saranOperasi});

  final int versi;
  final int? maksOperasi;
  final int? maksByte;
  final int? saranOperasi;

  /// Mode batch hanya untuk kontrak v2 ke atas.
  bool get aktif => versi >= 2;

  static int? _positif(Object? v) {
    final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
    return n != null && n > 0 ? n : null;
  }

  /// `/config` tanpa `sync_batch` (server lama, Mode Demo, atau
  /// `pos_idempotensi` belum ada di server) = versi 0 → jalur per baris lama.
  static KonfigSyncBatch dariConfig(Map<String, dynamic>? data) {
    final sb = data?['sync_batch'];
    if (sb is! Map) return const KonfigSyncBatch(versi: 0);
    return KonfigSyncBatch(
      versi: _positif(sb['versi']) ?? 0,
      maksOperasi: _positif(sb['maks_operasi']),
      maksByte: _positif(sb['maks_byte']),
      saranOperasi: _positif(sb['saran_operasi_per_segmen']),
    );
  }

  /// Jumlah operasi per segmen: 25, `maks_operasi`/`saran_operasi_per_segmen`
  /// server bila lebih kecil, dan batas adaptif setelah 413.
  int batasOp(int adaptif) => [batasOpSegmen, ?maksOperasi, ?saranOperasi, adaptif].reduce(min).clamp(1, batasOpSegmen);

  /// Byte per segmen: 1,5 MB dan ≤ 70% `maks_byte` server.
  int get batasByte => maksByte == null ? batasByteSegmen : min(batasByteSegmen, (maksByte! * 0.7).floor());
}

/// `GET /config` → [KonfigSyncBatch]. null HANYA bila gagal dibaca (jaringan,
/// 5xx) — pengurai tidak mememo kegagalan; server tanpa blok = versi 0.
Future<KonfigSyncBatch?> ambilKonfigSyncBatch(Dio dio) async {
  try {
    final res = await dio.get<dynamic>('/config');
    final code = res.statusCode ?? 0;
    final body = res.data;
    if (code < 200 || code >= 300 || body is! Map || body['success'] != true) return null;
    final data = body['data'];
    return KonfigSyncBatch.dariConfig(data is Map ? Map<String, dynamic>.from(data) : null);
  } catch (_) {
    return null;
  }
}

final _polaBulat = RegExp(r'^\s*[+-]?\d+\s*$');

/// Bilangan bulat untuk sidik `client_ref` (paritas desktop `bulatSidik`):
/// angka hingga → dipotong ke arah nol (-0,5 → 0); teks bilangan bulat
/// (`"2"`, `" +3 "`) → nilainya; selain itu (null, NaN, ±∞, `"1.5"`, `"0x10"`,
/// boolean) → 0. `truncate()` pada NaN/∞ melempar — karena itu dicek dulu.
int _bulatSidik(Object? v) {
  if (v is num) return v.isFinite ? v.truncate() : 0;
  if (v is String && _polaBulat.hasMatch(v)) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

/// Generasi kirim ulang baris (0 = belum pernah).
int kirimUlangKe(PesanAntrean p) => _bulatSidik(p.body[kunciKirimUlang]);

/// Segmen id pada jalur `/<grup>/<id>/…` (sudah di-decode), null bila bukan grup itu.
String? idDariJalur(String jalur, String grup) {
  final seg = jalur.split('/');
  if (seg.length < 3 || seg[1] != grup || seg[2].isEmpty) return null;
  try {
    return Uri.decodeComponent(seg[2]);
  } catch (_) {
    // Paritas desktop: segmen rusak (`%ZZ`, UTF-8 tak sah) bukan id yang sah.
    return null;
  }
}

/// Baris antrean → satu operasi v2. Badan tersimpan dipakai apa adanya (kunci
/// `_…` dibuang, `waktu_klien` ber-offset) + field batch: toko KEJADIAN untuk
/// semua tipe (bukan toko aktif saat kirim), rujukan dokumen dari jalur.
/// [path] = jalur yang rujukan `lokal:` bon-nya sudah diganti id server
/// (BILL_BAYAR); REFUND/BATAL atas transaksi lokal merujuk `transaksi_ref`.
Map<String, dynamic> opDariBaris(
  PesanAntrean p, {
  required String deviceId,
  required DateTime kini,
  String? path,
  String? nomorLokal,
}) {
  final type = jenisBatch[p.jenis];
  if (type == null) throw ArgumentError('Jenis ${p.jenis} tidak dikirim lewat batch.');
  final jalur = path ?? p.path;
  final payload = badanKirim(p.body);
  // Server menolak item bila client_ref payload ≠ idempotency_key.
  payload['client_ref'] = p.clientRef;
  // [badanKirim] sudah merapikan waktu yang terurai (tanpa zona → lokal +
  // offset); yang kosong/tak terurai → waktu baris dibuat (paritas desktop).
  final wk = payload['waktu_klien'];
  if (wk is! String || DateTime.tryParse(wk) == null) payload['waktu_klien'] = waktuKlienIso(p.dibuat);
  final toko = p.tokoId;
  if (toko != null && toko.isNotEmpty) payload['toko_id'] = toko;
  switch (type) {
    case 'checkout':
      // Penjualan yang diantrekan sudah terjadi fisik: diterima walau stok kurang (selisih dicatat).
      payload['offline'] = true;
      final diBadan = '${p.body['nomor_lokal'] ?? ''}';
      final nomor = diBadan.isNotEmpty ? diBadan : (nomorLokal ?? '');
      if (nomor.isNotEmpty) payload['nomor_lokal'] = nomor.length > 30 ? nomor.substring(0, 30) : nomor;
    case 'refund' || 'batal':
      final ref = rujukanDalamPath(jalur);
      if (ref != null) {
        payload['transaksi_ref'] = ref;
      } else {
        payload['transaksi_id'] = idDariJalur(jalur, 'transaksi');
      }
    case 'bills.settle':
      payload['bon_id'] = idDariJalur(jalur, 'bills');
    default:
      payload['order_id'] = idDariJalur(jalur, 'orders');
  }
  return {
    'idempotency_key': p.clientRef,
    if (deviceId.isNotEmpty) 'device_id': deviceId,
    if (p.urut > 0) 'device_seq': p.urut,
    // Umur baris menurut jam perangkat sendiri: kebal jam absolut yang salah.
    'umur_detik': max(0, kini.difference(p.dibuat).inSeconds),
    'type': type,
    'payload': payload,
  };
}

/// Komposisi segmen urutan kirim: `<type>:<clientRef>:<kirimUlangKe>` per baris.
/// Baris null / berjenis non-batch DIKECUALIKAN (tak pernah ikut segmen) —
/// bukan ditulis `null:…` (paritas desktop).
String sidikKomposisi(Iterable<PesanAntrean?> baris) => [
  for (final p in baris)
    if (p != null && jenisBatch.containsKey(p.jenis)) '${jenisBatch[p.jenis]}:${p.clientRef}:${kirimUlangKe(p)}',
].join('\n');

/// `client_ref` batch deterministik (sha256 hex 64): kiriman ulang identik
/// setelah putus jaringan = ref sama = replay server; komposisi / generasi
/// kirim ulang berbeda = ref berbeda. [garam] hanya untuk 409 BATCH_REF_BENTROK;
/// dinormalkan seperti desktop: dipotong bulat, akhiran `|<g>` hanya bila g > 0
/// (negatif, 0, 0,9, NaN, teks bukan angka → tanpa akhiran; 1,7 → `|1`).
String clientRefBatch(String deviceId, Iterable<PesanAntrean?> baris, {Object? garam = 0}) {
  final g = _bulatSidik(garam);
  return sha256.convert(utf8.encode('$deviceId|${sidikKomposisi(baris)}${g > 0 ? '|$g' : ''}')).toString();
}

/// Ukuran JSON dalam byte UTF-8.
int ukuranJson(Object? nilai) => utf8.encode(jsonEncode(nilai)).length;

/// Satu hasil item jawaban batch v2 (§B.3).
class HasilItemBatch {
  const HasilItemBatch({
    required this.idempotencyKey,
    required this.accepted,
    required this.kode,
    this.type,
    this.serverId,
    this.nomor,
    this.retriable = false,
    this.message = '',
    this.idempoten = false,
    this.peringatan = const [],
    this.data,
  });

  final String idempotencyKey;
  final bool accepted;
  final String kode;
  final String? type;
  final String? serverId;
  final String? nomor;
  final bool retriable;
  final String message;
  final bool idempoten;
  final List<String> peringatan;
  final Map<String, dynamic>? data;

  /// null bila item tanpa `idempotency_key` (tidak bisa dicocokkan ke baris).
  static HasilItemBatch? dariJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final key = m['idempotency_key'];
    if (key is! String || key.isEmpty) return null;
    final accepted = m['accepted'] == true;
    final kodeMentah = m['kode'];
    final kode = kodeMentah is String && kodeMentah.isNotEmpty ? kodeMentah : (accepted ? 'OK' : 'GALAT_SERVER');
    String teks(Object? v) => v == null ? '' : '$v'.trim();
    final msg = teks(m['message']);
    final alasan = teks(m['reason']);
    final per = m['peringatan'];
    final data = m['data'];
    return HasilItemBatch(
      idempotencyKey: key,
      accepted: accepted,
      kode: kode,
      type: m['type']?.toString(),
      serverId: m['server_id']?.toString(),
      nomor: m['nomor']?.toString(),
      retriable: m['retriable'] == true,
      message: msg.isNotEmpty ? msg : (alasan.isNotEmpty ? alasan : labelKode(kode)),
      idempoten: m['idempoten'] == true,
      peringatan: [if (per is List) for (final x in per) '$x'],
      data: data is Map ? Map<String, dynamic>.from(data) : null,
    );
  }

  /// `hasil` baris TERKIRIM (paritas desktop `hasilDariItem`); `id` dipakai
  /// rujukan `lokal:` turunan, `nomor_lokal` untuk "L-… → POS/…" di layar.
  Map<String, dynamic> keHasil({String? nomorLokal}) => {
    'id': serverId,
    'nomor': nomor,
    'kode': kode,
    'tipe': type,
    'peringatan': peringatan,
    'idempoten': idempoten,
    '_idempoten': idempoten,
    'data': data,
    if (nomorLokal != null && nomorLokal.isNotEmpty) 'nomor_lokal': nomorLokal,
  };
}

/// Id item transaksi server dari hasil induk: ringkasan batch
/// (`data.items[{baris, id}]`) atau struk per baris (`items[i].id`, urut id =
/// urutan `baris` — server K-22).
String? idItemDariHasil(Map<String, dynamic>? hasil, Object? baris) {
  if (hasil == null) return null;
  final n = _bulatBaris(baris);
  if (n == null || n < 0) return null;
  final data = hasil['data'];
  final ringkas = data is Map ? data['items'] : null;
  if (ringkas is List) {
    // Paritas desktop (`find`): entri PERTAMA ber-`baris` itu; id kosong → struk.
    for (final x in ringkas) {
      if (x is Map && _bulatBaris(x['baris']) == n) {
        final id = _idTakKosong(x['id']);
        if (id != null) return id;
        break;
      }
    }
  }
  final struk = hasil['items'];
  if (struk is List && n < struk.length) {
    final x = struk[n];
    if (x is Map) return _idTakKosong(x['id']);
  }
  return null;
}

/// Nomor `baris` sebagai bilangan bulat: angka / teks angka yang nilainya
/// bulat (`'1.0'` = 1); pecahan, NaN, ∞, dan bukan angka → null.
int? _bulatBaris(Object? v) {
  final n = v is num ? v : (v is String ? num.tryParse(v.trim()) : null);
  if (n == null || !n.isFinite || n % 1 != 0) return null;
  return n.toInt();
}

String? _idTakKosong(Object? v) {
  final s = v == null ? '' : '$v';
  return s.isEmpty ? null : s;
}

/// Badan refund berujukan `baris` → `id` item server dari hasil induk, untuk
/// kiriman PER BARIS ke endpoint tunggal. null bila ada baris yang tak bisa
/// dirujuk (induk terkirim tanpa rincian item).
Map<String, dynamic>? barisKeIdItem(Map<String, dynamic> body, Map<String, dynamic>? hasilInduk) {
  final items = body['items'];
  if (items is! List) return body;
  final baru = <Object?>[];
  for (final it in items) {
    if (it is Map && it['baris'] != null) {
      final id = idItemDariHasil(hasilInduk, it['baris']);
      if (id == null) return null;
      baru.add({'id': id, 'kuantitas': it['kuantitas']});
    } else {
      baru.add(it);
    }
  }
  return {...body, 'items': baru};
}
