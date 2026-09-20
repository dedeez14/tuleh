package main

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// newTestGateway membangun mux lengkap dengan upstream palsu.
func newTestGateway(t *testing.T, upstreamHandler http.Handler) (*httptest.Server, *atomic.Int64) {
	t.Helper()
	var hits atomic.Int64
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		upstreamHandler.ServeHTTP(w, r)
	}))
	t.Cleanup(upstream.Close)

	u, _ := url.Parse(upstream.URL)
	cache := newTTLCache(64)
	limiter := newRateLimiter(time.Now)
	p := newProxy(u, cache, slog.New(slog.NewTextHandler(io.Discard, nil)))
	gw := httptest.NewServer(buildMux(p, limiter))
	t.Cleanup(gw.Close)
	return gw, &hits
}

func TestProxyMeneruskanPingDanEnvelope(t *testing.T) {
	gw, _ := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/pos/v1/ping" {
			t.Errorf("path upstream salah: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"success":true,"data":{"app":"stub"}}`))
	}))

	res, err := http.Get(gw.URL + "/api/pos/v1/ping")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)

	if res.StatusCode != 200 {
		t.Fatalf("status = %d", res.StatusCode)
	}
	if !strings.Contains(string(body), `"success":true`) {
		t.Fatalf("body tidak diteruskan: %s", body)
	}
}

func TestProxyEndpointTakDikenalDitolak(t *testing.T) {
	gw, hits := newTestGateway(t, http.NotFoundHandler())

	res, err := http.Get(gw.URL + "/api/pos/v1/rahasia/../../etc")
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()

	if res.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, ingin 404", res.StatusCode)
	}
	if hits.Load() != 0 {
		t.Fatal("permintaan di luar allowlist tidak boleh menyentuh upstream")
	}
}

func TestProxyCacheHitTanpaMemukulUpstreamDuaKali(t *testing.T) {
	gw, hits := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"success":true,"data":[]}`))
	}))

	client := &http.Client{}
	makeReq := func() *http.Response {
		req, _ := http.NewRequest("GET", gw.URL+"/api/pos/v1/kategori", nil)
		req.Header.Set("Authorization", "Bearer token-uji")
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		return res
	}

	first := makeReq()
	second := makeReq()

	if hits.Load() != 1 {
		t.Fatalf("upstream terpukul %d kali, ingin 1 (cache)", hits.Load())
	}
	if first.Header.Get("X-MPos-Cache") != "MISS" || second.Header.Get("X-MPos-Cache") != "HIT" {
		t.Fatalf("penanda cache salah: %s lalu %s",
			first.Header.Get("X-MPos-Cache"), second.Header.Get("X-MPos-Cache"))
	}
}

func TestProxyCacheTerpisahAntarToken(t *testing.T) {
	gw, hits := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"success":true}`))
	}))

	for _, token := range []string{"Bearer kasir-a", "Bearer kasir-b"} {
		req, _ := http.NewRequest("GET", gw.URL+"/api/pos/v1/kategori", nil)
		req.Header.Set("Authorization", token)
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
	}

	if hits.Load() != 2 {
		t.Fatalf("token berbeda wajib miss masing-masing; upstream terpukul %d kali", hits.Load())
	}
}

func TestProxyCheckoutMembersihkanCacheProduk(t *testing.T) {
	gw, hits := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"success":true,"data":[]}`))
	}))

	do := func(method, path string) {
		req, _ := http.NewRequest(method, gw.URL+path, strings.NewReader("{}"))
		req.Header.Set("Authorization", "Bearer kasir")
		req.Header.Set("Content-Type", "application/json")
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
	}

	do("GET", "/api/pos/v1/produk")              // isi cache (1)
	do("GET", "/api/pos/v1/produk")              // HIT (masih 1)
	do("POST", "/api/pos/v1/transaksi/checkout") // mutasi (2) → purge produk
	do("GET", "/api/pos/v1/produk")              // MISS lagi (3)

	if hits.Load() != 3 {
		t.Fatalf("upstream terpukul %d kali, ingin 3 (cache di-purge setelah checkout)", hits.Load())
	}
}

// Refund mengubah stok & laporan: cache /produk wajib dibersihkan seperti checkout.
func TestProxyRefundMembersihkanCacheProduk(t *testing.T) {
	gw, hits := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"success":true,"data":[]}`))
	}))

	do := func(method, path string) {
		req, _ := http.NewRequest(method, gw.URL+path, strings.NewReader("{}"))
		req.Header.Set("Authorization", "Bearer manajer")
		req.Header.Set("Content-Type", "application/json")
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
	}

	do("GET", "/api/pos/v1/produk")               // isi cache (1)
	do("GET", "/api/pos/v1/produk")               // HIT (masih 1)
	do("POST", "/api/pos/v1/transaksi/T1/refund") // mutasi (2) → purge produk
	do("GET", "/api/pos/v1/produk")               // MISS lagi (3)

	if hits.Load() != 3 {
		t.Fatalf("upstream terpukul %d kali, ingin 3 (cache di-purge setelah refund)", hits.Load())
	}
}

// Setiap entri tabel rute harus terdaftar tanpa panik (ServeMux Go 1.22 panik saat pola
// bentrok, mis. /produk/{id}/toko vs /produk/barcode/{barcode}) DAN benar-benar diteruskan.
func TestSemuaRuteTerdaftarDanDiteruskan(t *testing.T) {
	func() {
		defer func() {
			if rec := recover(); rec != nil {
				t.Fatalf("buildMux panik: %v", rec)
			}
		}()
		u, _ := url.Parse("https://upstream.invalid")
		buildMux(newProxy(u, newTTLCache(8), slog.New(slog.NewTextHandler(io.Discard, nil))), newRateLimiter(time.Now))
	}()

	var terakhir atomic.Value
	gw, _ := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		terakhir.Store(r.Method + " " + r.URL.Path)
		_, _ = w.Write([]byte(`{"success":true,"data":null}`))
	}))
	for _, rt := range routeTable {
		if rt.isLogin {
			continue // dibatasi 5/menit — cukup diuji terpisah
		}
		jalur := apiPrefix + strings.NewReplacer("{id}", "X1", "{barcode}", "899").Replace(rt.pattern)
		req, _ := http.NewRequest(rt.method, gw.URL+jalur, strings.NewReader("{}"))
		req.Header.Set("Content-Type", "application/json")
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		if res.Header.Get(gatewayHeader) != "" || res.StatusCode != http.StatusOK {
			t.Errorf("%s %s tidak diteruskan: status %d penanda %q", rt.method, jalur, res.StatusCode, res.Header.Get(gatewayHeader))
			continue
		}
		if got := terakhir.Load(); got != rt.method+" "+jalur {
			t.Errorf("upstream menerima %v, ingin %s %s", got, rt.method, jalur)
		}
	}
}

func TestUpstreamTakTerjangkauBerpenandaDanNetralMerek(t *testing.T) {
	mati := httptest.NewServer(http.NotFoundHandler())
	u, _ := url.Parse(mati.URL)
	mati.Close() // port tertutup → koneksi ditolak

	p := newProxy(u, newTTLCache(8), slog.New(slog.NewTextHandler(io.Discard, nil)))
	gw := httptest.NewServer(buildMux(p, newRateLimiter(time.Now)))
	t.Cleanup(gw.Close)

	for _, method := range []string{"GET", "POST"} {
		req, _ := http.NewRequest(method, gw.URL+"/api/pos/v1/transaksi/checkout", strings.NewReader("{}"))
		if method == "GET" {
			req, _ = http.NewRequest(method, gw.URL+"/api/pos/v1/produk", nil)
		}
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(res.Body)
		res.Body.Close()
		if res.StatusCode != http.StatusBadGateway {
			t.Fatalf("%s: status = %d, ingin 502", method, res.StatusCode)
		}
		if res.Header.Get(gatewayHeader) != gatewayUpstreamUnreached {
			t.Fatalf("%s: penanda gateway = %q", method, res.Header.Get(gatewayHeader))
		}
		if strings.Contains(strings.ToUpper(string(body)), "MOVERA") {
			t.Fatalf("pesan gateway tidak boleh memuat merek: %s", body)
		}
		if !strings.Contains(string(body), `"success":false`) {
			t.Fatalf("amplop galat salah: %s", body)
		}
	}
}

func TestJawabanServerTidakDiberiPenandaGateway(t *testing.T) {
	gw, _ := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte(`{"success":false,"message":"pemeliharaan"}`))
	}))
	res, err := http.Post(gw.URL+"/api/pos/v1/pengeluaran", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusServiceUnavailable || res.Header.Get(gatewayHeader) != "" {
		t.Fatalf("503 dari server harus diteruskan apa adanya: %d %q", res.StatusCode, res.Header.Get(gatewayHeader))
	}
}

func TestMejaUbahDanNonaktifkanMembersihkanCacheMeja(t *testing.T) {
	var metode []string
	gw, hits := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		metode = append(metode, r.Method)
		_, _ = w.Write([]byte(`{"success":true,"data":[]}`))
	}))
	do := func(method, path string) int {
		req, _ := http.NewRequest(method, gw.URL+path, strings.NewReader(`{"nomor":"2"}`))
		req.Header.Set("Authorization", "Bearer kasir")
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		return res.StatusCode
	}
	do("GET", "/api/pos/v1/tables")
	do("GET", "/api/pos/v1/tables") // HIT
	if s := do("PUT", "/api/pos/v1/tables/M1"); s != 200 {
		t.Fatalf("PUT /tables/{id} = %d", s)
	}
	do("GET", "/api/pos/v1/tables") // MISS setelah purge
	if s := do("DELETE", "/api/pos/v1/tables/M1"); s != 200 {
		t.Fatalf("DELETE /tables/{id} = %d", s)
	}
	if hits.Load() != 4 {
		t.Fatalf("upstream terpukul %d kali, ingin 4 (%v)", hits.Load(), metode)
	}
}

func TestHeaderPlatformDanVersiDiteruskan(t *testing.T) {
	gw, _ := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Tuleh-Platform") != "desktop" || r.Header.Get("X-Tuleh-Version") != "1.2.3" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte(`{"success":true}`))
	}))
	req, _ := http.NewRequest("GET", gw.URL+"/api/pos/v1/app/versi", nil)
	req.Header.Set("X-Tuleh-Platform", "desktop")
	req.Header.Set("X-Tuleh-Version", "1.2.3")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("header tidak diteruskan (status %d)", res.StatusCode)
	}
}

func TestBodyTerlaluBesarDitolak413BukanGangguan(t *testing.T) {
	gw, hits := newTestGateway(t, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"success":true}`))
	}))
	handler := withBodyLimit(8, gw.Config.Handler)
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)

	res, err := http.Post(srv.URL+"/api/pos/v1/pengeluaran", "application/json", strings.NewReader(`{"keterangan":"terlalu panjang"}`))
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusRequestEntityTooLarge || res.Header.Get(gatewayHeader) != gatewayBodyTooLarge {
		t.Fatalf("status %d penanda %q, ingin 413 body-too-large", res.StatusCode, res.Header.Get(gatewayHeader))
	}
	if hits.Load() != 0 {
		t.Fatal("body kebesaran tidak boleh diteruskan")
	}
}

func TestRuteTakDikenalBerpenanda(t *testing.T) {
	gw, _ := newTestGateway(t, http.NotFoundHandler())
	res, err := http.Get(gw.URL + "/api/pos/v1/tidak-ada")
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.Header.Get(gatewayHeader) != gatewayRouteUnknown {
		t.Fatalf("penanda = %q", res.Header.Get(gatewayHeader))
	}
}

func TestHealthzMelaporkanVersiBuild(t *testing.T) {
	lama := appVersion
	appVersion = "0.9.99"
	t.Cleanup(func() { appVersion = lama })

	gw, _ := newTestGateway(t, http.NotFoundHandler())
	res, err := http.Get(gw.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if !strings.Contains(string(body), `"version":"0.9.99"`) {
		t.Fatalf("healthz tidak melaporkan versi build: %s", body)
	}
}
