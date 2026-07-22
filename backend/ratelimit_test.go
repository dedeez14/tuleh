package main

import (
	"testing"
	"time"
)

func TestRateLimiterBurstThenDeny(t *testing.T) {
	// Arrange — jam bisa dikendalikan
	now := time.Unix(1000, 0)
	l := newRateLimiter(func() time.Time { return now })

	// Act + Assert — burst 3 diizinkan, permintaan ke-4 ditolak
	for i := 0; i < 3; i++ {
		if !l.allow("ip:1", 1, 3) {
			t.Fatalf("permintaan ke-%d seharusnya diizinkan", i+1)
		}
	}
	if l.allow("ip:1", 1, 3) {
		t.Fatal("melebihi burst seharusnya ditolak")
	}
}

func TestRateLimiterRefill(t *testing.T) {
	now := time.Unix(1000, 0)
	l := newRateLimiter(func() time.Time { return now })

	for i := 0; i < 3; i++ {
		l.allow("ip:1", 1, 3)
	}
	if l.allow("ip:1", 1, 3) {
		t.Fatal("bucket seharusnya kosong")
	}

	// Maju 2 detik pada laju 1 token/detik → 2 token tersedia
	now = now.Add(2 * time.Second)
	if !l.allow("ip:1", 1, 3) {
		t.Fatal("token seharusnya terisi ulang")
	}
	if !l.allow("ip:1", 1, 3) {
		t.Fatal("token kedua seharusnya tersedia")
	}
	if l.allow("ip:1", 1, 3) {
		t.Fatal("token ketiga seharusnya belum ada")
	}
}

func TestRateLimiterIsolasiKunci(t *testing.T) {
	now := time.Unix(1000, 0)
	l := newRateLimiter(func() time.Time { return now })

	for i := 0; i < 3; i++ {
		l.allow("ip:1", 1, 3)
	}
	if !l.allow("ip:2", 1, 3) {
		t.Fatal("kunci berbeda tidak boleh saling memengaruhi")
	}
}
