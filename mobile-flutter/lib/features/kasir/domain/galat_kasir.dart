import '../../../core/network/api_exception.dart';
import '../../toko/domain/entities/toko.dart';

/// Toko tempat sesi kasir pengguna sedang terbuka (dari `meta.sesi_toko` pada
/// 409 SESI_BEDA_TOKO). [kode] baru dikirim server versi baru.
class TokoSesi {
  const TokoSesi({required this.id, required this.nama, this.kode});

  /// Id terenkripsi yang SAH dipakai memanggil server (pilih toko, manifest),
  /// tetapi tidak bisa dibandingkan dengan id toko di `/tokos` — `encrypt_id`
  /// memakai IV acak sehingga toko yang sama punya ciphertext berbeda.
  final String id;

  final String nama;

  /// Kode toko stabil (mis. `TK-001`) — penanda yang bisa dibandingkan.
  final String? kode;
}

/// Kode mesin galat POS dari amplop server (`errors.kode[0]`), mis.
/// `SESI_BEDA_TOKO`. Server lama tanpa kode → string kosong, penanganan lama
/// tetap berlaku. Kode ini untuk DIBACA PROGRAM, tidak pernah ditampilkan —
/// yang dibaca kasir selalu kalimat server (`ApiException.message`).
String kodeGalat(ApiException e) {
  final kode = e.errors?['kode'];
  return kode != null && kode.isNotEmpty ? kode.first : '';
}

/// Toko sesi pada 409 SESI_BEDA_TOKO; null bila server tak menyebutkannya
/// (tanpa id, tombol "Pindah ke …" tidak bisa ditawarkan).
TokoSesi? tokoSesi(ApiException e) {
  final m = e.meta?['sesi_toko'];
  if (m is! Map) return null;
  final id = m['id']?.toString();
  if (id == null || id.isEmpty) return null;
  final kode = m['kode']?.toString();
  return TokoSesi(
    id: id,
    nama: (m['nama'] ?? 'toko sesi').toString(),
    kode: kode != null && kode.isNotEmpty ? kode : null,
  );
}

String _rapi(String? nilai) => (nilai ?? '').trim().toLowerCase();

/// Cari toko sesi [sesi] di dalam daftar toko pengguna.
///
/// Id TIDAK dipakai membandingkan (ciphertext non-deterministik, lihat
/// [TokoSesi.id]): urutannya `kode` (stabil) lalu `nama`. Bila kedua sisi
/// sudah berkode tetapi tak ada yang cocok, nama BUKAN bukti yang cukup —
/// dua toko bisa senama atau satu toko berganti nama — jadi hasilnya null.
/// Pemanggil TIDAK boleh jatuh ke id amplop 409 sebagai gantinya (aecad35):
/// id itu sah dipakai memanggil server, tetapi toko yang diwakilinya tak bisa
/// dicocokkan dengan daftar toko pengguna, sehingga tawaran "Pindah ke …"
/// mengaku memindahkan ke toko yang tak pernah diverifikasi. Tanpa kecocokan,
/// yang benar adalah tidak menawarkan perpindahan sama sekali.
/// Padanan `pilihTokoSesi()` di `lib/keranjang-toko.js` (desktop).
Toko? pilihTokoSesi(List<Toko> daftar, TokoSesi sesi) {
  final kode = _rapi(sesi.kode);
  if (kode.isNotEmpty) {
    for (final t in daftar) {
      if (_rapi(t.kode) == kode) return t;
    }
    if (daftar.any((t) => _rapi(t.kode).isNotEmpty)) return null;
  }

  final nama = _rapi(sesi.nama);
  if (nama.isEmpty) return null;
  for (final t in daftar) {
    if (_rapi(t.nama) == nama) return t;
  }
  return null;
}
