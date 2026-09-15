/// Penyamaran rahasia sebelum teks apa pun keluar dari perangkat (laporan
/// galat, ekor log). Kontrak `/diagnostik`: klien TIDAK boleh mengirim token,
/// PIN, sandi, atau kunci — server menyamarkan lagi, tetapi lapisan pertama
/// ada di sini.
const _disamarkan = '[disamarkan]';

final _bearer = RegExp(r'(Bearer\s+)[^\s"\x27,;]+', caseSensitive: false);

/// Token Sanctum `123|AbCd…` (id + 40 karakter acak).
final _tokenSanctum = RegExp(r'\b\d+\|[A-Za-z0-9]{20,}\b');

/// `"token": "…"`, `password=…`, `pin: 1234`, `Authorization: …`, dst.
final _kunciRahasia = RegExp(
  r'''(["']?\b(?:access_token|token|password|kata_sandi|sandi|pin|authorization|secret|server_key|client_key|api_key|signature)\b["']?\s*[:=]\s*)(["']?)([^"'\s,&}\]]+)''',
  caseSensitive: false,
);

String samarkan(String teks) => teks
    .replaceAllMapped(_bearer, (m) => '${m[1]}$_disamarkan')
    .replaceAll(_tokenSanctum, _disamarkan)
    .replaceAllMapped(_kunciRahasia, (m) => '${m[1]}${m[2]}$_disamarkan');
