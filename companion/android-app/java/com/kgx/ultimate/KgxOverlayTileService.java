package com.kgx.ultimate;

import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

public final class KgxOverlayTileService extends TileService {
    @Override
    public void onStartListening() {
        super.onStartListening();
        syncTile(KgxOverlayService.isRunning());
    }

    @Override
    public void onClick() {
        super.onClick();
        boolean next = !KgxOverlayService.isRunning();
        if (next) {
            KgxOverlayService.startOverlay(this);
        } else {
            KgxOverlayService.stopOverlay(this);
        }
        syncTile(next);
        new Handler(Looper.getMainLooper()).postDelayed(() -> syncTile(KgxOverlayService.isRunning()), 300L);
    }

    private void syncTile(boolean active) {
        Tile t = getQsTile();
        if (t == null) return;
        if (active) {
            t.setState(Tile.STATE_ACTIVE);
            if (Build.VERSION.SDK_INT >= 29) t.setSubtitle(KgxOverlayService.isRecording() ? "Đang ghi ●" : "Đang bật");
        } else {
            t.setState(Tile.STATE_INACTIVE);
            if (Build.VERSION.SDK_INT >= 29) t.setSubtitle("Tắt");
        }
        t.updateTile();
    }
}
