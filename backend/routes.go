package main

import (
	"encoding/json"
	"net/http"
	"time"
)

// Allowlist endpoint MOVERA POS API — hanya rute di tabel ini yang diteruskan.
// cacheTTL > 0 berarti respons 200 GET di-cache per token.
// purge = prefix cache (per token) yang dihapus setelah mutasi sukses.
type route struct {
	method  string
	pattern string // relatif terhadap /api/pos/v1
	cache   time.Duration
	purge   []string
	isLogin bool // dikenai rate limit ketat anti brute-force
}

const apiPrefix = "/api/pos/v1"

var routeTable = []route{
	// Util
	{method: "GET", pattern: "/ping"},
	{method: "GET", pattern: "/config", cache: 5 * time.Minute},
	{method: "GET", pattern: "/bidang-usaha", cache: 5 * time.Minute},

	// Langganan & Kontak CS (Sistem Mitra §6.5) — info tenant
	{method: "GET", pattern: "/langganan/status", cache: 60 * time.Second},
	{method: "POST", pattern: "/langganan/bayar"}, // buat/ambil tagihan Midtrans Snap — TANPA cache (idempoten di server)
	{method: "GET", pattern: "/kontak-cs", cache: 5 * time.Minute},

	// Toko POS (multi-vertical MOVERA)
	{method: "GET", pattern: "/tokos", cache: 5 * time.Minute},
	{method: "POST", pattern: "/tokos", purge: []string{apiPrefix + "/tokos"}},
	{method: "GET", pattern: "/tokos/{id}", cache: 5 * time.Minute},
	{method: "GET", pattern: "/tokos/{id}/manifest", cache: 5 * time.Minute},

	// Stasiun kerja & meja (endpoint server menyusul — Blueprint §13)
	{method: "GET", pattern: "/stations", cache: 30 * time.Second},
	{method: "POST", pattern: "/stations", purge: []string{apiPrefix + "/stations"}},
	{method: "PATCH", pattern: "/stations/{id}", purge: []string{apiPrefix + "/stations"}},
	{method: "DELETE", pattern: "/stations/{id}", purge: []string{apiPrefix + "/stations"}},
	{method: "GET", pattern: "/tables", cache: 5 * time.Minute},
	{method: "POST", pattern: "/tables", purge: []string{apiPrefix + "/tables"}},
	{method: "GET", pattern: "/tables/{id}", cache: 5 * time.Minute},

	// Order (F&B/jasa) & sinkronisasi offline — selalu segar
	{method: "GET", pattern: "/orders"},
	{method: "POST", pattern: "/orders"},
	{method: "GET", pattern: "/orders/{id}"},
	{method: "POST", pattern: "/orders/{id}/transition"},
	{method: "POST", pattern: "/sync/batch", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan", apiPrefix + "/transaksi"}},

	// Bon meja (open bill dine-in) — selalu segar; pelunasan menyegarkan stok/laporan/transaksi
	{method: "GET", pattern: "/bills"},
	{method: "POST", pattern: "/bills"},
	{method: "GET", pattern: "/bills/{id}"},
	{method: "PATCH", pattern: "/bills/{id}"},
	{method: "GET", pattern: "/bills/{id}/prebill"},
	{method: "POST", pattern: "/bills/{id}/rounds"},
	{method: "POST", pattern: "/bills/{id}/merge"},
	{method: "POST", pattern: "/bills/{id}/void"},
	{method: "POST", pattern: "/bills/{id}/settle", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan", apiPrefix + "/transaksi"}},

	// Auth
	{method: "POST", pattern: "/auth/login", isLogin: true},
	{method: "GET", pattern: "/auth/me"},
	{method: "POST", pattern: "/auth/logout", purge: []string{""}}, // "" = semua cache token ini

	// Produk & master (+ CRUD manajemen — O/M; mutasi menyegarkan katalog & laporan stok)
	{method: "GET", pattern: "/produk", cache: 15 * time.Second},
	{method: "POST", pattern: "/produk", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan"}},
	{method: "GET", pattern: "/produk/barcode/{barcode}", cache: 15 * time.Second},
	{method: "GET", pattern: "/produk/{id}", cache: 15 * time.Second},
	{method: "PATCH", pattern: "/produk/{id}", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan"}},
	{method: "DELETE", pattern: "/produk/{id}", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan"}},
	{method: "GET", pattern: "/kategori", cache: 5 * time.Minute},
	{method: "GET", pattern: "/gudang", cache: 5 * time.Minute},
	{method: "GET", pattern: "/satuan", cache: 5 * time.Minute},

	// Pelanggan (+ quick add — semua peran; kebutuhan operasional kasir)
	{method: "GET", pattern: "/pelanggan", cache: 15 * time.Second},
	{method: "POST", pattern: "/pelanggan", purge: []string{apiPrefix + "/pelanggan"}},
	{method: "POST", pattern: "/pelanggan/quick", purge: []string{apiPrefix + "/pelanggan"}},
	{method: "GET", pattern: "/pelanggan/{id}", cache: time.Minute},

	// Inventory (kelola stok — O/M). Mutasi menyegarkan katalog & laporan.
	{method: "POST", pattern: "/inventory/stok-masuk", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan"}},
	{method: "POST", pattern: "/inventory/opname", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan"}},
	{method: "GET", pattern: "/inventory/riwayat"}, // selalu segar (poll realtime ~10 dtk)

	// Pengeluaran (kas keluar — O/M). Mutasi menyegarkan laporan keuangan.
	{method: "GET", pattern: "/pengeluaran", cache: 15 * time.Second},
	{method: "POST", pattern: "/pengeluaran", purge: []string{apiPrefix + "/pengeluaran", apiPrefix + "/laporan"}},
	{method: "DELETE", pattern: "/pengeluaran/{id}", purge: []string{apiPrefix + "/pengeluaran", apiPrefix + "/laporan"}},

	// Sesi kasir — selalu segar (tanpa cache)
	{method: "GET", pattern: "/sesi/aktif"},
	{method: "GET", pattern: "/sesi"},
	{method: "POST", pattern: "/sesi/buka", purge: []string{apiPrefix + "/laporan"}},
	{method: "POST", pattern: "/sesi/{id}/tutup", purge: []string{apiPrefix + "/laporan"}},
	{method: "GET", pattern: "/sesi/{id}"},
	{method: "GET", pattern: "/sesi/{id}/rekap"},

	// Transaksi — mutasi menyegarkan stok & laporan
	{method: "POST", pattern: "/transaksi/checkout", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan"}},
	{method: "GET", pattern: "/transaksi"},
	{method: "GET", pattern: "/transaksi/{id}"},
	{method: "GET", pattern: "/transaksi/{id}/struk"},
	{method: "POST", pattern: "/transaksi/{id}/batal", purge: []string{apiPrefix + "/produk", apiPrefix + "/laporan"}},

	// Pengaturan Usaha & Struk (profil perusahaan). Mutasi menyegarkan /config
	// (blok company+struk) & /pengaturan. Upload logo = multipart (O/M).
	{method: "GET", pattern: "/pengaturan/usaha", cache: 30 * time.Second},
	{method: "PUT", pattern: "/pengaturan/usaha", purge: []string{apiPrefix + "/pengaturan", apiPrefix + "/config"}},
	{method: "POST", pattern: "/pengaturan/usaha/logo", purge: []string{apiPrefix + "/pengaturan", apiPrefix + "/config"}},
	{method: "POST", pattern: "/pengaturan/usaha/logo-struk", purge: []string{apiPrefix + "/pengaturan", apiPrefix + "/config"}},

	// Keamanan (PIN / App Lock). Status juga di /config → mutasi purge /config.
	{method: "GET", pattern: "/pengaturan/keamanan", cache: 15 * time.Second},
	{method: "PUT", pattern: "/pengaturan/keamanan", purge: []string{apiPrefix + "/pengaturan", apiPrefix + "/config"}},
	{method: "POST", pattern: "/keamanan/verifikasi"}, // verifikasi PIN — tanpa cache (rate-limit di server)

	// Hold transaksi (parkir keranjang) — selalu segar, lintas perangkat
	{method: "GET", pattern: "/hold"},
	{method: "POST", pattern: "/hold"},
	{method: "DELETE", pattern: "/hold/{id}"},

	// Favorit / promo / terlaris (bahan kasir)
	{method: "GET", pattern: "/produk/terlaris", cache: 60 * time.Second},
	{method: "PATCH", pattern: "/produk/{id}/favorit", purge: []string{apiPrefix + "/produk"}},
	{method: "PUT", pattern: "/produk/{id}/promo", purge: []string{apiPrefix + "/produk"}},

	// Laporan (O/M sejak rilis peran — gateway hanya meneruskan; penegakan di server)
	{method: "GET", pattern: "/laporan/penjualan-harian", cache: 30 * time.Second},
	{method: "GET", pattern: "/laporan/penjualan-produk", cache: 30 * time.Second},
	{method: "GET", pattern: "/laporan/stok", cache: 30 * time.Second},
	{method: "GET", pattern: "/laporan/rekap-kasir", cache: 30 * time.Second},
	{method: "GET", pattern: "/laporan/keuangan", cache: 30 * time.Second},
	{method: "GET", pattern: "/laporan/tahapan", cache: 30 * time.Second},
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{"success": false, "message": message})
}

func buildMux(p *proxy, limiter *rateLimiter) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"success": true,
			"data": map[string]any{
				"app":      appName,
				"version":  appVersion,
				"upstream": p.upstream.String(),
				"time":     time.Now().Format(time.RFC3339),
			},
		})
	})

	for _, rt := range routeTable {
		rt := rt
		handler := p.handler(rt)
		if rt.isLogin {
			handler = loginRateLimit(limiter, rateLoginPerMin, handler)
		}
		mux.Handle(rt.method+" "+apiPrefix+rt.pattern, handler)
	}

	// Selain allowlist → tolak dengan envelope yang dikenali frontend
	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		writeError(w, http.StatusNotFound, "Endpoint tidak dikenal.")
	})

	return mux
}
