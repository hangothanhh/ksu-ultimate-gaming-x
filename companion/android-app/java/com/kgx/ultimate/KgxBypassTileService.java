// SPDX-License-Identifier: GPL-3.0-or-later
package com.kgx.ultimate;

import android.os.Build;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import java.util.Map;
import java.util.concurrent.Executors;

public final class KgxBypassTileService extends TileService {
    @Override
    public void onStartListening() {
        super.onStartListening();
        Executors.newSingleThreadExecutor().execute(this::syncTile);
    }

    @Override
    public void onClick() {
        super.onClick();
        Executors.newSingleThreadExecutor().execute(() -> {
            try {
                Map<String, Object> st = JsonLite.asMap(RustBridge.call("status"));
                Map<String, Object> pw = JsonLite.asMap(st.get("power"));
                boolean sup = JsonLite.bool(pw, "bypass_supported", false);
                if (sup) {
                    boolean en = JsonLite.bool(pw, "bypass_enabled", false);
                    RustBridge.call("engine", "set", "BYPASS_CHARGING", en ? "0" : "1");
                }
            } catch (Throwable ignored) {
            }
            syncTile();
        });
    }

    private void syncTile() {
        Tile t = getQsTile();
        if (t == null) return;
        try {
            Map<String, Object> st = JsonLite.asMap(RustBridge.call("status"));
            Map<String, Object> pw = JsonLite.asMap(st.get("power"));
            boolean sup = JsonLite.bool(pw, "bypass_supported", false);
            boolean en = JsonLite.bool(pw, "bypass_enabled", false);
            boolean act = JsonLite.bool(pw, "bypass_active", false);
            long pct = JsonLite.num(pw, "battery_pct", 0L);
            if (!sup) {
                t.setState(Tile.STATE_UNAVAILABLE);
                if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Không hỗ trợ");
            } else if (act) {
                t.setState(Tile.STATE_ACTIVE);
                if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Đang Bypass " + pct + "%");
            } else if (en) {
                t.setState(Tile.STATE_ACTIVE);
                if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Bật (" + pct + "%)");
            } else {
                t.setState(Tile.STATE_INACTIVE);
                if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Tắt (" + pct + "%)");
            }
        } catch (Throwable ignored) {
            t.setState(Tile.STATE_UNAVAILABLE);
            if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("No Root");
        }
        t.updateTile();
    }
}
