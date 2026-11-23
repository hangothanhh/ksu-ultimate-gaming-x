// SPDX-License-Identifier: GPL-3.0-or-later
package com.kgx.ultimate;

import android.os.Build;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import java.util.Map;
import java.util.concurrent.Executors;

public final class KgxModeTileService extends TileService {
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
                boolean sw = JsonLite.bool(st, "sustained_sweet_spot", false);
                boolean unl = JsonLite.bool(st, "thermal_unlock", false);
                if (!sw && !unl) {
                    RustBridge.call("engine", "set", "THERMAL_UNLOCK", "0");
                    RustBridge.call("engine", "set", "SUSTAINED_SWEET_SPOT", "1");
                } else if (sw) {
                    RustBridge.call("engine", "set", "SUSTAINED_SWEET_SPOT", "0");
                    RustBridge.call("engine", "set", "THERMAL_UNLOCK", "1");
                } else {
                    RustBridge.call("engine", "set", "SUSTAINED_SWEET_SPOT", "0");
                    RustBridge.call("engine", "set", "THERMAL_UNLOCK", "0");
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
            boolean sw = JsonLite.bool(st, "sustained_sweet_spot", false);
            boolean unl = JsonLite.bool(st, "thermal_unlock", false);
            if (sw) {
                t.setState(Tile.STATE_ACTIVE);
                if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Sweet-Spot");
            } else if (unl) {
                t.setState(Tile.STATE_ACTIVE);
                if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Max Unlock");
            } else {
                t.setState(Tile.STATE_INACTIVE);
                if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Stock Guard");
            }
        } catch (Throwable ignored) {
            t.setState(Tile.STATE_UNAVAILABLE);
            if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("No Root");
        }
        t.updateTile();
    }
}
