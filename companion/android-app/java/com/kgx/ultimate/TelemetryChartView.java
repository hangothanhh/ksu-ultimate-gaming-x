package com.kgx.ultimate;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Typeface;
import android.view.View;
import java.util.ArrayList;
import java.util.List;

public final class TelemetryChartView extends View {
    public static final int METRIC_FPS = 0;
    public static final int METRIC_CPU = 1;
    public static final int METRIC_GPU = 2;
    public static final int METRIC_RAM = 3;
    public static final int METRIC_TEMP = 4;
    public static final int METRIC_POWER = 5;
    public static final int METRIC_CLOCK = 6;

    private final Paint bgPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint gridPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint linePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint labelPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path linePath = new Path();

    private final List<Float> series = new ArrayList<>();
    private String unit = "FPS";
    private long spanSec = 0;
    private float minY = 0f;
    private float maxY = 120f;

    public TelemetryChartView(Context ctx) {
        super(ctx);
        float d = ctx.getResources().getDisplayMetrics().density;

        bgPaint.setColor(0xFF14161D);
        bgPaint.setStyle(Paint.Style.FILL);

        borderPaint.setColor(0xFF282C38);
        borderPaint.setStyle(Paint.Style.STROKE);
        borderPaint.setStrokeWidth(1f * d);

        gridPaint.setColor(0x22FFFFFF);
        gridPaint.setStyle(Paint.Style.STROKE);
        gridPaint.setStrokeWidth(1f);

        linePaint.setColor(0xFFE2E8F0);
        linePaint.setStyle(Paint.Style.STROKE);
        linePaint.setStrokeWidth(1.6f * d);
        linePaint.setStrokeCap(Paint.Cap.ROUND);
        linePaint.setStrokeJoin(Paint.Join.ROUND);

        labelPaint.setColor(0xFF9AA4B2);
        labelPaint.setTextSize(10f * ctx.getResources().getDisplayMetrics().scaledDensity);
        labelPaint.setTypeface(Typeface.MONOSPACE);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int w = MeasureSpec.getSize(widthMeasureSpec);
        int desiredH = Math.round(170f * getResources().getDisplayMetrics().density);
        int h = resolveSize(desiredH, heightMeasureSpec);
        setMeasuredDimension(w, h);
    }

    public void setData(List<SessionRecorder.Sample> samples, int metric) {
        series.clear();
        spanSec = 0;
        if (samples == null || samples.isEmpty()) {
            unit = metricUnit(metric);
            minY = 0f;
            maxY = metric == METRIC_FPS ? 120f : 100f;
            invalidate();
            return;
        }
        spanSec = Math.max(1L, samples.get(samples.size() - 1).ts - samples.get(0).ts);
        unit = metricUnit(metric);

        float hi = 0f;
        float lo = Float.MAX_VALUE;
        for (SessionRecorder.Sample s : samples) {
            float v;
            switch (metric) {
                case METRIC_CPU:
                    v = s.cpuPct;
                    break;
                case METRIC_GPU:
                    v = s.gpuPct;
                    break;
                case METRIC_RAM:
                    v = s.ramPct;
                    break;
                case METRIC_TEMP:
                    v = Math.max(s.cpuC, s.gpuC);
                    break;
                case METRIC_POWER:
                    v = s.powerMw / 1000f;
                    break;
                case METRIC_CLOCK:
                    v = s.cpuMhz;
                    break;
                default:
                    v = s.fps > 0 ? s.fps : 0f;
                    break;
            }
            series.add(v);
            if (v > hi) hi = v;
            if (v < lo) lo = v;
        }
        if (metric == METRIC_CPU || metric == METRIC_GPU || metric == METRIC_RAM) {
            minY = 0f;
            maxY = 100f;
        } else if (metric == METRIC_POWER) {
            minY = 0f;
            maxY = Math.max(6f, (float) Math.ceil(hi * 1.15f));
        } else if (metric == METRIC_CLOCK) {
            minY = 0f;
            maxY = Math.max(1000f, (float) Math.ceil(hi * 1.15f / 200f) * 200f);
        } else {
            minY = 0f;
            maxY = Math.max(metric == METRIC_FPS ? 60f : 40f, (float) Math.ceil(hi * 1.15f / 10f) * 10f);
        }
        invalidate();
    }

    private static String metricUnit(int m) {
        switch (m) {
            case METRIC_CPU:
            case METRIC_GPU:
            case METRIC_RAM:
                return "%";
            case METRIC_TEMP:
                return "°C";
            case METRIC_POWER:
                return "W";
            case METRIC_CLOCK:
                return "MHz";
            default:
                return "FPS";
        }
    }

    @Override
    protected void onDraw(Canvas c) {
        super.onDraw(c);
        float d = getResources().getDisplayMetrics().density;
        float w = getWidth();
        float h = getHeight();
        float r = 10f * d;

        c.drawRoundRect(0, 0, w, h, r, r, bgPaint);
        c.drawRoundRect(1f, 1f, w - 1f, h - 1f, r, r, borderPaint);

        float padL = 38f * d;
        float padR = 12f * d;
        float padT = 14f * d;
        float padB = 22f * d;
        float pw = Math.max(1f, w - padL - padR);
        float ph = Math.max(1f, h - padT - padB);

        // 4 subtle horizontal guide lines
        for (int i = 0; i <= 3; i++) {
            float frac = i / 3f;
            float y = padT + ph * frac;
            c.drawLine(padL, y, w - padR, y, gridPaint);
            int val = Math.round(maxY - (maxY - minY) * frac);
            c.drawText(String.valueOf(val), 6f * d, y + 3.5f * d, labelPaint);
        }

        // Axis span labels
        c.drawText("0s", padL, h - 6f * d, labelPaint);
        String endLbl = spanSec + "s (" + unit + ")";
        float tw = labelPaint.measureText(endLbl);
        c.drawText(endLbl, w - padR - tw, h - 6f * d, labelPaint);

        if (series.isEmpty()) {
            String empty = "Không có mẫu dữ liệu";
            c.drawText(empty, padL + pw * 0.28f, padT + ph * 0.55f, labelPaint);
            return;
        }

        linePath.reset();
        float range = Math.max(1f, maxY - minY);
        int n = series.size();
        for (int i = 0; i < n; i++) {
            float x = n == 1 ? (padL + pw * 0.5f) : (padL + (pw * i) / (n - 1));
            float norm = (series.get(i) - minY) / range;
            if (norm < 0f) norm = 0f;
            if (norm > 1f) norm = 1f;
            float y = padT + ph * (1f - norm);
            if (i == 0) linePath.moveTo(x, y);
            else linePath.lineTo(x, y);
        }
        c.drawPath(linePath, linePaint);
    }
}
