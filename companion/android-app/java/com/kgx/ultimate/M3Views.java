// SPDX-License-Identifier: GPL-3.0-or-later
package com.kgx.ultimate;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.Switch;
import android.widget.TextView;

public final class M3Views {
    private M3Views() {}

    public static int dp(Context c, int v) {
        return Math.round(c.getResources().getDisplayMetrics().density * v);
    }

    public static GradientDrawable roundRect(int fill, int strokeColor, int strokePx, int radiusPx) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(fill);
        if (strokePx > 0 && strokeColor != 0) {
            d.setStroke(strokePx, strokeColor);
        }
        d.setCornerRadius(radiusPx);
        return d;
    }

    public static RippleDrawable ripplePill(int fill, int rippleColor, int radiusPx) {
        GradientDrawable content = roundRect(fill, 0, 0, radiusPx);
        GradientDrawable mask = roundRect(0xFFFFFFFF, 0, 0, radiusPx);
        return new RippleDrawable(ColorStateList.valueOf(rippleColor), content, mask);
    }

    public static LinearLayout card(Context c, M3Theme t, boolean hero) {
        LinearLayout box = new LinearLayout(c);
        box.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(c, 16);
        box.setPadding(pad, pad, pad, pad);
        box.setBackground(roundRect(
            hero ? t.surface3 : t.surface2,
            hero ? t.outline : t.outlineSoft,
            dp(c, 1),
            dp(c, 24)
        ));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(c, 12);
        box.setLayoutParams(lp);
        return box;
    }

    public static TextView title(Context c, M3Theme t, String text, int sp) {
        TextView tv = new TextView(c);
        tv.setText(text);
        tv.setTextSize(sp);
        tv.setTypeface(Typeface.DEFAULT_BOLD);
        tv.setTextColor(t.onSurface);
        return tv;
    }

    public static TextView subtitle(Context c, M3Theme t, String text) {
        TextView tv = new TextView(c);
        tv.setText(text);
        tv.setTextSize(12);
        tv.setTextColor(t.onSurfaceVar);
        return tv;
    }

    public static TextView pill(Context c, String text, int bg, int fg) {
        TextView tv = new TextView(c);
        tv.setText(text);
        tv.setTextSize(11);
        tv.setTypeface(Typeface.DEFAULT_BOLD);
        tv.setTextColor(fg);
        tv.setPadding(dp(c, 10), dp(c, 4), dp(c, 10), dp(c, 4));
        tv.setBackground(roundRect(bg, 0, 0, dp(c, 999)));
        tv.setSingleLine(true);
        return tv;
    }

    public static TextView button(Context c, M3Theme t, String label, int bg, int fg, boolean compact, View.OnClickListener onClick) {
        TextView btn = new TextView(c);
        btn.setText(label);
        btn.setTextSize(compact ? 11.5f : 12.5f);
        btn.setTypeface(Typeface.DEFAULT_BOLD);
        btn.setTextColor(fg);
        btn.setGravity(Gravity.CENTER);
        btn.setPadding(dp(c, compact ? 12 : 16), dp(c, compact ? 7 : 10), dp(c, compact ? 12 : 16), dp(c, compact ? 7 : 10));
        btn.setBackground(ripplePill(bg, 0x33FFFFFF, dp(c, 999)));
        btn.setClickable(true);
        btn.setFocusable(true);
        if (onClick != null) btn.setOnClickListener(onClick);
        return btn;
    }

    public static LinearLayout cardHeader(Context c, M3Theme t, String titleText, String subText, TextView rightBadge) {
        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout left = new LinearLayout(c);
        left.setOrientation(LinearLayout.VERTICAL);
        left.addView(title(c, t, titleText, 15));
        if (subText != null && !subText.isEmpty()) {
            left.addView(subtitle(c, t, subText));
        }
        row.addView(left, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        if (rightBadge != null) {
            row.addView(rightBadge);
        }
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(c, 8);
        row.setLayoutParams(lp);
        return row;
    }

    public static LinearLayout kvRow(Context c, M3Theme t, String k, String v, boolean mono) {
        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(0, dp(c, 5), 0, dp(c, 5));
        TextView tk = new TextView(c);
        tk.setText(k);
        tk.setTextSize(12);
        tk.setTextColor(t.onSurfaceVar);
        TextView tv = new TextView(c);
        tv.setText(v);
        tv.setTextSize(12);
        tv.setTypeface(mono ? Typeface.MONOSPACE : Typeface.DEFAULT_BOLD);
        tv.setTextColor(t.onSurface);
        tv.setGravity(Gravity.END);
        tv.setMaxLines(2);
        tv.setEllipsize(TextUtils.TruncateAt.END);
        row.addView(tk, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 0.9f));
        row.addView(tv, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.3f));
        return row;
    }

    public interface OnToggle {
        void onChanged(boolean checked);
    }

    public static LinearLayout switchRow(Context c, M3Theme t, String titleText, String descText, boolean checked, OnToggle cb) {
        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(c, 7), 0, dp(c, 7));

        LinearLayout left = new LinearLayout(c);
        left.setOrientation(LinearLayout.VERTICAL);
        TextView tt = title(c, t, titleText, 13);
        left.addView(tt);
        if (descText != null && !descText.isEmpty()) {
            TextView td = subtitle(c, t, descText);
            td.setTextSize(11);
            left.addView(td);
        }

        Switch sw = new Switch(c);
        sw.setChecked(checked);
        sw.setThumbTintList(new ColorStateList(
            new int[][]{new int[]{android.R.attr.state_checked}, new int[]{}},
            new int[]{t.onPrimary, t.onSurfaceVar}
        ));
        sw.setTrackTintList(new ColorStateList(
            new int[][]{new int[]{android.R.attr.state_checked}, new int[]{}},
            new int[]{t.primary, t.surface4}
        ));
        sw.setOnCheckedChangeListener((btn, isChecked) -> {
            if (cb != null) cb.onChanged(isChecked);
        });

        row.addView(left, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        row.addView(sw);
        return row;
    }

    public static View progressBar(Context c, M3Theme t, int pct, int fillColor) {
        int clamped = Math.max(0, Math.min(100, pct));
        LinearLayout track = new LinearLayout(c);
        track.setOrientation(LinearLayout.HORIZONTAL);
        track.setBackground(roundRect(t.surface4, 0, 0, dp(c, 999)));
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(c, 7));
        tlp.topMargin = dp(c, 4);
        tlp.bottomMargin = dp(c, 6);
        track.setLayoutParams(tlp);

        View fill = new View(c);
        fill.setBackground(roundRect(fillColor, 0, 0, dp(c, 999)));
        int wFill = Math.max(clamped, 3);
        track.addView(fill, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, wFill));
        View rest = new View(c);
        track.addView(rest, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, Math.max(0, 100 - wFill)));
        return track;
    }

    public static LinearLayout metricTile(Context c, M3Theme t, String label, String value, String sub, int accent, int tileBg) {
        LinearLayout box = new LinearLayout(c);
        box.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(c, 12);
        box.setPadding(pad, pad, pad, pad);
        box.setBackground(roundRect(tileBg, t.outlineSoft, dp(c, 1), dp(c, 18)));

        TextView lb = new TextView(c);
        lb.setText(label);
        lb.setTextSize(11);
        lb.setTextColor(t.onSurfaceVar);
        box.addView(lb);

        TextView val = new TextView(c);
        val.setText(value);
        val.setTextSize(18);
        val.setTypeface(Typeface.DEFAULT_BOLD);
        val.setTextColor(accent);
        val.setPadding(0, dp(c, 2), 0, dp(c, 2));
        box.addView(val);

        if (sub != null && !sub.isEmpty()) {
            TextView sb = new TextView(c);
            sb.setText(sub);
            sb.setTextSize(10.5f);
            sb.setTextColor(t.onSurfaceVar);
            box.addView(sb);
        }
        return box;
    }

    public static void updateProgressBar(View bar, int pct, int fillColor) {
        if (!(bar instanceof LinearLayout)) return;
        LinearLayout track = (LinearLayout) bar;
        if (track.getChildCount() < 1) return;
        int wFill = Math.max(3, Math.max(0, Math.min(100, pct)));
        View fill = track.getChildAt(0);
        fill.setBackground(roundRect(fillColor, 0, 0, dp(track.getContext(), 999)));
        LinearLayout.LayoutParams flp = (LinearLayout.LayoutParams) fill.getLayoutParams();
        flp.weight = wFill;
        fill.setLayoutParams(flp);
        if (track.getChildCount() >= 2) {
            View rest = track.getChildAt(1);
            LinearLayout.LayoutParams rlp = (LinearLayout.LayoutParams) rest.getLayoutParams();
            rlp.weight = Math.max(0, 100 - wFill);
            rest.setLayoutParams(rlp);
        }
    }

    public static void setKvValue(LinearLayout row, String val) {
        if (row != null && row.getChildCount() >= 2 && row.getChildAt(1) instanceof TextView) {
            ((TextView) row.getChildAt(1)).setText(val);
        }
    }

    public static void setTileTexts(LinearLayout tile, String value, String sub, int accent) {
        if (tile == null) return;
        if (tile.getChildCount() >= 2 && tile.getChildAt(1) instanceof TextView) {
            TextView valTv = (TextView) tile.getChildAt(1);
            valTv.setText(value);
            valTv.setTextColor(accent);
        }
        if (tile.getChildCount() >= 3 && tile.getChildAt(2) instanceof TextView && sub != null) {
            ((TextView) tile.getChildAt(2)).setText(sub);
        }
    }

    public static void setSwitchChecked(LinearLayout row, boolean checked) {
        if (row != null && row.getChildCount() >= 2 && row.getChildAt(1) instanceof Switch) {
            Switch sw = (Switch) row.getChildAt(1);
            if (sw.isChecked() != checked) {
                sw.setChecked(checked);
            }
        }
    }
}
