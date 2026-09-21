/// Kode metode pembayaran yang dipakai form bayar & lembar refund. Server
/// memvalidasi terhadap master `pos_metode_pembayaran` aktif; daftar ini
/// mengikuti nilai bawaan katalog (login mengirim `payment_methods`, belum
/// dipakai Android — pekerjaan lanjutan).
const metodePembayaranBawaan = ['TUNAI', 'QRIS', 'TRANSFER'];
