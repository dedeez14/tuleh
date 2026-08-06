package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"time"
)

const (
	upstreamTimeout = 20 * time.Second
	maxUpstreamBody = 10 << 20 // 10 MB
	retryBackoff    = 200 * time.Millisecond
	userAgentHeader = appName + "/" + appVersion
)

// Header yang diteruskan ke upstream — selain ini dibuang (hop-by-hop dsb.)
// X-Tuleh-Version wajib diteruskan agar server bisa menegakkan versi minimum (426).
var forwardedHeaders = []string{"Authorization", "Content-Type", "Accept", "Accept-Language", "X-Tuleh-Version"}

type proxy struct {
	upstream *url.URL
	client   *http.Client
	cache    *ttlCache
	log      *slog.Logger
}

func newProxy(upstream *url.URL, cache *ttlCache, logger *slog.Logger) *proxy {
	return &proxy{
		upstream: upstream,
		cache:    cache,
		log:      logger,
		client: &http.Client{
			Timeout: upstreamTimeout,
			Transport: &http.Transport{
				MaxIdleConns:        20,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
				TLSHandshakeTimeout: 10 * time.Second,
				ForceAttemptHTTP2:   true,
			},
		},
	}
}

// tokenHash memisahkan cache antar pengguna tanpa pernah menyimpan token asli.
func tokenHash(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if auth == "" {
		return "anon"
	}
	sum := sha256.Sum256([]byte(auth))
	return hex.EncodeToString(sum[:8])
}

func cacheKeyPath(r *http.Request) string {
	if r.URL.RawQuery == "" {
		return r.URL.Path
	}
	return r.URL.Path + "?" + r.URL.RawQuery
}

func (p *proxy) handler(rt route) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := tokenHash(r)
		keyPath := cacheKeyPath(r)
		cacheable := rt.cache > 0 && r.Method == http.MethodGet

		if cacheable {
			if entry, ok := p.cache.get(token + "|" + keyPath); ok {
				w.Header().Set("Content-Type", entry.contentType)
				w.Header().Set("X-MPos-Cache", "HIT")
				w.WriteHeader(entry.status)
				_, _ = w.Write(entry.body)
				return
			}
		}

		status, contentType, body, err := p.forward(r)
		if err != nil {
			p.log.Warn("upstream tidak terjangkau", "path", r.URL.Path, "error", err)
			writeError(w, http.StatusBadGateway, "Server MOVERA tidak dapat dihubungi. Periksa koneksi internet.")
			return
		}

		if cacheable && status == http.StatusOK {
			p.cache.set(token+"|"+keyPath, cacheEntry{
				expiresAt:   time.Now().Add(rt.cache),
				status:      status,
				contentType: contentType,
				body:        body,
			})
		}

		// Mutasi sukses → buang cache yang kini basi (stok, laporan, dst.)
		if len(rt.purge) > 0 && status >= 200 && status < 300 {
			p.cache.purgePrefix(token, rt.purge)
		}

		w.Header().Set("Content-Type", contentType)
		if cacheable {
			w.Header().Set("X-MPos-Cache", "MISS")
		}
		w.WriteHeader(status)
		_, _ = w.Write(body)
	})
}

// forward meneruskan permintaan ke upstream. GET dicoba ulang sekali bila
// gagal jaringan / 502-504; metode lain tidak (tidak idempoten).
func (p *proxy) forward(r *http.Request) (status int, contentType string, body []byte, err error) {
	var reqBody []byte
	if r.Body != nil {
		reqBody, err = io.ReadAll(r.Body) // sudah dibatasi MaxBytesReader
		if err != nil {
			return 0, "", nil, err
		}
	}

	target := *p.upstream
	target.Path = r.URL.Path
	target.RawQuery = r.URL.RawQuery

	attempts := 1
	if r.Method == http.MethodGet {
		attempts = 2
	}

	for attempt := 1; attempt <= attempts; attempt++ {
		status, contentType, body, err = p.doOnce(r, target.String(), reqBody)
		retryable := err != nil || status == http.StatusBadGateway ||
			status == http.StatusServiceUnavailable || status == http.StatusGatewayTimeout
		if !retryable || attempt == attempts {
			return status, contentType, body, err
		}
		time.Sleep(retryBackoff)
	}
	return status, contentType, body, err
}

func (p *proxy) doOnce(orig *http.Request, targetURL string, reqBody []byte) (int, string, []byte, error) {
	req, err := http.NewRequestWithContext(orig.Context(), orig.Method, targetURL, bytes.NewReader(reqBody))
	if err != nil {
		return 0, "", nil, err
	}
	for _, name := range forwardedHeaders {
		if v := orig.Header.Get(name); v != "" {
			req.Header.Set(name, v)
		}
	}
	if req.Header.Get("Accept") == "" {
		req.Header.Set("Accept", "application/json")
	}
	req.Header.Set("User-Agent", userAgentHeader)
	if id := orig.Header.Get("X-Request-Id"); id != "" {
		req.Header.Set("X-Request-Id", id)
	}

	res, err := p.client.Do(req)
	if err != nil {
		return 0, "", nil, err
	}
	defer res.Body.Close()

	body, err := io.ReadAll(io.LimitReader(res.Body, maxUpstreamBody))
	if err != nil {
		return 0, "", nil, err
	}

	contentType := res.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/json; charset=utf-8"
	}
	return res.StatusCode, contentType, body, nil
}
