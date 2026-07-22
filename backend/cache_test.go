package main

import (
	"testing"
	"time"
)

func TestCacheSetGet(t *testing.T) {
	c := newTTLCache(10)
	c.set("tok|/api/pos/v1/produk", cacheEntry{
		expiresAt: time.Now().Add(time.Minute),
		status:    200,
		body:      []byte("data"),
	})

	entry, ok := c.get("tok|/api/pos/v1/produk")
	if !ok {
		t.Fatal("entri seharusnya ditemukan")
	}
	if string(entry.body) != "data" {
		t.Fatalf("body salah: %q", entry.body)
	}
}

func TestCacheExpiry(t *testing.T) {
	c := newTTLCache(10)
	c.set("tok|/x", cacheEntry{expiresAt: time.Now().Add(-time.Second)})

	if _, ok := c.get("tok|/x"); ok {
		t.Fatal("entri kedaluwarsa seharusnya tidak dikembalikan")
	}
}

func TestCachePurgePrefixPerToken(t *testing.T) {
	c := newTTLCache(10)
	future := time.Now().Add(time.Minute)
	c.set("tokA|/api/pos/v1/produk?q=a", cacheEntry{expiresAt: future})
	c.set("tokA|/api/pos/v1/laporan/stok", cacheEntry{expiresAt: future})
	c.set("tokA|/api/pos/v1/kategori", cacheEntry{expiresAt: future})
	c.set("tokB|/api/pos/v1/produk?q=a", cacheEntry{expiresAt: future})

	c.purgePrefix("tokA", []string{"/api/pos/v1/produk", "/api/pos/v1/laporan"})

	if _, ok := c.get("tokA|/api/pos/v1/produk?q=a"); ok {
		t.Error("produk tokA seharusnya terhapus")
	}
	if _, ok := c.get("tokA|/api/pos/v1/laporan/stok"); ok {
		t.Error("laporan tokA seharusnya terhapus")
	}
	if _, ok := c.get("tokA|/api/pos/v1/kategori"); !ok {
		t.Error("kategori tokA seharusnya masih ada")
	}
	if _, ok := c.get("tokB|/api/pos/v1/produk?q=a"); !ok {
		t.Error("cache token lain tidak boleh ikut terhapus")
	}
}

func TestCachePurgeAllForToken(t *testing.T) {
	c := newTTLCache(10)
	future := time.Now().Add(time.Minute)
	c.set("tokA|/a", cacheEntry{expiresAt: future})
	c.set("tokA|/b", cacheEntry{expiresAt: future})
	c.set("tokB|/a", cacheEntry{expiresAt: future})

	c.purgePrefix("tokA", []string{""}) // logout → semua milik tokA

	if _, ok := c.get("tokA|/a"); ok {
		t.Error("semua entri tokA seharusnya terhapus")
	}
	if _, ok := c.get("tokB|/a"); !ok {
		t.Error("entri tokB seharusnya selamat")
	}
}
