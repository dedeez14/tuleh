package com.tuleh.kasir;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

// Auto-Update Tahap 4: daftarkan plugin ApkUpdater sebelum bridge dibuat.
// File ini menimpa MainActivity bawaan hasil `cap add android` (via CI).
public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(ApkUpdaterPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
