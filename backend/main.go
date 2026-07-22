// mpos-backend — gateway lokal antara aplikasi MPos (Electron) dan MOVERA POS API.
//
// Tujuan:
//   - Cepat  : cache TTL di memori untuk GET yang aman di-cache (produk, master,
//     config, laporan) + retry ringan, HTTP/2 ke upstream.
//   - Aman   : bind default hanya 127.0.0.1, allowlist endpoint (bukan proxy
//     terbuka), rate limiting per IP, batas ukuran body, header
//     keamanan, token tidak pernah disimpan/di-log.
//
// Konfigurasi lewat environment:
//
//	MPOS_LISTEN   alamat dengar     (default "127.0.0.1:8787")
//	MPOS_UPSTREAM base URL MOVERA   (default "https://tatreport.com")
//	MPOS_LOG      level log         ("debug" | "info", default "info")
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const (
	appName          = "mpos-backend"
	appVersion       = "0.1.0"
	shutdownTimeout  = 10 * time.Second
	cacheMaxEntries  = 2048
	rateGlobalPerSec = 20
	rateGlobalBurst  = 40
	rateLoginPerMin  = 5
)

type config struct {
	listenAddr string
	upstream   *url.URL
	logLevel   slog.Level
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func loadConfig() (config, error) {
	cfg := config{
		listenAddr: envOr("MPOS_LISTEN", "127.0.0.1:8787"),
		logLevel:   slog.LevelInfo,
	}
	if envOr("MPOS_LOG", "info") == "debug" {
		cfg.logLevel = slog.LevelDebug
	}

	raw := envOr("MPOS_UPSTREAM", "https://tatreport.com")
	u, err := url.Parse(raw)
	if err != nil {
		return cfg, fmt.Errorf("MPOS_UPSTREAM tidak valid: %w", err)
	}
	isLocal := u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1"
	if u.Scheme != "https" && !(u.Scheme == "http" && isLocal) {
		return cfg, errors.New("MPOS_UPSTREAM harus https (http hanya untuk localhost)")
	}
	u.Path, u.RawQuery, u.Fragment = "", "", ""
	cfg.upstream = u
	return cfg, nil
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Konfigurasi salah:", err)
		os.Exit(1)
	}

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.logLevel}))
	slog.SetDefault(logger)

	cache := newTTLCache(cacheMaxEntries)
	go cache.janitor(context.Background(), time.Minute)

	limiter := newRateLimiter(time.Now)
	go limiter.janitor(context.Background(), 5*time.Minute)

	proxy := newProxy(cfg.upstream, cache, logger)
	mux := buildMux(proxy, limiter)

	handler := withRecover(logger,
		withRequestID(
			withSecurityHeaders(
				withBodyLimit(1<<20,
					withRateLimit(limiter, rateGlobalPerSec, rateGlobalBurst,
						withLogging(logger, mux))))))

	srv := &http.Server{
		Addr:              cfg.listenAddr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       90 * time.Second,
	}

	go func() {
		logger.Info("gateway berjalan",
			"app", appName, "version", appVersion,
			"listen", cfg.listenAddr, "upstream", cfg.upstream.String())
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server berhenti tidak wajar", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	logger.Info("mematikan gateway…")
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("shutdown tidak mulus", "error", err)
	}
}
