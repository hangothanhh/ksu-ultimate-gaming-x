package com.kgx.ultimate;

import android.util.Base64;
import java.nio.charset.StandardCharsets;

public final class RustBridge {
    private static final String MOD_DIR = "/data/adb/modules/ksu_ultimate_gaming_x";
    private static final String KGX_CORE = MOD_DIR + "/bin/kgx-core";
    private static final String KGX_CTL = MOD_DIR + "/bin/kgxctl";

    static {
        System.loadLibrary("kgx_rust");
    }

    public static native String nativeVersion();
    public static native int nativeCheckRoot();
    public static native String nativeExec(String shellCmd);
    public static native void nativeResetPipe();

    public static String shellQuote(String arg) {
        return "'" + String.valueOf(arg).replace("'", "'\\''") + "'";
    }

    public static String encodeB64(String text) {
        return Base64.encodeToString(text.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
    }

    public static boolean isFastRead(String[] args) {
        if (args.length == 0) return true;
        String c0 = args[0];
        String c1 = args.length > 1 ? args[1] : "";
        if ("status".equals(c0) && args.length == 1) return true;
        if ("engine".equals(c0) && "get".equals(c1)) return true;
        if ("profiles".equals(c0) && "list".equals(c1)) return true;
        if ("spoof".equals(c0) && "diag".equals(c1)) return true;
        if ("fps".equals(c0)) return true;
        if ("overlay-tick".equals(c0)) return true;
        return "logs".equals(c0) && !"clear".equals(c1);
    }

    public static volatile long lastIpcMs = 0L;

    public static Object call(String... args) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < args.length; i++) {
            if (i > 0) sb.append(' ');
            sb.append(shellQuote(args[i]));
        }
        String joined = sb.toString();
        String cmd;
        if (isFastRead(args)) {
            cmd = "if [ -x " + KGX_CORE + " ]; then " + KGX_CORE + " " + joined
                + "; else sh " + KGX_CTL + " " + joined + "; fi";
        } else {
            cmd = "sh " + KGX_CTL + " " + joined;
        }
        long t0 = System.nanoTime();
        String out = nativeExec(cmd);
        lastIpcMs = Math.max(1L, (System.nanoTime() - t0) / 1_000_000L);
        if (out == null || out.trim().isEmpty()) {
            return JsonLite.parse("{\"ok\":false,\"error\":\"Empty response\"}");
        }
        return JsonLite.parse(out);
    }

    public static String checkModuleState() {
        String cmd = "if [ -d " + MOD_DIR + " ]; then echo OK; else echo MISSING; fi";
        return nativeExec(cmd).trim();
    }
}
