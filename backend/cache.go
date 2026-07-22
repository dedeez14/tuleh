package main

import (
	"context"
	"strings"
	"sync"
	"time"
)

// Cache TTL sederhana di memori, aman untuk akses bersamaan.
// Kunci disusun pemanggil sebagai "<tokenHash>|<path?query>" sehingga cache
// satu kasir tidak pernah bocor ke kasir lain.
type cacheEntry struct {
	expiresAt   time.Time
	status      int
	contentType string
	body        []byte
}

type ttlCache struct {
	mu      sync.Mutex
	entries map[string]cacheEntry
	max     int
}

func newTTLCache(max int) *ttlCache {
	return &ttlCache{entries: make(map[string]cacheEntry), max: max}
}

func (c *ttlCache) get(key string) (cacheEntry, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	entry, ok := c.entries[key]
	if !ok || time.Now().After(entry.expiresAt) {
		if ok {
			delete(c.entries, key)
		}
		return cacheEntry{}, false
	}
	return entry, true
}

func (c *ttlCache) set(key string, entry cacheEntry) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= c.max {
		c.sweepLocked()
		// Masih penuh setelah entri kedaluwarsa dibuang → reset kasar.
		// Sederhana dan cukup: cache hanyalah akselerator, bukan sumber data.
		if len(c.entries) >= c.max {
			c.entries = make(map[string]cacheEntry)
		}
	}
	c.entries[key] = entry
}

// purgePrefix menghapus semua entri milik tokenHash yang path-nya diawali
// salah satu prefix. Prefix "" berarti semua entri token tersebut.
func (c *ttlCache) purgePrefix(tokenHash string, prefixes []string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for key := range c.entries {
		rest, ok := strings.CutPrefix(key, tokenHash+"|")
		if !ok {
			continue
		}
		for _, prefix := range prefixes {
			if strings.HasPrefix(rest, prefix) {
				delete(c.entries, key)
				break
			}
		}
	}
}

func (c *ttlCache) sweepLocked() {
	now := time.Now()
	for key, entry := range c.entries {
		if now.After(entry.expiresAt) {
			delete(c.entries, key)
		}
	}
}

func (c *ttlCache) janitor(ctx context.Context, every time.Duration) {
	ticker := time.NewTicker(every)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			c.mu.Lock()
			c.sweepLocked()
			c.mu.Unlock()
		}
	}
}
