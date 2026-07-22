package main

import (
	"context"
	"sync"
	"time"
)

// Rate limiter token-bucket per kunci (IP). now disuntikkan agar mudah diuji.
type bucket struct {
	tokens   float64
	lastFill time.Time
}

type rateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket
	now     func() time.Time
}

func newRateLimiter(now func() time.Time) *rateLimiter {
	return &rateLimiter{buckets: make(map[string]*bucket), now: now}
}

// allow mengisi bucket dengan laju ratePerSec (maks burst) lalu mencoba
// mengambil satu token.
func (l *rateLimiter) allow(key string, ratePerSec, burst float64) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	b, ok := l.buckets[key]
	if !ok {
		b = &bucket{tokens: burst, lastFill: now}
		l.buckets[key] = b
	}

	elapsed := now.Sub(b.lastFill).Seconds()
	if elapsed > 0 {
		b.tokens = min(burst, b.tokens+elapsed*ratePerSec)
		b.lastFill = now
	}

	if b.tokens >= 1 {
		b.tokens--
		return true
	}
	return false
}

// janitor membuang bucket yang lama tidak dipakai agar peta tidak tumbuh terus.
func (l *rateLimiter) janitor(ctx context.Context, every time.Duration) {
	ticker := time.NewTicker(every)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			cutoff := l.now().Add(-10 * time.Minute)
			l.mu.Lock()
			for key, b := range l.buckets {
				if b.lastFill.Before(cutoff) {
					delete(l.buckets, key)
				}
			}
			l.mu.Unlock()
		}
	}
}
