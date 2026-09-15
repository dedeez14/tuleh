/// Langganan perusahaan — SEMUA nilai (status, sisa hari, ambang peringatan,
/// tautan perpanjang, pesan) datang dari server (`GET /langganan/status`,
/// jawaban 402). Aplikasi tidak menyimpan ambang atau URL sendiri: nilai yang
/// kosong berarti "belum diisi pemilik platform", dan layar menampilkan
/// keadaan kosong — bukan mengarang nilai.
class StatusLangganan {
  const StatusLangganan({
    required this.status,
    this.planNama,
    this.periodeAkhir,
    this.sisaHari,
    this.perpanjangUrl,
    this.ambangPeringatanHari,
    this.blokirTulis = false,
  });

  /// AKTIF | TRIAL | GRACE | KEDALUWARSA (huruf besar, dari server).
  final String status;
  final String? planNama;

  /// Tanggal akhir periode (YYYY-MM-DD) atau null bila tanpa tenggat.
  final String? periodeAkhir;

  /// Sisa hari penuh; null = tanpa tenggat.
  final int? sisaHari;
  final String? perpanjangUrl;

  /// Mulai berapa hari sebelum berakhir banner peringatan tampil — dari
  /// master data server. null = server belum mengirim → tanpa banner hitung
  /// mundur (masa tenggang & berakhir tetap diberi tahu).
  final int? ambangPeringatanHari;

  /// true = server menolak permintaan tulis (402) selama langganan berakhir.
  final bool blokirTulis;

  bool get berakhir => status == 'KEDALUWARSA';
  bool get tenggang => status == 'GRACE';

  /// Banner peringatan: masa tenggang & berakhir selalu; aktif/uji coba bila
  /// sisa hari ≤ ambang dari server.
  bool get perluPeringatan {
    if (berakhir || tenggang) return true;
    final ambang = ambangPeringatanHari;
    final sisa = sisaHari;
    if (ambang == null || sisa == null) return false;
    return (status == 'AKTIF' || status == 'TRIAL') && sisa <= ambang;
  }

  static int? _angka(Object? v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());

  static String? _teks(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  factory StatusLangganan.fromJson(Map<String, dynamic> j) => StatusLangganan(
    status: (_teks(j['status']) ?? 'AKTIF').toUpperCase(),
    planNama: _teks(j['plan_nama']),
    periodeAkhir: _teks(j['periode_akhir']),
    sisaHari: _angka(j['sisa_hari']),
    perpanjangUrl: _teks(j['perpanjang_url']),
    ambangPeringatanHari: _angka(j['ambang_peringatan_hari']),
    blokirTulis: j['blokir_tulis'] == true,
  );
}

/// Penolakan 402 dari endpoint tulis: pesan & tautan dari server.
class LanggananTerkunci {
  const LanggananTerkunci({required this.pesan, this.perpanjangUrl, this.status});

  final String pesan;
  final String? perpanjangUrl;
  final String? status;

  /// Dari amplop 402: `{message, meta: {langganan: {status, perpanjang_url}}}`.
  factory LanggananTerkunci.dariAmplop(Object? body, {required String pesanBawaan}) {
    final m = body is Map ? body : const {};
    final meta = m['meta'];
    final langganan = meta is Map ? meta['langganan'] : null;
    final l = langganan is Map ? langganan : const {};
    final pesan = m['message']?.toString().trim() ?? '';
    final url = l['perpanjang_url']?.toString().trim() ?? '';
    final status = l['status']?.toString().trim() ?? '';
    return LanggananTerkunci(
      pesan: pesan.isEmpty ? pesanBawaan : pesan,
      perpanjangUrl: url.isEmpty ? null : url,
      status: status.isEmpty ? null : status.toUpperCase(),
    );
  }
}

/// Kontak CS dari `GET /kontak-cs` (mitra perekrut atau CS pusat — server
/// yang memutuskan). Nomor mentah tidak pernah dikirim, hanya tautan WA.
class KontakCs {
  const KontakCs({this.nama, this.waLink, this.sumber});

  final String? nama;
  final String? waLink;
  final String? sumber;

  bool get ada => waLink != null && waLink!.isNotEmpty;

  factory KontakCs.fromJson(Map<String, dynamic> j) {
    String? t(Object? v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    return KontakCs(nama: t(j['nama']), waLink: t(j['wa_link']), sumber: t(j['sumber']));
  }
}
