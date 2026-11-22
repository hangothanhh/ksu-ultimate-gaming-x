package com.kgx.ultimate;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.Icon;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.Settings;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.AbsoluteSizeSpan;
import android.text.style.ForegroundColorSpan;
import android.text.style.StyleSpan;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public final class KgxOverlayService extends Service {
    public static final String ACTION_START = "com.kgx.ultimate.OVERLAY_START";
    public static final String ACTION_STOP = "com.kgx.ultimate.OVERLAY_STOP";
    public static final String ACTION_TOGGLE_REC = "com.kgx.ultimate.OVERLAY_TOGGLE_REC";
    public static final String ACTION_TOGGLE_LOCK = "com.kgx.ultimate.OVERLAY_TOGGLE_LOCK";
    public static final String ACTION_RELOAD_PREFS = "com.kgx.ultimate.OVERLAY_RELOAD_PREFS";

    private static final String CHANNEL_ID = "kgx_overlay_channel";
    private static final int NOTIF_ID = 3301;
    public static final String PREF_NAME = "kgx_overlay_prefs";

    private static final ExecutorService PERM_EXEC = Executors.newSingleThreadExecutor();
    private static final AtomicBoolean RUNNING = new AtomicBoolean(false);
    private static final AtomicBoolean RECORDING = new AtomicBoolean(false);
    private static final AtomicBoolean CLICK_THROUGH = new AtomicBoolean(false);
    private static volatile long recStartEpoch = 0L;
    private static volatile Runnable stateListener = null;

    private WindowManager wm;
    private WindowManager.LayoutParams wmParams;
    private GradientDrawable rootBg;
    private LinearLayout rootView;
    private LinearLayout bodyBox;
    private TextView headerTv;
    private TextView rowsTv;
    private TextView recBtn;
    private TextView closeBtn;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private HandlerThread pollThread;
    private Handler pollHandler;
    private volatile boolean pollActive = false;
    private volatile boolean compactMode = false;
    private volatile boolean showLow1 = true;
    private volatile boolean showCpu = true;
    private volatile boolean showGpu = true;
    private volatile boolean showClock = true;
    private volatile boolean showRam = true;
    private volatile boolean showPower = true;
    private volatile long pollIntervalMs = 1000L;
    private volatile int bgAlpha = 190;
    private volatile long lastVibeMs = 0L;
    private volatile String lastPkg = "";
    private volatile SessionRecorder.Sample lastSample = new SessionRecorder.Sample();

    private SessionRecorder recorder;
    private DisplayManager displayMgr;
    private final DisplayManager.DisplayListener displayListener = new DisplayManager.DisplayListener() {
        @Override public void onDisplayAdded(int displayId) { syncExtDisplayAsync(); }
        @Override public void onDisplayRemoved(int displayId) { syncExtDisplayAsync(); }
        @Override public void onDisplayChanged(int displayId) {}
    };

    public static boolean isRunning() {
        return RUNNING.get();
    }

    public static boolean isRecording() {
        return RECORDING.get();
    }

    public static boolean isClickThrough(Context ctx) {
        if (RUNNING.get()) {
            return CLICK_THROUGH.get();
        }
        return ctx.getSharedPreferences(PREF_NAME, MODE_PRIVATE).getBoolean("click_through", false);
    }

    public static void toggleClickThrough(Context ctx) {
        Context app = ctx.getApplicationContext();
        SharedPreferences sp = app.getSharedPreferences(PREF_NAME, MODE_PRIVATE);
        boolean next = !isClickThrough(app);
        sp.edit().putBoolean("click_through", next).apply();
        CLICK_THROUGH.set(next);
        if (RUNNING.get()) {
            Intent i = new Intent(app, KgxOverlayService.class);
            i.setAction(ACTION_TOGGLE_LOCK);
            app.startService(i);
        } else {
            notifyListener();
        }
    }

    public static void reloadPrefs(Context ctx) {
        if (!RUNNING.get()) return;
        Context app = ctx.getApplicationContext();
        Intent i = new Intent(app, KgxOverlayService.class);
        i.setAction(ACTION_RELOAD_PREFS);
        app.startService(i);
    }

    public static long getRecDurationSec() {
        if (!RECORDING.get() || recStartEpoch <= 0L) return 0L;
        return Math.max(0L, (System.currentTimeMillis() / 1000L) - recStartEpoch);
    }

    public static void setStateListener(Runnable r) {
        stateListener = r;
    }

    private static void notifyListener() {
        Runnable r = stateListener;
        if (r != null) {
            new Handler(Looper.getMainLooper()).post(r);
        }
    }

    private static void runWithOverlayPermission(Context ctx, Runnable onGranted) {
        Context app = ctx.getApplicationContext();
        if (Settings.canDrawOverlays(app)) {
            onGranted.run();
            return;
        }
        PERM_EXEC.execute(() -> {
            try {
                RustBridge.nativeExec("appops set " + app.getPackageName() + " SYSTEM_ALERT_WINDOW allow");
            } catch (Throwable ignored) {
            }
            new Handler(Looper.getMainLooper()).post(() -> {
                if (Settings.canDrawOverlays(app)) {
                    onGranted.run();
                } else {
                    Toast.makeText(app, "Hãy cấp quyền Hiển thị trên ứng dụng khác", Toast.LENGTH_SHORT).show();
                    try {
                        Intent perm = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:" + app.getPackageName()));
                        perm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        app.startActivity(perm);
                    } catch (Throwable ignored) {
                    }
                }
            });
        });
    }

    public static void startOverlay(Context ctx) {
        Context app = ctx.getApplicationContext();
        runWithOverlayPermission(app, () -> {
            Intent i = new Intent(app, KgxOverlayService.class);
            i.setAction(ACTION_START);
            if (Build.VERSION.SDK_INT >= 26) {
                app.startForegroundService(i);
            } else {
                app.startService(i);
            }
        });
    }

    public static void stopOverlay(Context ctx) {
        Context app = ctx.getApplicationContext();
        Intent i = new Intent(app, KgxOverlayService.class);
        i.setAction(ACTION_STOP);
        app.startService(i);
    }

    public static void toggleRecord(Context ctx) {
        Context app = ctx.getApplicationContext();
        runWithOverlayPermission(app, () -> {
            Intent i = new Intent(app, KgxOverlayService.class);
            i.setAction(ACTION_TOGGLE_REC);
            if (Build.VERSION.SDK_INT >= 26) {
                app.startForegroundService(i);
            } else {
                app.startService(i);
            }
        });
    }

    private void syncExtDisplayAsync() {
        if (pollHandler == null) return;
        pollHandler.post(() -> {
            try {
                RustBridge.call("display", "ext-sync");
            } catch (Throwable ignored) {
            }
        });
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        ensureNotificationChannel();
        Notification n = buildNotification();
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIF_ID, n);
        }

        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "Thiếu quyền Overlay", Toast.LENGTH_SHORT).show();
            stopSelf();
            return;
        }

        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        loadOverlayPrefs();
        buildOverlayWindow();

        pollThread = new HandlerThread("KgxOverlayPoller");
        pollThread.start();
        pollHandler = new Handler(pollThread.getLooper());
        pollActive = true;
        pollHandler.post(pollTick);

        displayMgr = (DisplayManager) getSystemService(DISPLAY_SERVICE);
        if (displayMgr != null) {
            displayMgr.registerDisplayListener(displayListener, ui);
        }

        RUNNING.set(true);
        notifyListener();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : ACTION_START;
        if (ACTION_STOP.equals(action)) {
            stopRecordingInternal();
            stopSelf();
            return START_NOT_STICKY;
        }
        if (ACTION_TOGGLE_REC.equals(action)) {
            toggleRecordingInternal("game");
        } else if (ACTION_TOGGLE_LOCK.equals(action)) {
            if (intent != null && intent.getBooleanExtra("from_notif", false)) {
                boolean next = !CLICK_THROUGH.get();
                CLICK_THROUGH.set(next);
                getSharedPreferences(PREF_NAME, MODE_PRIVATE).edit().putBoolean("click_through", next).apply();
            } else {
                loadOverlayPrefs();
            }
            applyOverlayWindowFlags();
            updateNotif();
            notifyListener();
        } else if (ACTION_RELOAD_PREFS.equals(action)) {
            loadOverlayPrefs();
            applyOverlayWindowFlags();
            renderOverlayText(lastSample);
            notifyListener();
        }
        return START_STICKY;
    }

    private void loadOverlayPrefs() {
        SharedPreferences sp = getSharedPreferences(PREF_NAME, MODE_PRIVATE);
        showLow1 = sp.getBoolean("show_low1", true);
        showCpu = sp.getBoolean("show_cpu", true);
        showGpu = sp.getBoolean("show_gpu", true);
        showClock = sp.getBoolean("show_clock", true);
        showRam = sp.getBoolean("show_ram", true);
        showPower = sp.getBoolean("show_power", true);
        long p = sp.getLong("poll_ms", 1000L);
        if (p != 500L && p != 1000L && p != 2000L) p = 1000L;
        pollIntervalMs = p;
        int a = sp.getInt("bg_alpha", 190);
        if (a < 100 || a > 255) a = 190;
        bgAlpha = a;
        boolean ct = sp.getBoolean("click_through", false);
        CLICK_THROUGH.set(ct);
        if (rootBg != null) {
            rootBg.setColor((bgAlpha << 24) | 0x0D1016);
        }
    }

    private void applyOverlayWindowFlags() {
        if (wmParams == null || wm == null || rootView == null) return;
        int base = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
        boolean locked = CLICK_THROUGH.get();
        if (locked) {
            base |= WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE;
        }
        wmParams.flags = base;
        try {
            wm.updateViewLayout(rootView, wmParams);
        } catch (Throwable ignored) {
        }
        if (recBtn != null) recBtn.setVisibility(locked ? View.GONE : View.VISIBLE);
        if (closeBtn != null) closeBtn.setVisibility(locked ? View.GONE : View.VISIBLE);
    }

    @Override
    public void onDestroy() {
        pollActive = false;
        stopRecordingInternal();
        if (displayMgr != null) {
            try {
                displayMgr.unregisterDisplayListener(displayListener);
            } catch (Throwable ignored) {
            }
        }
        if (pollThread != null) {
            pollThread.quitSafely();
        }
        if (wm != null && rootView != null) {
            try {
                wm.removeViewImmediate(rootView);
            } catch (Throwable ignored) {
            }
            rootView = null;
        }
        RUNNING.set(false);
        RECORDING.set(false);
        recStartEpoch = 0L;
        notifyListener();
        super.onDestroy();
    }

    private void ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null && nm.getNotificationChannel(CHANNEL_ID) == null) {
                NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID, "KGX FPS Overlay", NotificationManager.IMPORTANCE_LOW);
                ch.setSound(null, null);
                ch.enableVibration(false);
                ch.setShowBadge(false);
                nm.createNotificationChannel(ch);
            }
        }
    }

    private Notification buildNotification() {
        Intent launch = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(
            this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Intent lockIntent = new Intent(this, KgxOverlayService.class);
        lockIntent.setAction(ACTION_TOGGLE_LOCK);
        lockIntent.putExtra("from_notif", true);
        PendingIntent lockPi = PendingIntent.getService(
            this, 1, lockIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Intent stopIntent = new Intent(this, KgxOverlayService.class);
        stopIntent.setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(
            this, 2, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        boolean locked = CLICK_THROUGH.get();
        Notification.Builder b = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(this, CHANNEL_ID)
            : new Notification.Builder(this);
        b.setSmallIcon(R.drawable.ic_qs_overlay)
            .setContentTitle(locked ? "KGX FPS Popup (Đang khóa xuyên chạm)" : "KGX FPS Popup")
            .setContentText(RECORDING.get() ? "Đang ghi dữ liệu FPS/CPU/GPU/RAM/W..." : "Popup Scene tối giản đang bật")
            .setContentIntent(pi)
            .addAction(new Notification.Action.Builder(
                Icon.createWithResource(this, R.drawable.ic_qs_overlay),
                locked ? "Mở khóa chạm" : "Khóa xuyên chạm", lockPi).build())
            .addAction(new Notification.Action.Builder(
                Icon.createWithResource(this, R.drawable.ic_qs_overlay),
                "Tắt Popup", stopPi).build())
            .setOngoing(true);
        return b.build();
    }

    private int dp(int v) {
        return Math.round(getResources().getDisplayMetrics().density * v);
    }

    private void buildOverlayWindow() {
        rootBg = new GradientDrawable();
        rootBg.setColor((bgAlpha << 24) | 0x0D1016);
        rootBg.setStroke(1, 0x2AFFFFFF);
        rootBg.setCornerRadius(dp(8));

        rootView = new LinearLayout(this);
        rootView.setOrientation(LinearLayout.VERTICAL);
        rootView.setBackground(rootBg);
        rootView.setPadding(dp(8), dp(6), dp(8), dp(6));

        // Top Scene header row: [FPS + 1% Low] ... [Rec] [Close]
        LinearLayout topRow = new LinearLayout(this);
        topRow.setOrientation(LinearLayout.HORIZONTAL);
        topRow.setGravity(Gravity.CENTER_VERTICAL);

        headerTv = new TextView(this);
        headerTv.setTypeface(Typeface.MONOSPACE);
        headerTv.setTextColor(0xFFF2F5F9);
        headerTv.setSingleLine(true);
        headerTv.setText("-- FPS");
        LinearLayout.LayoutParams hlp = new LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        hlp.rightMargin = dp(8);
        topRow.addView(headerTv, hlp);

        recBtn = new TextView(this);
        recBtn.setTypeface(Typeface.MONOSPACE);
        recBtn.setTextSize(10f);
        recBtn.setTextColor(0xFF9AA4B2);
        recBtn.setText("●");
        recBtn.setPadding(dp(4), 0, dp(4), 0);
        recBtn.setOnClickListener(v -> toggleRecordingInternal("overlay"));
        topRow.addView(recBtn);

        closeBtn = new TextView(this);
        closeBtn.setTypeface(Typeface.DEFAULT_BOLD);
        closeBtn.setTextSize(11f);
        closeBtn.setTextColor(0xFF9AA4B2);
        closeBtn.setText("×");
        closeBtn.setPadding(dp(4), 0, 0, 0);
        closeBtn.setOnClickListener(v -> {
            stopRecordingInternal();
            stopSelf();
        });
        topRow.addView(closeBtn);
        rootView.addView(topRow);

        // Scene-style stacked tabular telemetry rows (hidden cleanly in ultra-slim 1-line mode)
        bodyBox = new LinearLayout(this);
        bodyBox.setOrientation(LinearLayout.VERTICAL);
        bodyBox.setPadding(0, dp(3), 0, 0);

        rowsTv = new TextView(this);
        rowsTv.setTypeface(Typeface.MONOSPACE);
        rowsTv.setTextSize(10f);
        rowsTv.setLineSpacing(dp(1), 1.0f);
        rowsTv.setTextColor(0xFFF2F5F9);
        rowsTv.setText("CPU  --%   --°C\nGPU  --%   --°C\nRAM  --%   --G");
        bodyBox.addView(rowsTv);
        rootView.addView(bodyBox);

        SharedPreferences sp = getSharedPreferences(PREF_NAME, MODE_PRIVATE);
        int type = Build.VERSION.SDK_INT >= 26
            ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            : WindowManager.LayoutParams.TYPE_PHONE;
        int flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
        if (CLICK_THROUGH.get()) {
            flags |= WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE;
        }
        wmParams = new WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            flags,
            PixelFormat.TRANSLUCENT
        );
        wmParams.gravity = Gravity.TOP | Gravity.START;
        wmParams.x = sp.getInt("x", dp(12));
        wmParams.y = sp.getInt("y", dp(44));

        final int touchSlop = ViewConfiguration.get(this).getScaledTouchSlop();
        View.OnTouchListener dragOrToggle = new View.OnTouchListener() {
            float rawX0, rawY0;
            int winX0, winY0;
            boolean dragging = false;

            @Override
            public boolean onTouch(View v, MotionEvent ev) {
                switch (ev.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        rawX0 = ev.getRawX();
                        rawY0 = ev.getRawY();
                        winX0 = wmParams.x;
                        winY0 = wmParams.y;
                        dragging = false;
                        return true;
                    case MotionEvent.ACTION_MOVE:
                        float dx = ev.getRawX() - rawX0;
                        float dy = ev.getRawY() - rawY0;
                        if (Math.abs(dx) > touchSlop || Math.abs(dy) > touchSlop) {
                            dragging = true;
                        }
                        if (dragging && wm != null && rootView != null) {
                            wmParams.x = Math.round(winX0 + dx);
                            wmParams.y = Math.round(winY0 + dy);
                            wm.updateViewLayout(rootView, wmParams);
                        }
                        return true;
                    case MotionEvent.ACTION_UP:
                        if (dragging) {
                            sp.edit().putInt("x", wmParams.x).putInt("y", wmParams.y).apply();
                        } else {
                            compactMode = !compactMode;
                            bodyBox.setVisibility(compactMode ? View.GONE : View.VISIBLE);
                            renderOverlayText(lastSample);
                        }
                        return true;
                }
                return false;
            }
        };
        headerTv.setOnTouchListener(dragOrToggle);
        rowsTv.setOnTouchListener(dragOrToggle);

        wm.addView(rootView, wmParams);
        if (CLICK_THROUGH.get()) {
            if (recBtn != null) recBtn.setVisibility(View.GONE);
            if (closeBtn != null) closeBtn.setVisibility(View.GONE);
        }
    }

    private synchronized void toggleRecordingInternal(String pkgHint) {
        if (RECORDING.get()) {
            stopRecordingInternal();
            ui.post(() -> Toast.makeText(this, "Đã lưu log phiên vào app", Toast.LENGTH_SHORT).show());
        } else {
            String chosenPkg = (lastPkg != null && !lastPkg.isEmpty()) ? lastPkg : pkgHint;
            recorder = new SessionRecorder(this, chosenPkg);
            recStartEpoch = System.currentTimeMillis() / 1000L;
            RECORDING.set(true);
            updateRecButtonUi();
            updateNotif();
            notifyListener();
        }
    }

    private synchronized void stopRecordingInternal() {
        if (recorder != null) {
            recorder.stop();
            recorder = null;
        }
        RECORDING.set(false);
        recStartEpoch = 0L;
        ui.post(() -> {
            updateRecButtonUi();
            updateNotif();
        });
        notifyListener();
    }

    private void updateNotif() {
        if (!RUNNING.get()) return;
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) {
            nm.notify(NOTIF_ID, buildNotification());
        }
    }

    private void updateRecButtonUi() {
        if (recBtn == null) return;
        if (RECORDING.get()) {
            long sec = getRecDurationSec();
            recBtn.setText(String.format(Locale.US, "■ %02d:%02d", sec / 60, sec % 60));
            recBtn.setTextColor(0xFFE57373);
        } else {
            recBtn.setText("●");
            recBtn.setTextColor(0xFF9AA4B2);
        }
    }

    private final Runnable pollTick = new Runnable() {
        @Override
        public void run() {
            if (!pollActive) return;
            try {
                Map<String, Object> m = JsonLite.asMap(RustBridge.call("overlay-tick"));
                SessionRecorder.Sample s = parseSample(m);
                String pkg = JsonLite.str(m, "pkg", "");
                if (!pkg.isEmpty() && !"com.kgx.ultimate".equals(pkg)) {
                    lastPkg = pkg;
                }
                lastSample = s;
                synchronized (KgxOverlayService.this) {
                    if (RECORDING.get() && recorder != null) {
                        recorder.updatePkgIfGeneric(pkg);
                        recorder.record(s);
                    }
                }
                ui.post(() -> {
                    renderOverlayText(s);
                    maybePulseThermalAlert(s);
                });
            } catch (Throwable ignored) {
            }
            if (pollActive && pollHandler != null) {
                pollHandler.postDelayed(this, pollIntervalMs);
            }
        }
    };

    private void maybePulseThermalAlert(SessionRecorder.Sample s) {
        if (s == null || !s.thermalAlert) return;
        long nowMs = System.currentTimeMillis();
        if (nowMs - lastVibeMs < 60_000L) return;
        lastVibeMs = nowMs;
        try {
            Vibrator v = (Vibrator) getSystemService(VIBRATOR_SERVICE);
            if (v != null && v.hasVibrator()) {
                v.vibrate(VibrationEffect.createOneShot(40L, VibrationEffect.DEFAULT_AMPLITUDE));
            }
        } catch (Throwable ignored) {
        }
    }

    private static SessionRecorder.Sample parseSample(Map<String, Object> m) {
        SessionRecorder.Sample s = new SessionRecorder.Sample();
        s.ts = JsonLite.num(m, "ts", System.currentTimeMillis() / 1000L);
        s.fps = m.get("fps") != null ? (int) JsonLite.num(m, "fps", -1L) : -1;
        s.low1 = m.get("low1") != null ? (int) JsonLite.num(m, "low1", -1L) : -1;
        s.cpuPct = (int) JsonLite.num(m, "cpu_pct", 0L);
        s.cpuC = (int) JsonLite.num(m, "cpu_c", 0L);
        s.cpuMhz = (int) JsonLite.num(m, "cpu_mhz", 0L);
        s.gpuPct = (int) JsonLite.num(m, "gpu_pct", 0L);
        s.gpuMhz = (int) JsonLite.num(m, "gpu_mhz", 0L);
        s.gpuC = (int) JsonLite.num(m, "gpu_c", 0L);
        s.ramUsedMb = (int) JsonLite.num(m, "ram_used_mb", 0L);
        s.ramTotalMb = (int) JsonLite.num(m, "ram_total_mb", 0L);
        s.ramPct = (int) JsonLite.num(m, "ram_pct", 0L);
        s.battC = (int) JsonLite.num(m, "batt_c", 0L);
        s.battPct = (int) JsonLite.num(m, "batt_pct", 0L);
        s.powerMw = (int) JsonLite.num(m, "power_mw", 0L);
        s.charging = JsonLite.bool(m, "charging", false);
        s.softStep = (int) JsonLite.num(m, "soft_step", 0L);
        s.thermalAlert = JsonLite.bool(m, "thermal_alert", false);
        s.thermalAlertMsg = JsonLite.str(m, "thermal_alert_msg", "");
        return s;
    }

    private void appendStyled(SpannableStringBuilder sb, String text, int color, int sp, boolean bold) {
        int a = sb.length();
        sb.append(text);
        int b = sb.length();
        sb.setSpan(new ForegroundColorSpan(color), a, b, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        sb.setSpan(new AbsoluteSizeSpan(sp, true), a, b, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        if (bold) {
            sb.setSpan(new StyleSpan(Typeface.BOLD), a, b, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        }
    }

    private String formatPowerCompact(SessionRecorder.Sample s) {
        String sign = s.charging ? "+" : "";
        return String.format(Locale.US, "%s%.1fW", sign, s.powerMw / 1000f);
    }

    private void renderOverlayText(SessionRecorder.Sample s) {
        if (headerTv == null || rowsTv == null || s == null) return;
        String fpsVal = s.fps > 0 ? String.valueOf(s.fps) : "--";

        SpannableStringBuilder hSb = new SpannableStringBuilder();
        if (compactMode) {
            appendStyled(hSb, fpsVal, 0xFFF2F5F9, 11, true);
            appendStyled(hSb, " FPS", 0xFF9AA4B2, 10, false);
            if (showCpu) {
                appendStyled(hSb, "  C ", 0xFF9AA4B2, 10, false);
                appendStyled(hSb, showClock && s.cpuMhz > 0 ? (s.cpuPct + "% " + s.cpuMhz + "M") : (s.cpuPct + "%"), 0xFFF2F5F9, 10, false);
            }
            if (showGpu) {
                appendStyled(hSb, "  G ", 0xFF9AA4B2, 10, false);
                appendStyled(hSb, showClock && s.gpuMhz > 0 ? (s.gpuPct + "% " + s.gpuMhz + "M") : (s.gpuPct + "%"), 0xFFF2F5F9, 10, false);
            }
            if (showRam) {
                appendStyled(hSb, "  R ", 0xFF9AA4B2, 10, false);
                appendStyled(hSb, s.ramPct + "%", 0xFFF2F5F9, 10, false);
            }
            if (showPower && s.powerMw > 0) {
                appendStyled(hSb, "  " + formatPowerCompact(s), 0xFFF2F5F9, 10, false);
            }
            if (s.thermalAlert) {
                appendStyled(hSb, "  ▲" + Math.max(s.battC, s.cpuC) + "°", 0xFFE57373, 10, true);
            }
            headerTv.setText(hSb);
            updateRecButtonUi();
            return;
        }

        appendStyled(hSb, fpsVal, 0xFFF2F5F9, 13, true);
        appendStyled(hSb, " FPS", 0xFF9AA4B2, 9, false);
        if (showLow1 && s.low1 > 0) {
            appendStyled(hSb, " 1%:" + s.low1, 0xFF9AA4B2, 9, false);
        }
        if (s.thermalAlert) {
            int hotC = Math.max(s.battC, 0) >= 40 ? s.battC : s.cpuC;
            appendStyled(hSb, "  ▲ " + hotC + "°C", 0xFFE57373, 9, true);
        } else if (s.softStep > 0) {
            appendStyled(hSb, " S" + s.softStep, 0xFF9AA4B2, 9, false);
        }
        headerTv.setText(hSb);

        SpannableStringBuilder rSb = new SpannableStringBuilder();
        boolean needNl = false;
        if (showCpu) {
            String cpuLine = showClock
                ? String.format(Locale.US, "%3d%% %4dM %2d°C", s.cpuPct, s.cpuMhz, s.cpuC)
                : String.format(Locale.US, "%3d%%  %2d°C", s.cpuPct, s.cpuC);
            appendStyled(rSb, "CPU ", 0xFF8E98A4, 10, false);
            appendStyled(rSb, cpuLine, 0xFFF2F5F9, 10, false);
            needNl = true;
        }
        if (showGpu) {
            if (needNl) appendStyled(rSb, "\n", 0xFFF2F5F9, 10, false);
            String gpuLine = showClock
                ? String.format(Locale.US, "%3d%% %4dM %2d°C", s.gpuPct, s.gpuMhz, s.gpuC)
                : String.format(Locale.US, "%3d%%  %2d°C", s.gpuPct, s.gpuC);
            appendStyled(rSb, "GPU ", 0xFF8E98A4, 10, false);
            appendStyled(rSb, gpuLine, 0xFFF2F5F9, 10, false);
            needNl = true;
        }
        if (showRam) {
            if (needNl) appendStyled(rSb, "\n", 0xFFF2F5F9, 10, false);
            String ramLine = String.format(Locale.US, "%3d%% %4.1fG", s.ramPct, s.ramUsedMb / 1024f);
            appendStyled(rSb, "RAM ", 0xFF8E98A4, 10, false);
            appendStyled(rSb, ramLine, 0xFFF2F5F9, 10, false);
            needNl = true;
        }
        if (showPower) {
            if (needNl) appendStyled(rSb, "\n", 0xFFF2F5F9, 10, false);
            String pwrLine = String.format(Locale.US, "%5s %2d°C", formatPowerCompact(s), s.battC);
            appendStyled(rSb, "PWR ", 0xFF8E98A4, 10, false);
            appendStyled(rSb, pwrLine, 0xFFF2F5F9, 10, false);
        }
        bodyBox.setVisibility(rSb.length() == 0 ? View.GONE : View.VISIBLE);
        rowsTv.setText(rSb);
        updateRecButtonUi();
    }
}
