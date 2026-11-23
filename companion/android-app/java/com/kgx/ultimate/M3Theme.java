// SPDX-License-Identifier: GPL-3.0-or-later
package com.kgx.ultimate;

import android.content.Context;
import android.os.Build;

public final class M3Theme {
    public final int bg = 0xFF0F0E15;
    public final int surface1 = 0xFF16151F;
    public final int surface2 = 0xFF1D1B28;
    public final int surface3 = 0xFF262436;
    public final int surface4 = 0xFF312E45;
    public final int outline = 0xFF3C3852;
    public final int outlineSoft = 0xFF2A273B;

    public final int onSurface = 0xFFECE8F8;
    public final int onSurfaceVar = 0xFFA7A1BD;

    public final int primary;
    public final int onPrimary;
    public final int primaryContainer;
    public final int onPrimaryContainer;

    public final int secondary = 0xFF80DEEA;
    public final int secondaryContainer = 0xFF14434C;
    public final int onSecondaryContainer = 0xFFB2EBF2;

    public final int ok = 0xFFA8F0C6;
    public final int okContainer = 0xFF14452F;
    public final int warn = 0xFFFFD580;
    public final int warnContainer = 0xFF4A350D;
    public final int error = 0xFFFFB4AB;
    public final int errorContainer = 0xFF690005;

    public M3Theme(Context ctx) {
        int p = 0xFFD0BCFF;
        int op = 0xFF371E73;
        int pc = 0xFF4F378B;
        int opc = 0xFFEADDFF;
        // Material You dynamic palette enhancement on Android 12+ (One UI / AOSP)
        if (Build.VERSION.SDK_INT >= 31) {
            try {
                int dynP = ctx.getColor(android.R.color.system_accent1_200);
                int dynOp = ctx.getColor(android.R.color.system_accent1_800);
                int dynPc = ctx.getColor(android.R.color.system_accent1_700);
                int dynOpc = ctx.getColor(android.R.color.system_accent1_100);
                if (dynP != 0 && dynPc != 0) {
                    p = dynP;
                    op = dynOp;
                    pc = dynPc;
                    opc = dynOpc;
                }
            } catch (Throwable ignored) {}
        }
        this.primary = p;
        this.onPrimary = op;
        this.primaryContainer = pc;
        this.onPrimaryContainer = opc;
    }
}
