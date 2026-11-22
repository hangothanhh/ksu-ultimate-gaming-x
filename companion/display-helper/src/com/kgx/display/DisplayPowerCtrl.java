package com.kgx.display;

import android.os.IBinder;
import java.lang.reflect.Method;

public final class DisplayPowerCtrl {
    private static final int POWER_MODE_OFF = 0;
    private static final int POWER_MODE_NORMAL = 2;

    private static IBinder resolveTokenFromClass(String clsName) {
        try {
            Class<?> cls = Class.forName(clsName);
            Method mIds = cls.getMethod("getPhysicalDisplayIds");
            long[] ids = (long[]) mIds.invoke(null);
            if (ids != null && ids.length > 0) {
                Method mTok = cls.getMethod("getPhysicalDisplayToken", long.class);
                Object tok = mTok.invoke(null, ids[0]);
                if (tok instanceof IBinder) {
                    return (IBinder) tok;
                }
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    private static IBinder resolveInternalDisplayToken(Class<?> sc) {
        IBinder token = resolveTokenFromClass("com.android.server.display.DisplayControl");
        if (token != null) return token;

        try {
            Method m = sc.getMethod("getInternalDisplayToken");
            Object tok = m.invoke(null);
            if (tok instanceof IBinder) return (IBinder) tok;
        } catch (Throwable ignored) {
        }

        token = resolveTokenFromClass("android.view.SurfaceControl");
        if (token != null) return token;

        try {
            Method m = sc.getMethod("getBuiltInDisplay", int.class);
            Object tok = m.invoke(null, 0);
            if (tok instanceof IBinder) return (IBinder) tok;
        } catch (Throwable ignored) {
        }
        return null;
    }

    public static void main(String[] args) {
        String cmd = (args != null && args.length > 0) ? args[0] : "on";
        int mode;
        if ("off".equals(cmd)) {
            mode = POWER_MODE_OFF;
        } else if ("on".equals(cmd)) {
            mode = POWER_MODE_NORMAL;
        } else {
            System.err.println("ERR:usage_off_or_on");
            System.exit(1);
            return;
        }

        try {
            Class<?> sc = Class.forName("android.view.SurfaceControl");
            IBinder token = resolveInternalDisplayToken(sc);
            if (token == null) {
                System.err.println("ERR:no_internal_display_token");
                System.exit(1);
                return;
            }
            Method setMode = sc.getMethod("setDisplayPowerMode", IBinder.class, int.class);
            setMode.invoke(null, token, mode);
            System.out.println(mode == POWER_MODE_OFF ? "OK_OFF" : "OK_ON");
        } catch (Throwable t) {
            Throwable root = t.getCause() != null ? t.getCause() : t;
            System.err.println("ERR:" + root.getClass().getSimpleName() + ":" + root.getMessage());
            System.exit(1);
        }
    }
}
