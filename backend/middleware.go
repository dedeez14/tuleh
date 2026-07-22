package main

import (
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net"
	"net/http"
	"time"
)

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func clientIP(r *http.Request) string {
	// Gateway lokal: percaya RemoteAddr saja, jangan header X-Forwarded-For.
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func withRecover(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				logger.Error("panic tertangkap", "path", r.URL.Path, "panic", rec)
				writeError(w, http.StatusInternalServerError, "Terjadi kesalahan internal gateway.")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func withRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Request-Id") == "" {
			var b [8]byte
			_, _ = rand.Read(b[:])
			r.Header.Set("X-Request-Id", hex.EncodeToString(b[:]))
		}
		w.Header().Set("X-Request-Id", r.Header.Get("X-Request-Id"))
		next.ServeHTTP(w, r)
	})
}

func withSecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		// Cache HTTP sisi klien dimatikan — kesegaran diatur cache gateway.
		h.Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

func withBodyLimit(maxBytes int64, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
		}
		next.ServeHTTP(w, r)
	})
}

func withRateLimit(limiter *rateLimiter, ratePerSec, burst float64, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !limiter.allow("ip:"+clientIP(r), ratePerSec, burst) {
			writeError(w, http.StatusTooManyRequests, "Terlalu banyak permintaan. Coba lagi sebentar.")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// loginRateLimit jauh lebih ketat — perlindungan brute force kredensial.
func loginRateLimit(limiter *rateLimiter, perMinute float64, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !limiter.allow("login:"+clientIP(r), perMinute/60.0, perMinute) {
			writeError(w, http.StatusTooManyRequests, "Terlalu banyak percobaan masuk. Tunggu satu menit.")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func withLogging(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		logger.Info("req",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"dur_ms", time.Since(start).Milliseconds(),
			"cache", rec.Header().Get("X-MPos-Cache"),
			"id", r.Header.Get("X-Request-Id"))
	})
}
