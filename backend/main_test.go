package main

import "testing"

func TestLoadConfigWajibUpstreamTanpaNilaiBawaan(t *testing.T) {
	t.Setenv("MPOS_UPSTREAM", "")
	if _, err := loadConfig(); err == nil {
		t.Fatal("tanpa MPOS_UPSTREAM seharusnya galat (tidak ada server bawaan tertanam)")
	}

	t.Setenv("MPOS_UPSTREAM", "http://contoh.test")
	if _, err := loadConfig(); err == nil {
		t.Fatal("http non-lokal seharusnya ditolak")
	}

	t.Setenv("MPOS_UPSTREAM", "https://toko.contoh.test/jalur?x=1")
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.upstream.String() != "https://toko.contoh.test" {
		t.Fatalf("upstream = %s", cfg.upstream)
	}
}

func TestResolveVersionLdflagsLaluEnv(t *testing.T) {
	lama := appVersion
	t.Cleanup(func() { appVersion = lama })

	appVersion = ""
	t.Setenv("MPOS_VERSION", "")
	if got := resolveVersion(); got != versiTidakDikenal {
		t.Fatalf("tanpa sumber = %q", got)
	}
	t.Setenv("MPOS_VERSION", "0.9.40")
	if got := resolveVersion(); got != "0.9.40" {
		t.Fatalf("dari env = %q", got)
	}
	appVersion = "0.9.41"
	if got := resolveVersion(); got != "0.9.41" {
		t.Fatalf("ldflags harus menang = %q", got)
	}
}
