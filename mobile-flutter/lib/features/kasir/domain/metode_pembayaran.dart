/// Daftar CADANGAN kode metode pembayaran. Sumber sebenarnya adalah master
/// `pos_metode_pembayaran` di server, dibaca lewat `metodePembayaranProvider`
/// (GET /config → `payment_methods`); daftar ini hanya dipakai saat server
/// belum menjawab, gagal dimuat, atau versinya belum mengirim bidang itu —
/// supaya kasir tetap bisa menyelesaikan transaksi.
const metodePembayaranBawaan = ['TUNAI', 'QRIS', 'TRANSFER'];
