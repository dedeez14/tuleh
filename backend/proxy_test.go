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
