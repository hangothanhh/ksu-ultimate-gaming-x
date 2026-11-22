package com.kgx.ultimate;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.ArrayAdapter;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final Set<String> NEW_FLAGSHIPS = new HashSet<>(Arrays.asList(
        "galaxy_s26_ultra", "redmagic_11_pro", "rog_phone_9_pro", "xiaomi_17_ultra",
        "oneplus_15", "iqoo_15", "redmagic_10_pro", "galaxy_s25_ultra",
        "xiaomi_15_ultra", "oneplus_13", "iqoo_13", "realme_gt7_pro",
        "redmi_k80_pro", "redmi_k80_ultra", "vivo_x200_pro", "realme_14_5g"
    ));

    private M3Theme theme;
    private final ExecutorService bg = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());

    private LinearLayout contentContainer;
    private TextView headerSub;
    private TextView rootPill;
    private TextView daemonPill;
    private TextView livePill;
    private final List<LinearLayout> navTabs = new ArrayList<>();
    private final List<TextView> navPills = new ArrayList<>();
    private final List<TextView> navLabels = new ArrayList<>();

    private int currentTab = 0;
    private boolean hasRoot = false;
    private boolean moduleOk = false;
    private boolean autoLive = true;
    private final Runnable livePollTask = new Runnable() {
        @Override
        public void run() {
            if (autoLive && currentTab == 0 && hasRoot && moduleOk) {
                refreshStatusOnly();
            }
            if (autoLive) {
                ui.postDelayed(this, 2500L);
            }
        }
    };

    private Map<String, Object> statusData;
    private Map<String, Object> engineData;
    private List<Map<String, Object>> gamesData = new ArrayList<>();
    private List<Map<String, Object>> profilesData = new ArrayList<>();
    private Map<String, Object> conflictData;
    private Map<String, Object> piDiagData;
    private Map<String, Object> spoofDenylistData;
    private Map<String, Object> freezerData;
    private List<Map<String, Object>> backupsData = new ArrayList<>();
    private List<String> logsData = new ArrayList<>();

    private String gameQuery = "";
    private boolean gameOnlyInstalled = true;
    private String profileQuery = "";
    private String profileCat = "all";
    private String touchOut = "";
    private String pingOut = "";
    private boolean suppressSwitch = false;
    private DashboardHolder dashHolder;

    private static final class DashboardHolder {
        boolean safeMode;
        boolean piWarn;
        int clusterCount;
        LinearLayout tileTemp, tileHz, tileRam, tileTherm;
        TextView spBadge, spHero, hzPill;
        LinearLayout spOrigRow, spGameRow, spFpsRow;
        LinearLayout swPeakUnlock, swSweetSpot, swClockLock, swSoftStep, swBypass;
        LinearLayout c3Header, c4Header;
        TextView c3Sub, c3ModePill, c4Sub, c4StagePill;
        TextView ovPill, ovToggleBtn, ovRecBtn, ovHistBtn, ovLockBtn;
        View gpuBar, ramBar;
        final List<LinearLayout> clRows = new ArrayList<>();
        final List<View> clBars = new ArrayList<>();
        final List<TextView> modeBtns = new ArrayList<>();
        LinearLayout tempRow, ramRow, netRow, powerRow;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        theme = new M3Theme(this);

        Window w = getWindow();
        w.setStatusBarColor(theme.bg);
        w.setNavigationBarColor(theme.surface2);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(theme.bg);

        root.addView(buildTopBar());

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        contentContainer = new LinearLayout(this);
        contentContainer.setOrientation(LinearLayout.VERTICAL);
        int pad = M3Views.dp(this, 14);
        contentContainer.setPadding(pad, M3Views.dp(this, 10), pad, M3Views.dp(this, 18));
        scroll.addView(contentContainer);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        root.addView(buildBottomNav());
        setContentView(root);

        refreshAll(true);
    }

    @Override
    protected void onResume() {
        super.onResume();
        KgxOverlayService.setStateListener(() -> {
            if (currentTab == 0 && dashHolder != null) updateOverlayCardUi();
        });
        ui.removeCallbacks(livePollTask);
        if (autoLive) {
            ui.postDelayed(livePollTask, 2500L);
        }
        if (currentTab == 0 && dashHolder != null) updateOverlayCardUi();
    }

    @Override
    protected void onPause() {
        super.onPause();
        KgxOverlayService.setStateListener(null);
        ui.removeCallbacks(livePollTask);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        ui.removeCallbacks(livePollTask);
        bg.shutdownNow();
    }

    private LinearLayout buildTopBar() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setBackgroundColor(theme.bg);
        int hPad = M3Views.dp(this, 14);
        int vPad = M3Views.dp(this, 10);
        bar.setPadding(hPad, vPad, hPad, vPad);

        TextView badge = new TextView(this);
        badge.setText("GX3");
        badge.setTextSize(13);
        badge.setTypeface(Typeface.DEFAULT_BOLD);
        badge.setTextColor(theme.onPrimaryContainer);
        badge.setGravity(Gravity.CENTER);
        badge.setBackground(M3Views.roundRect(theme.primaryContainer, 0, 0, M3Views.dp(this, 12)));
        LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(
            M3Views.dp(this, 38), M3Views.dp(this, 38));
        blp.rightMargin = M3Views.dp(this, 10);
        bar.addView(badge, blp);

        LinearLayout mid = new LinearLayout(this);
        mid.setOrientation(LinearLayout.VERTICAL);
        TextView t = M3Views.title(this, theme, "Gaming X v1.0.0", 16);
        headerSub = M3Views.subtitle(this, theme, RustBridge.nativeVersion());
        headerSub.setTextSize(10.5f);
        mid.addView(t);
        mid.addView(headerSub);
        bar.addView(mid, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        livePill = M3Views.button(this, theme, "LIVE", theme.secondaryContainer, theme.onSecondaryContainer, true, v -> {
            autoLive = !autoLive;
            updateLivePillStyle();
            ui.removeCallbacks(livePollTask);
            if (autoLive) {
                ui.postDelayed(livePollTask, 2500L);
                toast("Bật cập nhật Live 2.5s");
            } else {
                toast("Tạm dừng Live");
            }
        });
        LinearLayout.LayoutParams llp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        llp.rightMargin = M3Views.dp(this, 5);
        bar.addView(livePill, llp);

        rootPill = M3Views.pill(this, "Root...", theme.surface3, theme.onSurfaceVar);
        LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rlp.rightMargin = M3Views.dp(this, 5);
        bar.addView(rootPill, rlp);

        daemonPill = M3Views.pill(this, "D:--", theme.surface3, theme.onSurfaceVar);
        rlp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rlp.rightMargin = M3Views.dp(this, 5);
        bar.addView(daemonPill, rlp);

        TextView refBtn = M3Views.button(this, theme, "↻", theme.primaryContainer, theme.onPrimaryContainer, true,
            v -> refreshAll(false));
        bar.addView(refBtn);
        updateLivePillStyle();
        return bar;
    }

    private void updateLivePillStyle() {
        if (livePill == null) return;
        livePill.setBackground(M3Views.roundRect(
            autoLive ? theme.secondaryContainer : theme.surface3, 0, 0, M3Views.dp(this, 999)));
        livePill.setTextColor(autoLive ? theme.onSecondaryContainer : theme.onSurfaceVar);
        livePill.setText(autoLive ? "● LIVE" : "PAUSE");
    }

    private LinearLayout buildBottomNav() {
        String[] labels = {"Tổng quan", "Games", "Spoof", "Engine", "Cài đặt"};
        String[] glyphs = {"◈", "🎮", "🛡", "⚡", "⚙"};

        LinearLayout nav = new LinearLayout(this);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setBackgroundColor(theme.surface2);
        nav.setPadding(M3Views.dp(this, 4), M3Views.dp(this, 6), M3Views.dp(this, 4), M3Views.dp(this, 8));

        for (int i = 0; i < labels.length; i++) {
            final int idx = i;
            LinearLayout item = new LinearLayout(this);
            item.setOrientation(LinearLayout.VERTICAL);
            item.setGravity(Gravity.CENTER);
            item.setClickable(true);
            item.setFocusable(true);

            TextView pill = new TextView(this);
            pill.setText(glyphs[i]);
            pill.setTextSize(14);
            pill.setGravity(Gravity.CENTER);
            LinearLayout.LayoutParams plp = new LinearLayout.LayoutParams(
                M3Views.dp(this, 56), M3Views.dp(this, 28));
            item.addView(pill, plp);

            TextView lbl = new TextView(this);
            lbl.setText(labels[i]);
            lbl.setTextSize(11);
            lbl.setTypeface(Typeface.DEFAULT_BOLD);
            lbl.setGravity(Gravity.CENTER);
            lbl.setPadding(0, M3Views.dp(this, 2), 0, 0);
            item.addView(lbl);

            item.setOnClickListener(v -> switchTab(idx));
            nav.addView(item, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            navTabs.add(item);
            navPills.add(pill);
            navLabels.add(lbl);
        }
        updateNavStyles();
        return nav;
    }

    private void updateNavStyles() {
        for (int i = 0; i < navTabs.size(); i++) {
            boolean active = (i == currentTab);
            navPills.get(i).setBackground(M3Views.roundRect(
                active ? theme.secondaryContainer : Color.TRANSPARENT, 0, 0, M3Views.dp(this, 999)));
            navPills.get(i).setTextColor(active ? theme.onSecondaryContainer : theme.onSurfaceVar);
            navLabels.get(i).setTextColor(active ? theme.onSurface : theme.onSurfaceVar);
        }
    }

    private void switchTab(int idx) {
        currentTab = idx;
        dashHolder = null;
        updateNavStyles();
        renderCurrentTab();
        if (idx == 1 && gamesData.isEmpty()) loadGamesAsync();
        if (idx == 2 && (profilesData.isEmpty() || piDiagData == null)) loadProfilesAsync();
        if (idx == 3 && freezerData == null) loadFreezerAsync();
        if (idx == 4) loadSettingsExtrasAsync();
    }

    private void runBg(Runnable task) {
        bg.execute(() -> {
            try {
                task.run();
            } catch (Throwable t) {
                ui.post(() -> toast("Lỗi: " + t.getMessage()));
            }
        });
    }

    private void refreshStatusOnly() {
        runBg(() -> {
            statusData = JsonLite.asMap(RustBridge.call("status"));
            ui.post(() -> {
                updateHeaderPills();
                if (currentTab == 0) updateDashboardInPlace();
            });
        });
    }

    private void refreshAll(boolean initial) {
        runBg(() -> {
            hasRoot = RustBridge.nativeCheckRoot() == 1;
            moduleOk = hasRoot && "OK".equals(RustBridge.checkModuleState());
            if (hasRoot && moduleOk) {
                statusData = JsonLite.asMap(RustBridge.call("status"));
                engineData = JsonLite.asMap(RustBridge.call("engine", "get"));
                if (initial || profilesData.isEmpty()) {
                    Map<String, Object> pr = JsonLite.asMap(RustBridge.call("profiles", "list"));
                    profilesData = toMapList(JsonLite.asList(pr.get("profiles")));
                }
                if (currentTab == 2) {
                    piDiagData = JsonLite.asMap(RustBridge.call("spoof", "diag"));
                }
                if (currentTab == 3) {
                    freezerData = JsonLite.asMap(RustBridge.call("freezer", "status"));
                }
            }
            ui.post(() -> {
                updateHeaderPills();
                if (currentTab == 0 && hasRoot && moduleOk && dashHolder != null) {
                    updateDashboardInPlace();
                } else {
                    renderCurrentTab();
                }
            });
        });
    }

    private void loadGamesAsync() {
        if (!hasRoot || !moduleOk) return;
        runBg(() -> {
            Map<String, Object> gr = JsonLite.asMap(RustBridge.call("games", "list"));
            gamesData = toMapList(JsonLite.asList(gr.get("games")));
            ui.post(this::renderCurrentTab);
        });
    }

    private void loadProfilesAsync() {
        if (!hasRoot || !moduleOk) return;
        runBg(() -> {
            Map<String, Object> pr = JsonLite.asMap(RustBridge.call("profiles", "list"));
            profilesData = toMapList(JsonLite.asList(pr.get("profiles")));
            conflictData = JsonLite.asMap(RustBridge.call("profiles", "conflicts"));
            piDiagData = JsonLite.asMap(RustBridge.call("spoof", "diag"));
            spoofDenylistData = JsonLite.asMap(RustBridge.call("spoof", "denylist"));
            ui.post(this::renderCurrentTab);
        });
    }

    private void loadSettingsExtrasAsync() {
        if (!hasRoot || !moduleOk) return;
        runBg(() -> {
            Map<String, Object> bk = JsonLite.asMap(RustBridge.call("backup", "list"));
            backupsData = toMapList(JsonLite.asList(bk.get("backups")));
            Map<String, Object> lg = JsonLite.asMap(RustBridge.call("logs", "80"));
            List<String> lines = new ArrayList<>();
            for (Object o : JsonLite.asList(lg.get("lines"))) {
                lines.add(String.valueOf(o));
            }
            logsData = lines;
            ui.post(this::renderCurrentTab);
        });
    }

    private void loadSpoofDenylistAsync() {
        if (!hasRoot || !moduleOk) return;
        runBg(() -> {
            spoofDenylistData = JsonLite.asMap(RustBridge.call("spoof", "denylist"));
            ui.post(() -> {
                if (currentTab == 2) renderCurrentTab();
            });
        });
    }

    private void loadFreezerAsync() {
        if (!hasRoot || !moduleOk) return;
        runBg(() -> {
            freezerData = JsonLite.asMap(RustBridge.call("freezer", "status"));
            ui.post(() -> {
                if (currentTab == 3) renderCurrentTab();
            });
        });
    }

    private static List<Map<String, Object>> toMapList(List<Object> raw) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Object o : raw) out.add(JsonLite.asMap(o));
        return out;
    }

    private void updateHeaderPills() {
        if (!hasRoot) {
            rootPill.setText("No Root");
            rootPill.setBackground(M3Views.roundRect(theme.errorContainer, 0, 0, M3Views.dp(this, 999)));
            rootPill.setTextColor(theme.error);
        } else if (!moduleOk) {
            rootPill.setText("No Module");
            rootPill.setBackground(M3Views.roundRect(theme.warnContainer, 0, 0, M3Views.dp(this, 999)));
            rootPill.setTextColor(theme.warn);
        } else {
            rootPill.setText("KSU Rust");
            rootPill.setBackground(M3Views.roundRect(theme.okContainer, 0, 0, M3Views.dp(this, 999)));
            rootPill.setTextColor(theme.ok);
        }

        if (statusData != null) {
            Map<String, Object> rd = JsonLite.asMap(statusData.get("real_device"));
            Map<String, Object> d = JsonLite.asMap(statusData.get("daemon"));
            headerSub.setText(JsonLite.str(rd, "model", "--") + " • " + JsonLite.str(rd, "gpu", "") + " • Rust " + RustBridge.lastIpcMs + "ms");
            boolean dOn = JsonLite.bool(d, "running", false);
            daemonPill.setText(dOn ? "Daemon ON" : "Daemon OFF");
            daemonPill.setBackground(M3Views.roundRect(
                dOn ? theme.okContainer : theme.warnContainer, 0, 0, M3Views.dp(this, 999)));
            daemonPill.setTextColor(dOn ? theme.ok : theme.warn);
        }
    }

    private void toast(String msg) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();
    }

    private void renderCurrentTab() {
        dashHolder = null;
        contentContainer.removeAllViews();
        if (!hasRoot || !moduleOk) {
            renderStatusErrorCard();
            return;
        }
        switch (currentTab) {
            case 0: renderDashboard(); break;
            case 1: renderGames(); break;
            case 2: renderSpoof(); break;
            case 3: renderEngine(); break;
            case 4: renderSettings(); break;
        }
    }

    private void renderStatusErrorCard() {
        LinearLayout c = M3Views.card(this, theme, true);
        c.addView(M3Views.title(this, theme, hasRoot ? "Chưa cài Module KernelSU" : "Cần quyền Root (KernelSU)", 16));
        c.addView(M3Views.subtitle(this, theme,
            hasRoot
                ? "Hãy flash KSU-Ultimate-Gaming-X-v1.0.0.zip trong KernelSU Manager trước."
                : "Hãy cấp quyền Superuser (su) cho KSU Gaming X trong KernelSU Manager rồi bấm Thử lại."));
        LinearLayout row = rowButtons();
        row.addView(M3Views.button(this, theme, "Thử kết nối lại", theme.primary, theme.onPrimary, false, v -> {
            RustBridge.nativeResetPipe();
            refreshAll(true);
        }));
        c.addView(row);
        contentContainer.addView(c);
    }

    private LinearLayout rowButtons() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = M3Views.dp(this, 10);
        row.setLayoutParams(lp);
        return row;
    }

    private void addGap(LinearLayout row, View child) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.rightMargin = M3Views.dp(this, 8);
        row.addView(child, lp);
    }

    // ------------------------------------------------------------------
    // TAB 0: DASHBOARD (Zero-Jank In-Place Binding)
    // ------------------------------------------------------------------
    private String formatFpsText(Map<String, Object> ss, Map<String, Object> fp) {
        Object liveObj = fp.get("live");
        if (liveObj != null) {
            long live = JsonLite.num(fp, "live", 0);
            Object lowObj = fp.get("low1");
            String src = JsonLite.str(fp, "source", "");
            StringBuilder sb = new StringBuilder();
            sb.append(live).append(" FPS");
            if (lowObj != null) {
                sb.append(" (1% Low: ").append(JsonLite.num(fp, "low1", 0)).append(")");
            }
            if (!src.isEmpty() && !"none".equals(src)) {
                sb.append(" • ").append(src);
            }
            return sb.toString();
        }
        return JsonLite.bool(ss, "active", false) ? "Đang lấy mẫu SurfaceFlinger..." : "Idle (SurfaceFlinger)";
    }

    private String formatPowerText(Map<String, Object> pw) {
        long battPct = JsonLite.num(pw, "battery_pct", 0);
        long mw = JsonLite.num(pw, "power_mw", 0);
        boolean chg = JsonLite.bool(pw, "charging", false);
        String wattTxt = mw > 0 ? String.format(Locale.US, " • %s%.1fW", chg ? "+" : "", mw / 1000f) : "";
        boolean sup = JsonLite.bool(pw, "bypass_supported", false);
        boolean act = JsonLite.bool(pw, "bypass_active", false);
        boolean en = JsonLite.bool(pw, "bypass_enabled", false);
        long minPct = JsonLite.num(pw, "bypass_min_pct", 80);
        if (!sup) return "Pin " + battPct + "%" + wattTxt;
        if (act) return "Pin " + battPct + "%" + wattTxt + " • Bypass BẬT (>=" + minPct + "%)";
        if (en) return "Pin " + battPct + "%" + wattTxt + " • Chờ " + minPct + "%";
        return "Pin " + battPct + "%" + wattTxt + " • Sạc thường";
    }

    private int stageBgColor(String stage) {
        if ("UNLOCKED_COOL".equals(stage) || "SWEET_SPOT_COOL".equals(stage) || "HOT".equals(stage)) return theme.warnContainer;
        if ("CRITICAL".equals(stage)) return theme.errorContainer;
        if ("UNLOCKED".equals(stage) || "SWEET_SPOT".equals(stage)) return theme.primaryContainer;
        return theme.okContainer;
    }

    private int stageFgColor(String stage) {
        if ("UNLOCKED_COOL".equals(stage) || "SWEET_SPOT_COOL".equals(stage) || "HOT".equals(stage)) return theme.warn;
        if ("CRITICAL".equals(stage)) return theme.error;
        if ("UNLOCKED".equals(stage) || "SWEET_SPOT".equals(stage)) return theme.onPrimaryContainer;
        return theme.ok;
    }

    private String thermSubText() {
        String base = "Guard Mode";
        if (JsonLite.bool(statusData, "sustained_sweet_spot", false)) base = "Sweet-Spot ON";
        else if (JsonLite.bool(statusData, "thermal_unlock", false)) base = "Peak Unlock ON";
        Map<String, Object> th = JsonLite.asMap(statusData.get("thermal"));
        long tier = JsonLite.num(th, "soft_step_tier", 0);
        if (tier > 0) base += " · Step T" + tier;
        if (JsonLite.bool(th, "alert", false)) base += " · ▲ " + JsonLite.str(th, "alert_msg", "");
        return base;
    }

    private void renderDashboard() {
        if (statusData == null) return;
        Map<String, Object> rd = JsonLite.asMap(statusData.get("real_device"));
        Map<String, Object> sp = JsonLite.asMap(statusData.get("spoof"));
        Map<String, Object> ss = JsonLite.asMap(statusData.get("session"));
        Map<String, Object> cg = JsonLite.asMap(statusData.get("cpu_gpu"));
        Map<String, Object> rm = JsonLite.asMap(statusData.get("ram"));
        Map<String, Object> th = JsonLite.asMap(statusData.get("thermal"));
        Map<String, Object> dp = JsonLite.asMap(statusData.get("display"));
        Map<String, Object> net = JsonLite.asMap(statusData.get("network"));
        Map<String, Object> pw = JsonLite.asMap(statusData.get("power"));
        Map<String, Object> fp = JsonLite.asMap(statusData.get("fps"));

        DashboardHolder h = new DashboardHolder();
        boolean safeMode = JsonLite.bool(statusData, "safe_mode", false);
        h.safeMode = safeMode;

        if (safeMode) {
            LinearLayout sb = M3Views.card(this, theme, true);
            sb.addView(M3Views.title(this, theme, "SAFE MODE ĐANG BẬT", 14));
            sb.addView(M3Views.subtitle(this, theme, "Toàn bộ spoof và tối ưu đang tạm dừng để bảo vệ thiết bị."));
            LinearLayout row = rowButtons();
            row.addView(M3Views.button(this, theme, "Tắt Safe Mode", theme.okContainer, theme.ok, true, v ->
                runAction("safemode", "off")));
            sb.addView(row);
            contentContainer.addView(sb);
        }

        boolean spOn = JsonLite.bool(sp, "enabled", false) && (JsonLite.bool(sp, "active", false) || JsonLite.bool(sp, "system_prop_active", false));
        boolean piAct = JsonLite.bool(sp, "play_integrity_shield_active", false);
        boolean piWarn = spOn && !piAct;
        h.piWarn = piWarn;
        if (piWarn) {
            LinearLayout piCard = M3Views.card(this, theme, true);
            piCard.setBackground(M3Views.roundRect(theme.warnContainer, theme.warn, M3Views.dp(this, 1), M3Views.dp(this, 24)));
            piCard.addView(M3Views.title(this, theme, "Play Integrity Shield chưa kích hoạt", 14));
            piCard.addView(M3Views.subtitle(this, theme,
                "Cần bật ReZygisk và Soft-Reboot để Play Store/GMS nhận đúng máy gốc (không lỗi Device Integrity)."));
            LinearLayout pwRow = rowButtons();
            addGap(pwRow, M3Views.button(this, theme, "Soft-Reboot (Temproot)", theme.primary, theme.onPrimary, true,
                v -> confirmSoftReboot()));
            addGap(pwRow, M3Views.button(this, theme, "Làm mới GMS", theme.secondaryContainer, theme.onSecondaryContainer, true,
                v -> runAction("spoof", "refresh-gms")));
            piCard.addView(pwRow);
            contentContainer.addView(piCard);
        }

        long battC = JsonLite.num(th, "battery_c", 0);
        long cpuC = JsonLite.num(th, "cpu_c", 0);
        long gpuC = JsonLite.num(th, "gpu_c", 0);
        long curHz = JsonLite.num(dp, "current_hz", 60);
        int ramPct = (int) Math.max(0, Math.min(100, JsonLite.num(rm, "used_pct", 0)));
        long availMb = JsonLite.num(rm, "avail_mb", 0);
        String stage = JsonLite.str(th, "stage", "NORMAL");
        int tBg = stageBgColor(stage);
        int tFg = stageFgColor(stage);

        // 2x2 Expressive Tonal Metric Grid
        LinearLayout gridRow1 = new LinearLayout(this);
        gridRow1.setOrientation(LinearLayout.HORIZONTAL);
        h.tileTemp = M3Views.metricTile(this, theme, "CPU / Pin / GPU", cpuC + "°C",
            "Pin " + battC + "°C • GPU " + gpuC + "°C", cpuC >= 78 ? theme.warn : theme.primary, theme.surface2);
        h.tileHz = M3Views.metricTile(this, theme, "Màn Hình", curHz + " Hz",
            "Hỗ trợ: " + JsonLite.str(dp, "supported_hz", "60"), theme.secondary, theme.surface2);
        LinearLayout.LayoutParams tlpL = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tlpL.rightMargin = M3Views.dp(this, 8);
        LinearLayout.LayoutParams tlpR = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        gridRow1.addView(h.tileTemp, tlpL);
        gridRow1.addView(h.tileHz, tlpR);
        contentContainer.addView(gridRow1);

        LinearLayout gridRow2 = new LinearLayout(this);
        gridRow2.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams gr2lp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        gr2lp.topMargin = M3Views.dp(this, 8);
        gr2lp.bottomMargin = M3Views.dp(this, 12);
        h.tileRam = M3Views.metricTile(this, theme, "RAM Đã Dùng", ramPct + "%",
            "Trống " + availMb + " MB • " + JsonLite.str(rm, "pressure", "LOW"),
            ramPct >= 85 ? theme.warn : theme.ok, theme.surface2);
        h.tileTherm = M3Views.metricTile(this, theme, "Thermal Engine", stage,
            thermSubText(), tFg, theme.surface2);
        LinearLayout.LayoutParams tlpL2 = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tlpL2.rightMargin = M3Views.dp(this, 8);
        LinearLayout.LayoutParams tlpR2 = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        gridRow2.addView(h.tileRam, tlpL2);
        gridRow2.addView(h.tileTherm, tlpR2);
        contentContainer.addView(gridRow2, gr2lp);

        // Card 1: Whole-System Spoof, Play Integrity Shield & Live SurfaceFlinger FPS
        LinearLayout c1 = M3Views.card(this, theme, true);
        h.spBadge = M3Views.pill(this, piAct ? "PI Shield ON" : (spOn ? "Safe Spoof" : "Stock"),
            piAct ? theme.okContainer : theme.surface4, piAct ? theme.ok : theme.onSurface);
        c1.addView(M3Views.cardHeader(this, theme, "Whole-System Spoof", "Play Integrity PLT+JNI Shield", h.spBadge));

        h.spHero = new TextView(this);
        h.spHero.setText(spOn
            ? (JsonLite.str(sp, "label", "realme 14 5G") + " (" + JsonLite.str(sp, "current_prop_model", "RMX5070") + ")")
            : ("Stock (" + JsonLite.str(rd, "model", "--") + ")"));
        h.spHero.setTextSize(19);
        h.spHero.setTypeface(Typeface.DEFAULT_BOLD);
        h.spHero.setTextColor(theme.primary);
        c1.addView(h.spHero);

        h.spOrigRow = M3Views.kvRow(this, theme, "Thiết bị gốc (GMS)",
            JsonLite.str(rd, "brand", "") + " " + JsonLite.str(rd, "model", "--") + " (" + JsonLite.str(rd, "device", "--") + ")", true);
        c1.addView(h.spOrigRow);
        c1.addView(M3Views.kvRow(this, theme, "SoC / GPU",
            JsonLite.str(rd, "soc", "--") + " • " + JsonLite.str(rd, "gpu", "--"), false));
        boolean sessAct = JsonLite.bool(ss, "active", false);
        h.spGameRow = M3Views.kvRow(this, theme, "Game active",
            sessAct ? (JsonLite.str(ss, "name", "") + " (" + JsonLite.num(ss, "target_fps", 0) + " FPS)") : "Idle (Chờ mở game)", false);
        c1.addView(h.spGameRow);
        h.spFpsRow = M3Views.kvRow(this, theme, "FPS thực tế / 1% Low", formatFpsText(ss, fp), true);
        c1.addView(h.spFpsRow);

        LinearLayout c1Btns = rowButtons();
        addGap(c1Btns, M3Views.button(this, theme, "Đổi Máy Spoof", theme.primary, theme.onPrimary, true, v -> switchTab(2)));
        addGap(c1Btns, M3Views.button(this, theme, "Khôi phục Gốc", theme.errorContainer, theme.error, true, v ->
            runAction("rollback")));
        c1.addView(c1Btns);
        contentContainer.addView(c1);

        // Card 1B: Scene-style Minimalist FPS Popup & CSV Session Recorder
        LinearLayout cOv = M3Views.card(this, theme, false);
        int recCnt = SessionRecorder.countRecordings(this);
        h.ovPill = M3Views.pill(this, "Tắt", theme.surface4, theme.onSurfaceVar);
        cOv.addView(M3Views.cardHeader(this, theme, "FPS Popup (Kiểu Scene)",
            "Chỉ hiện khi bật • FPS, Xung MHz, Công suất W & CSV", h.ovPill));
        LinearLayout ovBtns = rowButtons();
        h.ovToggleBtn = M3Views.button(this, theme, "Bật Overlay", theme.primary, theme.onPrimary, true, v -> {
            if (KgxOverlayService.isRunning()) {
                KgxOverlayService.stopOverlay(this);
            } else {
                KgxOverlayService.startOverlay(this);
            }
            ui.postDelayed(this::updateOverlayCardUi, 250L);
        });
        h.ovRecBtn = M3Views.button(this, theme, "● Ghi dữ liệu", theme.secondaryContainer, theme.onSecondaryContainer, true, v -> {
            KgxOverlayService.toggleRecord(this);
            ui.postDelayed(this::updateOverlayCardUi, 250L);
        });
        h.ovHistBtn = M3Views.button(this, theme, "Xem lịch sử (" + recCnt + ")", theme.surface4, theme.onSurface, true,
            v -> showRecordingsDialog());
        addGap(ovBtns, h.ovToggleBtn);
        addGap(ovBtns, h.ovRecBtn);
        ovBtns.addView(h.ovHistBtn);
        cOv.addView(ovBtns);

        LinearLayout ovBtns2 = rowButtons();
        TextView ovCfgBtn = M3Views.button(this, theme, "Tùy biến dòng & Hz", theme.surface4, theme.onSurface, true,
            v -> showOverlayPrefsDialog());
        h.ovLockBtn = M3Views.button(this, theme, "Xuyên chạm: Tắt", theme.surface4, theme.onSurface, true, v -> {
            KgxOverlayService.toggleClickThrough(this);
            updateOverlayCardUi();
        });
        addGap(ovBtns2, ovCfgBtn);
        ovBtns2.addView(h.ovLockBtn);
        cOv.addView(ovBtns2);
        contentContainer.addView(cOv);

        // Card 2: Sustained Anti-Lag Thermal, Sweet-Spot & Bypass Charging
        LinearLayout c2 = M3Views.card(this, theme, false);
        h.hzPill = M3Views.pill(this, curHz + " Hz", theme.secondaryContainer, theme.onSecondaryContainer);
        c2.addView(M3Views.cardHeader(this, theme, "Sustained Anti-Lag Engine", "Exynos / QCOM / MTK Anti-Throttle", h.hzPill));
        h.swSweetSpot = M3Views.switchRow(this, theme, "Exynos Sustained Sweet-Spot (~82% Peak)",
            "Khóa trần vùng hiệu suất vàng giữ 120FPS ổn định và mát hơn 6–10°C",
            JsonLite.bool(statusData, "sustained_sweet_spot", false),
            on -> { if (!suppressSwitch) runAction("engine", "set", "SUSTAINED_SWEET_SPOT", on ? "1" : "0"); });
        c2.addView(h.swSweetSpot);
        h.swPeakUnlock = M3Views.switchRow(this, theme, "Bỏ giới hạn nhiệt độ (Sustained Peak Unlock)",
            "Chặn SDHMS/SIOP hạ xung & 60Hz; tự xả floor ở 78°C tránh TMU 90°C",
            JsonLite.bool(statusData, "thermal_unlock", false),
            on -> { if (!suppressSwitch) runAction("engine", "set", "THERMAL_UNLOCK", on ? "1" : "0"); });
        c2.addView(h.swPeakUnlock);
        h.swClockLock = M3Views.switchRow(this, theme, "Khóa xung cao (Fast Ramp Boost)",
            "Uclamp top-app + render thread priority mượt 120FPS",
            JsonLite.bool(statusData, "max_clock_lock", false),
            on -> { if (!suppressSwitch) runAction("engine", "set", "MAX_CLOCK_LOCK", on ? "1" : "0"); });
        c2.addView(h.swClockLock);
        h.swSoftStep = M3Views.switchRow(this, theme, "Hạ trần êm theo nhiệt độ pin (Soft Step-Down)",
            "Giảm nấc 10%–20% khi pin >= 41–43°C giúp giữ FPS phẳng không khựng",
            JsonLite.bool(statusData, "soft_thermal_step", false),
            on -> { if (!suppressSwitch) runAction("engine", "set", "SOFT_THERMAL_STEP", on ? "1" : "0"); });
        c2.addView(h.swSoftStep);
        h.swBypass = M3Views.switchRow(this, theme, "Bypass Charging khi chơi game",
            "Ngắt sạc vào pin khi cắm cáp USB >= " + JsonLite.num(pw, "bypass_min_pct", 80) + "%",
            JsonLite.bool(pw, "bypass_enabled", false),
            on -> { if (!suppressSwitch) runAction("engine", "set", "BYPASS_CHARGING", on ? "1" : "0"); });
        c2.addView(h.swBypass);
        contentContainer.addView(c2);

        // Card 3: CPU & GPU Telemetry + Mode Picker
        LinearLayout c3 = M3Views.card(this, theme, false);
        String curMode = JsonLite.str(ss, "mode", JsonLite.str(engineData, "DEFAULT_MODE", "high_performance"));
        long cpuPct = JsonLite.num(cg, "cpu_pct", 0);
        long gpuPctVal = JsonLite.num(cg, "gpu_pct", 0);
        long gpuCur = JsonLite.num(cg, "gpu_cur_mhz", 0);
        long gpuMax = JsonLite.num(cg, "gpu_max_mhz", 0);
        if (gpuMax <= 0) gpuMax = Math.max(gpuCur, 1);
        int gpuPct = gpuPctVal > 0 ? (int) Math.min(100, gpuPctVal) : (int) Math.min(100, (gpuCur * 100L) / gpuMax);
        h.c3ModePill = M3Views.pill(this, curMode, theme.primaryContainer, theme.onPrimaryContainer);
        h.c3Header = M3Views.cardHeader(this, theme, "CPU & GPU Telemetry",
            "CPU " + cpuPct + "% • GPU " + gpuPct + "% (" + gpuCur + "/" + gpuMax + " MHz, " + JsonLite.str(cg, "gpu_gov", "--") + ")",
            h.c3ModePill);
        h.c3Sub = (TextView) ((LinearLayout) h.c3Header.getChildAt(0)).getChildAt(1);
        c3.addView(h.c3Header);
        h.gpuBar = M3Views.progressBar(this, theme, gpuPct, theme.secondary);
        c3.addView(h.gpuBar);

        List<Object> clList = JsonLite.asList(cg.get("clusters"));
        h.clusterCount = clList.size();
        for (Object clObj : clList) {
            Map<String, Object> cl = JsonLite.asMap(clObj);
            long clCur = JsonLite.num(cl, "cur_mhz", 0);
            long clMax = JsonLite.num(cl, "max_mhz", 0);
            int clPct = clMax > 0 ? (int) Math.min(100, (clCur * 100L) / clMax) : 0;
            LinearLayout row = M3Views.kvRow(this, theme,
                JsonLite.str(cl, "policy", "") + " (" + JsonLite.str(cl, "gov", "") + ")",
                clCur + " MHz [" + JsonLite.num(cl, "min_mhz", 0) + "-" + clMax + "]", true);
            View bar = M3Views.progressBar(this, theme, clPct, theme.primary);
            h.clRows.add(row);
            h.clBars.add(bar);
            c3.addView(row);
            c3.addView(bar);
        }

        LinearLayout mRow1 = rowButtons();
        LinearLayout mRow2 = rowButtons();
        String[][] modes = {
            {"balanced", "Balanced"}, {"high_performance", "High Perf"},
            {"extreme_gaming", "Extreme"}, {"battery_gaming", "Battery"}
        };
        for (int i = 0; i < 4; i++) {
            final String mid = modes[i][0];
            boolean sel = mid.equals(curMode);
            LinearLayout.LayoutParams mlp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
            if (i % 2 == 0) mlp.rightMargin = M3Views.dp(this, 8);
            TextView btn = M3Views.button(this, theme, modes[i][1],
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true,
                v -> runAction("engine", "set", "DEFAULT_MODE", mid));
            h.modeBtns.add(btn);
            (i < 2 ? mRow1 : mRow2).addView(btn, mlp);
        }
        c3.addView(mRow1);
        c3.addView(mRow2);
        contentContainer.addView(c3);

        // Card 4: Temps, RAM, Bypass & Network
        LinearLayout c4 = M3Views.card(this, theme, false);
        h.c4StagePill = M3Views.pill(this, stage, tBg, tFg);
        h.c4Header = M3Views.cardHeader(this, theme, "Nhiệt Độ, RAM & Nguồn",
            "PSI: some " + JsonLite.str(rm, "psi_some", "0") + " / full " + JsonLite.str(rm, "psi_full", "0"),
            h.c4StagePill);
        h.c4Sub = (TextView) ((LinearLayout) h.c4Header.getChildAt(0)).getChildAt(1);
        c4.addView(h.c4Header);
        h.tempRow = M3Views.kvRow(this, theme, "Pin / CPU / GPU",
            battC + "°C • " + cpuC + "°C • " + gpuC + "°C", true);
        c4.addView(h.tempRow);
        h.ramRow = M3Views.kvRow(this, theme, "RAM (" + JsonLite.str(rm, "pressure", "LOW") + ")",
            JsonLite.num(rm, "used_mb", 0) + "/" + JsonLite.num(rm, "total_mb", 0) + " MB (Free " + availMb + " MB)", true);
        c4.addView(h.ramRow);
        h.ramBar = M3Views.progressBar(this, theme, ramPct, ramPct >= 85 ? theme.warn : theme.ok);
        c4.addView(h.ramBar);
        h.powerRow = M3Views.kvRow(this, theme, "Pin / Bypass", formatPowerText(pw), false);
        c4.addView(h.powerRow);
        h.netRow = M3Views.kvRow(this, theme, "Mạng", JsonLite.str(net, "transport", "NONE"), true);
        c4.addView(h.netRow);
        contentContainer.addView(c4);

        dashHolder = h;
        updateOverlayCardUi();
    }

    private void updateDashboardInPlace() {
        if (statusData == null) return;
        Map<String, Object> sp = JsonLite.asMap(statusData.get("spoof"));
        Map<String, Object> ss = JsonLite.asMap(statusData.get("session"));
        Map<String, Object> cg = JsonLite.asMap(statusData.get("cpu_gpu"));
        List<Object> clList = JsonLite.asList(cg.get("clusters"));
        boolean safeMode = JsonLite.bool(statusData, "safe_mode", false);
        boolean spOn = JsonLite.bool(sp, "enabled", false) && (JsonLite.bool(sp, "active", false) || JsonLite.bool(sp, "system_prop_active", false));
        boolean piAct = JsonLite.bool(sp, "play_integrity_shield_active", false);
        boolean piWarn = spOn && !piAct;

        if (dashHolder == null || dashHolder.safeMode != safeMode || dashHolder.piWarn != piWarn
                || dashHolder.clusterCount != clList.size()) {
            renderCurrentTab();
            return;
        }

        DashboardHolder h = dashHolder;
        Map<String, Object> rd = JsonLite.asMap(statusData.get("real_device"));
        Map<String, Object> rm = JsonLite.asMap(statusData.get("ram"));
        Map<String, Object> th = JsonLite.asMap(statusData.get("thermal"));
        Map<String, Object> dp = JsonLite.asMap(statusData.get("display"));
        Map<String, Object> net = JsonLite.asMap(statusData.get("network"));
        Map<String, Object> pw = JsonLite.asMap(statusData.get("power"));
        Map<String, Object> fp = JsonLite.asMap(statusData.get("fps"));

        long battC = JsonLite.num(th, "battery_c", 0);
        long cpuC = JsonLite.num(th, "cpu_c", 0);
        long gpuC = JsonLite.num(th, "gpu_c", 0);
        long curHz = JsonLite.num(dp, "current_hz", 60);
        int ramPct = (int) Math.max(0, Math.min(100, JsonLite.num(rm, "used_pct", 0)));
        long availMb = JsonLite.num(rm, "avail_mb", 0);
        String stage = JsonLite.str(th, "stage", "NORMAL");
        int tBg = stageBgColor(stage);
        int tFg = stageFgColor(stage);

        M3Views.setTileTexts(h.tileTemp, cpuC + "°C", "Pin " + battC + "°C • GPU " + gpuC + "°C", cpuC >= 78 ? theme.warn : theme.primary);
        M3Views.setTileTexts(h.tileHz, curHz + " Hz", "Hỗ trợ: " + JsonLite.str(dp, "supported_hz", "60"), theme.secondary);
        M3Views.setTileTexts(h.tileRam, ramPct + "%", "Trống " + availMb + " MB • " + JsonLite.str(rm, "pressure", "LOW"), ramPct >= 85 ? theme.warn : theme.ok);
        M3Views.setTileTexts(h.tileTherm, stage, thermSubText(), tFg);

        h.spBadge.setText(piAct ? "PI Shield ON" : (spOn ? "Safe Spoof" : "Stock"));
        h.spBadge.setBackground(M3Views.roundRect(piAct ? theme.okContainer : theme.surface4, 0, 0, M3Views.dp(this, 999)));
        h.spBadge.setTextColor(piAct ? theme.ok : theme.onSurface);
        h.spHero.setText(spOn
            ? (JsonLite.str(sp, "label", "realme 14 5G") + " (" + JsonLite.str(sp, "current_prop_model", "RMX5070") + ")")
            : ("Stock (" + JsonLite.str(rd, "model", "--") + ")"));
        boolean sessAct = JsonLite.bool(ss, "active", false);
        M3Views.setKvValue(h.spGameRow,
            sessAct ? (JsonLite.str(ss, "name", "") + " (" + JsonLite.num(ss, "target_fps", 0) + " FPS)") : "Idle (Chờ mở game)");
        M3Views.setKvValue(h.spFpsRow, formatFpsText(ss, fp));

        h.hzPill.setText(curHz + " Hz");
        suppressSwitch = true;
        try {
            M3Views.setSwitchChecked(h.swSweetSpot, JsonLite.bool(statusData, "sustained_sweet_spot", false));
            M3Views.setSwitchChecked(h.swPeakUnlock, JsonLite.bool(statusData, "thermal_unlock", false));
            M3Views.setSwitchChecked(h.swClockLock, JsonLite.bool(statusData, "max_clock_lock", false));
            M3Views.setSwitchChecked(h.swSoftStep, JsonLite.bool(statusData, "soft_thermal_step", false));
            M3Views.setSwitchChecked(h.swBypass, JsonLite.bool(pw, "bypass_enabled", false));
        } finally {
            suppressSwitch = false;
        }

        String curMode = JsonLite.str(ss, "mode", JsonLite.str(engineData, "DEFAULT_MODE", "high_performance"));
        long cpuPct = JsonLite.num(cg, "cpu_pct", 0);
        long gpuPctVal = JsonLite.num(cg, "gpu_pct", 0);
        long gpuCur = JsonLite.num(cg, "gpu_cur_mhz", 0);
        long gpuMax = JsonLite.num(cg, "gpu_max_mhz", 0);
        if (gpuMax <= 0) gpuMax = Math.max(gpuCur, 1);
        int gpuPct = gpuPctVal > 0 ? (int) Math.min(100, gpuPctVal) : (int) Math.min(100, (gpuCur * 100L) / gpuMax);
        h.c3Sub.setText("CPU " + cpuPct + "% • GPU " + gpuPct + "% (" + gpuCur + "/" + gpuMax + " MHz, " + JsonLite.str(cg, "gpu_gov", "--") + ")");
        h.c3ModePill.setText(curMode);
        M3Views.updateProgressBar(h.gpuBar, gpuPct, theme.secondary);

        for (int i = 0; i < clList.size() && i < h.clRows.size(); i++) {
            Map<String, Object> cl = JsonLite.asMap(clList.get(i));
            long clCur = JsonLite.num(cl, "cur_mhz", 0);
            long clMax = JsonLite.num(cl, "max_mhz", 0);
            int clPct = clMax > 0 ? (int) Math.min(100, (clCur * 100L) / clMax) : 0;
            M3Views.setKvValue(h.clRows.get(i), clCur + " MHz [" + JsonLite.num(cl, "min_mhz", 0) + "-" + clMax + "]");
            M3Views.updateProgressBar(h.clBars.get(i), clPct, theme.primary);
        }

        String[] modeIds = {"balanced", "high_performance", "extreme_gaming", "battery_gaming"};
        for (int i = 0; i < modeIds.length && i < h.modeBtns.size(); i++) {
            boolean sel = modeIds[i].equals(curMode);
            TextView b = h.modeBtns.get(i);
            b.setBackground(M3Views.ripplePill(sel ? theme.primary : theme.surface4, 0x33FFFFFF, M3Views.dp(this, 999)));
            b.setTextColor(sel ? theme.onPrimary : theme.onSurface);
        }

        h.c4Sub.setText("PSI: some " + JsonLite.str(rm, "psi_some", "0") + " / full " + JsonLite.str(rm, "psi_full", "0"));
        h.c4StagePill.setText(stage);
        h.c4StagePill.setBackground(M3Views.roundRect(tBg, 0, 0, M3Views.dp(this, 999)));
        h.c4StagePill.setTextColor(tFg);
        M3Views.setKvValue(h.tempRow, battC + "°C • " + cpuC + "°C • " + gpuC + "°C");
        M3Views.setKvValue(h.ramRow, JsonLite.num(rm, "used_mb", 0) + "/" + JsonLite.num(rm, "total_mb", 0) + " MB (Free " + availMb + " MB)");
        M3Views.updateProgressBar(h.ramBar, ramPct, ramPct >= 85 ? theme.warn : theme.ok);
        M3Views.setKvValue(h.powerRow, formatPowerText(pw));
        M3Views.setKvValue(h.netRow, JsonLite.str(net, "transport", "NONE"));
        updateOverlayCardUi();
    }

    private void updateOverlayCardUi() {
        DashboardHolder h = dashHolder;
        if (h == null || h.ovPill == null) return;
        boolean run = KgxOverlayService.isRunning();
        boolean rec = KgxOverlayService.isRecording();
        long dur = KgxOverlayService.getRecDurationSec();
        int cnt = SessionRecorder.countRecordings(this);

        if (rec) {
            h.ovPill.setText(String.format(Locale.US, "Đang ghi ● %02d:%02d", dur / 60, dur % 60));
            h.ovPill.setBackground(M3Views.roundRect(theme.errorContainer, 0, 0, M3Views.dp(this, 999)));
            h.ovPill.setTextColor(theme.error);
        } else if (run) {
            h.ovPill.setText("Đang bật");
            h.ovPill.setBackground(M3Views.roundRect(theme.okContainer, 0, 0, M3Views.dp(this, 999)));
            h.ovPill.setTextColor(theme.ok);
        } else {
            h.ovPill.setText("Tắt");
            h.ovPill.setBackground(M3Views.roundRect(theme.surface4, 0, 0, M3Views.dp(this, 999)));
            h.ovPill.setTextColor(theme.onSurfaceVar);
        }

        h.ovToggleBtn.setText(run ? "Tắt Overlay" : "Bật Overlay");
        h.ovToggleBtn.setBackground(M3Views.ripplePill(
            run ? theme.errorContainer : theme.primary, 0x33FFFFFF, M3Views.dp(this, 999)));
        h.ovToggleBtn.setTextColor(run ? theme.error : theme.onPrimary);

        h.ovRecBtn.setText(rec ? "■ Dừng ghi" : "● Ghi dữ liệu");
        h.ovRecBtn.setBackground(M3Views.ripplePill(
            rec ? theme.warnContainer : theme.secondaryContainer, 0x33FFFFFF, M3Views.dp(this, 999)));
        h.ovRecBtn.setTextColor(rec ? theme.warn : theme.onSecondaryContainer);

        h.ovHistBtn.setText("Xem lịch sử (" + cnt + ")");

        if (h.ovLockBtn != null) {
            boolean locked = KgxOverlayService.isClickThrough(this);
            h.ovLockBtn.setText(locked ? "Xuyên chạm: ĐÃ KHÓA" : "Xuyên chạm: Tắt");
            h.ovLockBtn.setBackground(M3Views.ripplePill(
                locked ? theme.warnContainer : theme.surface4, 0x33FFFFFF, M3Views.dp(this, 999)));
            h.ovLockBtn.setTextColor(locked ? theme.warn : theme.onSurface);
        }
    }

    private void showOverlayPrefsDialog() {
        SharedPreferences sp = getSharedPreferences(KgxOverlayService.PREF_NAME, MODE_PRIVATE);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setBackgroundColor(theme.surface3);
        int p = M3Views.dp(this, 14);
        body.setPadding(p, p, p, p);

        final boolean[] bLow1 = {sp.getBoolean("show_low1", true)};
        final boolean[] bCpu = {sp.getBoolean("show_cpu", true)};
        final boolean[] bGpu = {sp.getBoolean("show_gpu", true)};
        final boolean[] bClock = {sp.getBoolean("show_clock", true)};
        final boolean[] bRam = {sp.getBoolean("show_ram", true)};
        final boolean[] bPwr = {sp.getBoolean("show_power", true)};
        final long[] pollRef = {sp.getLong("poll_ms", 1000L)};
        final int[] alphaRef = {sp.getInt("bg_alpha", 190)};

        body.addView(M3Views.switchRow(this, theme, "Hiện 1% Low FPS", "", bLow1[0], v -> bLow1[0] = v));
        body.addView(M3Views.switchRow(this, theme, "Hiện dòng CPU (% / MHz / °C)", "", bCpu[0], v -> bCpu[0] = v));
        body.addView(M3Views.switchRow(this, theme, "Hiện dòng GPU (% / MHz / °C)", "", bGpu[0], v -> bGpu[0] = v));
        body.addView(M3Views.switchRow(this, theme, "Hiện xung nhịp MHz trên Popup", "", bClock[0], v -> bClock[0] = v));
        body.addView(M3Views.switchRow(this, theme, "Hiện dòng RAM (% / GB)", "", bRam[0], v -> bRam[0] = v));
        body.addView(M3Views.switchRow(this, theme, "Hiện dòng Công suất W & nhiệt Pin", "", bPwr[0], v -> bPwr[0] = v));

        body.addView(M3Views.subtitle(this, theme, "Tốc độ cập nhật Popup:"));
        LinearLayout pollRow = rowButtons();
        final List<TextView> pollBtns = new ArrayList<>();
        long[] pVals = {500L, 1000L, 2000L};
        String[] pLbls = {"0.5s", "1s", "2s"};
        for (int i = 0; i < pVals.length; i++) {
            final int idx = i;
            final long pv = pVals[i];
            boolean sel = (pollRef[0] == pv);
            TextView b = M3Views.button(this, theme, pLbls[i],
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true, v -> {
                    pollRef[0] = pv;
                    for (int j = 0; j < pollBtns.size(); j++) {
                        boolean s2 = (j == idx);
                        pollBtns.get(j).setBackground(M3Views.ripplePill(s2 ? theme.primary : theme.surface4, 0x33FFFFFF, M3Views.dp(this, 999)));
                        pollBtns.get(j).setTextColor(s2 ? theme.onPrimary : theme.onSurface);
                    }
                });
            pollBtns.add(b);
            addGap(pollRow, b);
        }
        body.addView(pollRow);

        body.addView(M3Views.subtitle(this, theme, "Độ mờ nền Popup:"));
        LinearLayout alphaRow = rowButtons();
        final List<TextView> alphaBtns = new ArrayList<>();
        int[] aVals = {150, 190, 230};
        String[] aLbls = {"60%", "75%", "90%"};
        for (int i = 0; i < aVals.length; i++) {
            final int idx = i;
            final int av = aVals[i];
            boolean sel = (alphaRef[0] == av);
            TextView b = M3Views.button(this, theme, aLbls[i],
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true, v -> {
                    alphaRef[0] = av;
                    for (int j = 0; j < alphaBtns.size(); j++) {
                        boolean s2 = (j == idx);
                        alphaBtns.get(j).setBackground(M3Views.ripplePill(s2 ? theme.primary : theme.surface4, 0x33FFFFFF, M3Views.dp(this, 999)));
                        alphaBtns.get(j).setTextColor(s2 ? theme.onPrimary : theme.onSurface);
                    }
                });
            alphaBtns.add(b);
            addGap(alphaRow, b);
        }
        body.addView(alphaRow);

        ScrollView sv = new ScrollView(this);
        sv.addView(body);
        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Tùy biến Popup Scene")
            .setView(sv)
            .setPositiveButton("Áp dụng", (d, w) -> {
                sp.edit()
                    .putBoolean("show_low1", bLow1[0])
                    .putBoolean("show_cpu", bCpu[0])
                    .putBoolean("show_gpu", bGpu[0])
                    .putBoolean("show_clock", bClock[0])
                    .putBoolean("show_ram", bRam[0])
                    .putBoolean("show_power", bPwr[0])
                    .putLong("poll_ms", pollRef[0])
                    .putInt("bg_alpha", alphaRef[0])
                    .apply();
                KgxOverlayService.reloadPrefs(this);
                toast("Đã cập nhật hiển thị Popup");
            })
            .setNegativeButton("Đóng", null)
            .show();
    }

    private void showRecordingsDialog() {
        List<SessionRecorder.Summary> items = SessionRecorder.listSummaries(this);
        if (items.isEmpty()) {
            new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Lịch sử ghi FPS & Telemetry")
                .setMessage("Chưa có phiên nào được ghi.\nBấm \"● Ghi dữ liệu\" trên Overlay hoặc trong app khi chơi để lưu lại FPS, CPU%, GPU%, RAM%, nhiệt độ.")
                .setPositiveButton("Đóng", null)
                .show();
            return;
        }

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setBackgroundColor(theme.bg);
        int p = M3Views.dp(this, 12);
        body.setPadding(p, p, p, p);

        SimpleDateFormat fmt = new SimpleDateFormat("dd/MM HH:mm", Locale.US);
        final AlertDialog[] holder = new AlertDialog[1];
        for (SessionRecorder.Summary s : items) {
            LinearLayout card = M3Views.card(this, theme, false);
            String when = s.startEpoch > 0 ? fmt.format(new Date(s.startEpoch * 1000L)) : "--";
            String fpsTxt = s.avgFps > 0 ? (s.avgFps + " FPS") : "-- FPS";
            card.addView(M3Views.cardHeader(this, theme, s.pkg,
                when + " • " + s.durationSec + "s (" + s.sampleCount + " mẫu)",
                M3Views.pill(this, fpsTxt, theme.surface4, theme.onSurface)));
            card.addView(M3Views.subtitle(this, theme,
                "1% Low " + s.low1Fps + " • CPU " + s.avgCpuPct + "% (" + s.maxCpuC + "°C) • GPU "
                    + s.avgGpuPct + "% • RAM " + s.avgRamPct + "%"));
            card.setOnClickListener(v -> {
                if (holder[0] != null) holder[0].dismiss();
                showRecordingDetailDialog(s);
            });
            body.addView(card);
        }

        ScrollView sv = new ScrollView(this);
        sv.addView(body);
        holder[0] = new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Phiên đã ghi (" + items.size() + ")")
            .setView(sv)
            .setNegativeButton("Đóng", null)
            .create();
        holder[0].show();
    }

    private void showRecordingDetailDialog(SessionRecorder.Summary s) {
        List<SessionRecorder.Sample> samples = SessionRecorder.loadSamples(s.file);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setBackgroundColor(theme.bg);
        int p = M3Views.dp(this, 14);
        body.setPadding(p, p, p, p);

        TelemetryChartView chart = new TelemetryChartView(this);
        chart.setData(samples, TelemetryChartView.METRIC_FPS);
        body.addView(chart, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, M3Views.dp(this, 170)));

        LinearLayout tabs = rowButtons();
        String[] mNames = {"FPS", "CPU %", "GPU %", "RAM %", "Nhiệt °C", "Công suất W", "Xung MHz"};
        int[] mIds = {
            TelemetryChartView.METRIC_FPS,
            TelemetryChartView.METRIC_CPU,
            TelemetryChartView.METRIC_GPU,
            TelemetryChartView.METRIC_RAM,
            TelemetryChartView.METRIC_TEMP,
            TelemetryChartView.METRIC_POWER,
            TelemetryChartView.METRIC_CLOCK
        };
        final List<TextView> tabBtns = new ArrayList<>();
        for (int i = 0; i < mNames.length; i++) {
            final int idx = i;
            final int metric = mIds[i];
            boolean act = (i == 0);
            TextView b = M3Views.button(this, theme, mNames[i],
                act ? theme.primary : theme.surface4,
                act ? theme.onPrimary : theme.onSurface, true, v -> {
                    chart.setData(samples, metric);
                    for (int j = 0; j < tabBtns.size(); j++) {
                        boolean sel = (j == idx);
                        tabBtns.get(j).setBackground(M3Views.ripplePill(
                            sel ? theme.primary : theme.surface4, 0x33FFFFFF, M3Views.dp(this, 999)));
                        tabBtns.get(j).setTextColor(sel ? theme.onPrimary : theme.onSurface);
                    }
                });
            tabBtns.add(b);
            addGap(tabs, b);
        }
        HorizontalScrollView hsv = new HorizontalScrollView(this);
        hsv.setHorizontalScrollBarEnabled(false);
        hsv.addView(tabs);
        body.addView(hsv);

        body.addView(M3Views.kvRow(this, theme, "FPS (TB / 1% Low)",
            s.avgFps + " FPS / " + s.low1Fps + " FPS (Min " + s.minFps + " - Max " + s.maxFps + ")", true));
        body.addView(M3Views.kvRow(this, theme, "CPU / GPU TB",
            "CPU " + s.avgCpuPct + "% • GPU " + s.avgGpuPct + "%", true));
        body.addView(M3Views.kvRow(this, theme, "Công suất TB / Đỉnh",
            s.avgPowerMw > 0
                ? String.format(Locale.US, "%.1fW / %.1fW", s.avgPowerMw / 1000f, s.maxPowerMw / 1000f)
                : "--",
            true));
        body.addView(M3Views.kvRow(this, theme, "RAM TB / Nhiệt đỉnh",
            "RAM " + s.avgRamPct + "% • CPU " + s.maxCpuC + "°C / GPU " + s.maxGpuC + "°C / Pin " + s.maxBattC + "°C", true));

        ScrollView sv = new ScrollView(this);
        sv.addView(body);
        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(s.pkg + " (" + s.durationSec + "s)")
            .setView(sv)
            .setPositiveButton("Xuất CSV", (d, w) -> runBg(() -> {
                String dst = SessionRecorder.exportToDownloads(s.file);
                ui.post(() -> toast(dst.isEmpty() ? "Xuất CSV thất bại" : ("Đã lưu: " + dst)));
            }))
            .setNeutralButton("Xóa", (d, w) -> {
                SessionRecorder.deleteRecording(s.file);
                updateOverlayCardUi();
                toast("Đã xóa bản ghi");
            })
            .setNegativeButton("Đóng", null)
            .show();
    }

    // ------------------------------------------------------------------
    // TAB 1: GAMES MANAGER
    // ------------------------------------------------------------------
    private void renderGames() {
        LinearLayout bar = M3Views.card(this, theme, false);
        LinearLayout listBox = new LinearLayout(this);
        listBox.setOrientation(LinearLayout.VERTICAL);

        EditText search = styledInput("Tìm tên game hoặc package...", gameQuery);
        search.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
            public void onTextChanged(CharSequence s, int a, int b, int c) {}
            public void afterTextChanged(Editable s) {
                gameQuery = s.toString();
                fillGamesList(listBox);
            }
        });
        bar.addView(search);

        LinearLayout opts = rowButtons();
        CheckBox chk = new CheckBox(this);
        chk.setText("Chỉ hiện game đã cài");
        chk.setTextColor(theme.onSurface);
        chk.setChecked(gameOnlyInstalled);
        chk.setOnCheckedChangeListener((b, c) -> {
            gameOnlyInstalled = c;
            fillGamesList(listBox);
        });
        opts.addView(chk);
        addGap(opts, M3Views.button(this, theme, "Quét & Tải lại", theme.primaryContainer, theme.onPrimaryContainer, true,
            v -> loadGamesAsync()));
        addGap(opts, M3Views.button(this, theme, "+ Thêm App", theme.primary, theme.onPrimary, true,
            v -> showAddAppDialog()));
        bar.addView(opts);
        contentContainer.addView(bar);
        contentContainer.addView(listBox);
        fillGamesList(listBox);
    }

    private void fillGamesList(LinearLayout listBox) {
        listBox.removeAllViews();
        if (gamesData.isEmpty()) {
            LinearLayout empty = M3Views.card(this, theme, false);
            empty.addView(M3Views.subtitle(this, theme, "Đang tải danh sách game..."));
            listBox.addView(empty);
            return;
        }

        String q = gameQuery.toLowerCase().trim();
        for (Map<String, Object> g : gamesData) {
            boolean inst = JsonLite.bool(g, "installed", false);
            if (gameOnlyInstalled && !inst) continue;
            String name = JsonLite.str(g, "name", "");
            String pkg = JsonLite.str(g, "package", "");
            if (!q.isEmpty() && !name.toLowerCase().contains(q) && !pkg.toLowerCase().contains(q)) continue;

            boolean isKnown = JsonLite.bool(g, "known_db", true);
            String dscale = JsonLite.str(g, "downscale", "1.0");
            String wres = JsonLite.str(g, "wm_res", "default");

            LinearLayout c = M3Views.card(this, theme, false);
            c.addView(M3Views.cardHeader(this, theme, name, pkg,
                M3Views.pill(this, inst ? (isKnown ? "Đã cài" : "Tự thêm") : "DB",
                    inst ? theme.okContainer : theme.surface4, inst ? theme.ok : theme.onSurfaceVar)));
            c.addView(M3Views.kvRow(this, theme, "Target / Max FPS",
                JsonLite.num(g, "target_fps", 60) + " / " + JsonLite.num(g, "engine_max_fps", 60)
                    + " FPS (" + JsonLite.str(g, "limit_type", "OPEN") + ")", true));
            c.addView(M3Views.kvRow(this, theme, "Mode / Display / Scale",
                JsonLite.str(g, "mode", "high_performance") + " • " + JsonLite.str(g, "display_hz", "auto")
                    + " • " + dscale + "x" + ("default".equals(wres) ? "" : (" • " + wres)), true));

            LinearLayout row = rowButtons();
            addGap(row, M3Views.button(this, theme, "Cấu hình", theme.primary, theme.onPrimary, true,
                v -> showGameDialog(g)));
            addGap(row, M3Views.button(this, theme, "Test Apply", theme.primaryContainer, theme.onPrimaryContainer, true,
                v -> runAction("games", "apply", pkg)));
            addGap(row, M3Views.button(this, theme, "Clear Data", theme.errorContainer, theme.error, true,
                v -> confirmClearData(pkg, name)));
            if (!isKnown) {
                addGap(row, M3Views.button(this, theme, "Gỡ", theme.surface4, theme.onSurfaceVar, true,
                    v -> runAction("games", "remove", pkg)));
            }
            c.addView(row);
            listBox.addView(c);
        }
    }

    private void showAddAppDialog() {
        toast("Đang quét danh sách app đã cài...");
        runBg(() -> {
            Map<String, Object> scan = JsonLite.asMap(RustBridge.call("games", "scan"));
            List<Object> third = JsonLite.asList(scan.get("third_party_packages"));
            Set<String> existing = new HashSet<>();
            for (Map<String, Object> g : gamesData) {
                existing.add(JsonLite.str(g, "package", ""));
            }
            List<String> pkgs = new ArrayList<>();
            for (Object o : third) {
                String s = String.valueOf(o);
                if (!existing.contains(s)) pkgs.add(s);
            }
            for (Object o : third) {
                String s = String.valueOf(o);
                if (existing.contains(s)) pkgs.add(s);
            }

            ui.post(() -> {
                LinearLayout body = new LinearLayout(this);
                body.setOrientation(LinearLayout.VERTICAL);
                body.setBackgroundColor(theme.surface3);
                int p = M3Views.dp(this, 14);
                body.setPadding(p, p, p, p);

                EditText search = styledInput("Tìm tên package app/game...", "");
                LinearLayout list = new LinearLayout(this);
                list.setOrientation(LinearLayout.VERTICAL);
                ScrollView sc = new ScrollView(this);
                sc.addView(list);
                LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, M3Views.dp(this, 360));
                body.addView(search);
                body.addView(sc, slp);

                AlertDialog dlg = new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                    .setTitle("Thêm App / Game ngoài DB (" + pkgs.size() + ")")
                    .setView(body)
                    .setNegativeButton("Đóng", null)
                    .create();

                Runnable populate = () -> {
                    list.removeAllViews();
                    String q = search.getText().toString().toLowerCase().trim();
                    int shown = 0;
                    for (String pkg : pkgs) {
                        if (!q.isEmpty() && !pkg.toLowerCase().contains(q)) continue;
                        if (shown++ >= 80) break;
                        boolean inList = existing.contains(pkg);
                        LinearLayout row = M3Views.kvRow(this, theme, pkg, inList ? "Đã có" : "+ Thêm", true);
                        row.setPadding(M3Views.dp(this, 4), M3Views.dp(this, 10), M3Views.dp(this, 4), M3Views.dp(this, 10));
                        row.setOnClickListener(v -> {
                            dlg.dismiss();
                            Map<String, Object> stub = new java.util.LinkedHashMap<>();
                            stub.put("package", pkg);
                            stub.put("name", pkg);
                            stub.put("enabled", Boolean.TRUE);
                            stub.put("target_fps", 120L);
                            stub.put("mode", "high_performance");
                            stub.put("display_hz", "120");
                            stub.put("touch_profile", "esports");
                            stub.put("net_opt", Boolean.TRUE);
                            stub.put("downscale", "1.0");
                            stub.put("wm_res", "default");
                            showGameDialog(stub);
                        });
                        list.addView(row);
                    }
                };
                search.addTextChangedListener(new TextWatcher() {
                    public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
                    public void onTextChanged(CharSequence s, int a, int b, int c) {}
                    public void afterTextChanged(Editable s) { populate.run(); }
                });
                populate.run();
                dlg.show();
            });
        });
    }

    private void showGameDialog(Map<String, Object> g) {
        String pkg = JsonLite.str(g, "package", "");
        String name = JsonLite.str(g, "name", pkg);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setBackgroundColor(theme.surface3);
        int p = M3Views.dp(this, 16);
        body.setPadding(p, p, p, p);

        final boolean[] enRef = {JsonLite.bool(g, "enabled", true)};
        final boolean[] netRef = {JsonLite.bool(g, "net_opt", true)};
        body.addView(M3Views.switchRow(this, theme, "Bật tối ưu cho game", "", enRef[0], v -> enRef[0] = v));

        Spinner spFps = makeSpinner(new String[]{"60", "90", "120", "144"}, String.valueOf(JsonLite.num(g, "target_fps", 120)));
        Spinner spMode = makeSpinner(new String[]{"balanced", "high_performance", "extreme_gaming", "battery_gaming"}, JsonLite.str(g, "mode", "high_performance"));
        Spinner spHz = makeSpinner(new String[]{"auto", "60", "90", "120", "144"}, JsonLite.str(g, "display_hz", "auto"));
        Spinner spTouch = makeSpinner(new String[]{"standard", "esports", "precision"}, JsonLite.str(g, "touch_profile", "esports"));
        Spinner spScale = makeSpinner(new String[]{"1.0", "0.9", "0.85", "0.8", "0.75"}, JsonLite.str(g, "downscale", "1.0"));
        Spinner spWres = makeSpinner(new String[]{"default", "1080x1920", "900x1600", "720x1280"}, JsonLite.str(g, "wm_res", "default"));

        body.addView(labeledSpinner("FPS Mục Tiêu", spFps));
        body.addView(labeledSpinner("Chế độ hiệu năng", spMode));
        body.addView(labeledSpinner("Refresh Rate", spHz));
        body.addView(labeledSpinner("Scale độ phân giải (Android 12+)", spScale));
        body.addView(labeledSpinner("Ép độ phân giải game (wm size)", spWres));
        body.addView(labeledSpinner("Touch Profile", spTouch));
        body.addView(M3Views.switchRow(this, theme, "Wi-Fi Low-Latency", "", netRef[0], v -> netRef[0] = v));

        ScrollView dlgScroll = new ScrollView(this);
        dlgScroll.addView(body);

        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(name + "\n(" + pkg + ")")
            .setView(dlgScroll)
            .setPositiveButton("Lưu", (d, w) -> {
                String payload = pkg + "\t" + (enRef[0] ? "1" : "0") + "\tauto\t"
                    + spFps.getSelectedItem() + "\t" + spMode.getSelectedItem() + "\t"
                    + spHz.getSelectedItem() + "\t" + spTouch.getSelectedItem() + "\t"
                    + (netRef[0] ? "1" : "0") + "\t" + spScale.getSelectedItem() + "\t" + spWres.getSelectedItem();
                runAction("games", "set-b64", RustBridge.encodeB64(payload));
            })
            .setNeutralButton("Clear Data Game", (d, w) -> confirmClearData(pkg, name))
            .setNegativeButton("Đóng", null)
            .show();
    }

    private void confirmClearData(String pkg, String name) {
        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Xóa dữ liệu " + name + "?")
            .setMessage("Thao tác này chạy pm clear " + pkg + " để game nhận model spoof mới (ví dụ mở 120FPS Free Fire). Bạn sẽ cần đăng nhập lại.")
            .setPositiveButton("Xóa ngay", (d, w) -> runAction("games", "clear-data", pkg))
            .setNegativeButton("Hủy", null)
            .show();
    }

    // ------------------------------------------------------------------
    // TAB 2: DEVICE SPOOF (WHOLE-SYSTEM + PLAY INTEGRITY SHIELD + 2026)
    // ------------------------------------------------------------------
    private void renderSpoof() {
        String activeId = JsonLite.str(engineData, "GLOBAL_SPOOF_PROFILE", "realme_14_5g");

        LinearLayout hero = M3Views.card(this, theme, true);
        hero.addView(M3Views.cardHeader(this, theme, "Whole-System Persistent Spoof",
            "An toàn Play Integrity • Hỗ trợ Flagship 2025–2026",
            M3Views.pill(this, activeId, theme.primaryContainer, theme.onPrimaryContainer)));
        hero.addView(M3Views.switchRow(this, theme, "Play Integrity Stock-Identity Shield",
            "Chỉ gửi thông số máy gốc cho GMS/Play Store; game thấy máy flagship spoof",
            JsonLite.bool(engineData, "PLAY_INTEGRITY_SHIELD", true),
            on -> runAction("engine", "set", "PLAY_INTEGRITY_SHIELD", on ? "1" : "0")));

        if (conflictData != null) {
            hero.addView(M3Views.kvRow(this, theme, "Trạng thái Shield",
                JsonLite.str(conflictData, "shield_note", ""), false));
        }

        if (piDiagData != null) {
            boolean fpOk = JsonLite.bool(piDiagData, "fingerprint_stock", true);
            boolean jniAct = JsonLite.bool(piDiagData, "jni_active", false);
            long sc = JsonLite.num(piDiagData, "shielded_count", 0);
            String rz = JsonLite.str(piDiagData, "rezygisk_desc", "");
            if (!rz.isEmpty()) {
                hero.addView(M3Views.kvRow(this, theme, "ReZygisk Core", rz, false));
            }
            hero.addView(M3Views.kvRow(this, theme, "Chẩn đoán PI Shield",
                "FP gốc: " + (fpOk ? "Chuẩn" : "Lệch") + " • Hook: " + (jniAct ? "PLT + JNI" : "PLT") + " • Đã bọc " + sc + " tiến trình", false));
            List<Object> procs = JsonLite.asList(piDiagData.get("shielded_procs"));
            if (!procs.isEmpty()) {
                List<String> ps = new ArrayList<>();
                for (Object o : procs) ps.add(String.valueOf(o));
                hero.addView(M3Views.kvRow(this, theme, "Tiến trình đã bọc", String.join(", ", ps), true));
            }
        }

        LinearLayout hBtns1 = rowButtons();
        addGap(hBtns1, M3Views.button(this, theme, "Soft-Reboot (Temproot)", theme.primary, theme.onPrimary, true,
            v -> confirmSoftReboot()));
        addGap(hBtns1, M3Views.button(this, theme, "Làm mới GMS", theme.secondaryContainer, theme.onSecondaryContainer, true,
            v -> runAction("spoof", "refresh-gms")));
        hero.addView(hBtns1);

        LinearLayout hBtns2 = rowButtons();
        addGap(hBtns2, M3Views.button(this, theme, "Chẩn đoán PI", theme.primaryContainer, theme.onPrimaryContainer, true,
            v -> runBg(() -> {
                piDiagData = JsonLite.asMap(RustBridge.call("spoof", "diag"));
                ui.post(this::renderCurrentTab);
            })));
        addGap(hBtns2, M3Views.button(this, theme, "Khôi phục Máy Gốc", theme.errorContainer, theme.error, true,
            v -> runAction("spoof", "restore")));
        addGap(hBtns2, M3Views.button(this, theme, "+ Tạo Profile", theme.surface4, theme.onSurface, true,
            v -> showCreateProfileDialog()));
        hero.addView(hBtns2);
        contentContainer.addView(hero);

        boolean exSettings = JsonLite.bool(engineData, "SPOOF_EXCLUDE_SETTINGS",
            JsonLite.bool(spoofDenylistData, "exclude_settings", true));
        List<String> denyPkgs = new ArrayList<>();
        if (spoofDenylistData != null) {
            for (Object o : JsonLite.asList(spoofDenylistData.get("packages"))) {
                String p = String.valueOf(o).trim();
                if (!p.isEmpty()) denyPkgs.add(p);
            }
        }
        LinearLayout denyCard = M3Views.card(this, theme, false);
        denyCard.addView(M3Views.cardHeader(this, theme, "Spoof Denylist (Không Spoof)",
            "App trong danh sách luôn nhận máy gốc, không bị áp dụng model spoof",
            M3Views.pill(this, (exSettings ? "Cài đặt + " : "") + denyPkgs.size() + " app",
                theme.primaryContainer, theme.onPrimaryContainer)));
        denyCard.addView(M3Views.switchRow(this, theme, "Không spoof ứng dụng Cài đặt (Settings)",
            "Giữ model & tên máy gốc cho com.android.settings (mặc định bật)",
            exSettings,
            on -> runAction("engine", "set", "SPOOF_EXCLUDE_SETTINGS", on ? "1" : "0")));

        String denySummary;
        if (denyPkgs.isEmpty()) {
            denySummary = "Chưa chọn app bổ sung — đang bảo vệ GMS/Play Store" + (exSettings ? " & Cài đặt" : "");
        } else {
            PackageManager pm = getPackageManager();
            List<String> shown = new ArrayList<>();
            int lim = Math.min(denyPkgs.size(), 6);
            for (int i = 0; i < lim; i++) {
                String pkg = denyPkgs.get(i);
                String lbl = resolveAppLabel(pm, pkg);
                shown.add(lbl.equals(pkg) ? pkg : (lbl + " (" + pkg + ")"));
            }
            denySummary = String.join(", ", shown) + (denyPkgs.size() > 6 ? " ... (+" + (denyPkgs.size() - 6) + " app)" : "");
        }
        denyCard.addView(M3Views.kvRow(this, theme, "Danh sách loại trừ", denySummary, !denyPkgs.isEmpty()));

        LinearLayout dBtns = rowButtons();
        addGap(dBtns, M3Views.button(this, theme, "Chọn ứng dụng (" + denyPkgs.size() + ")",
            theme.primary, theme.onPrimary, true, v -> showSpoofDenylistPickerDialog()));
        if (!denyPkgs.isEmpty()) {
            addGap(dBtns, M3Views.button(this, theme, "Xóa hết",
                theme.errorContainer, theme.error, true,
                v -> runAction("spoof", "denylist-set-b64", "")));
        }
        denyCard.addView(dBtns);
        contentContainer.addView(denyCard);

        // Search & Filter card (live instant filter without losing keyboard focus)
        LinearLayout filterCard = M3Views.card(this, theme, false);
        LinearLayout profilesBox = new LinearLayout(this);
        profilesBox.setOrientation(LinearLayout.VERTICAL);

        EditText pSearch = styledInput("Tìm tên máy / model (vd: S26, RedMagic, ROG 9, RMX5070)...", profileQuery);
        pSearch.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
            public void onTextChanged(CharSequence s, int a, int b, int c) {}
            public void afterTextChanged(Editable s) {
                profileQuery = s.toString();
                fillProfilesList(profilesBox, activeId);
            }
        });
        filterCard.addView(pSearch);

        HorizontalScrollView hsv = new HorizontalScrollView(this);
        hsv.setHorizontalScrollBarEnabled(false);
        LinearLayout chips = rowButtons();
        String[][] cats = {
            {"all", "Tất cả"},
            {"flagship_new", "2025–2026 Mới"},
            {"gaming", "ROG / RedMagic"},
            {"xiaomi_flagship", "Xiaomi / Redmi"},
            {"samsung_ultra", "Samsung Ultra"}
        };
        for (String[] c : cats) {
            boolean act = c[0].equals(profileCat);
            addGap(chips, M3Views.button(this, theme, c[1],
                act ? theme.secondaryContainer : theme.surface3,
                act ? theme.onSecondaryContainer : theme.onSurfaceVar, true,
                v -> { profileCat = c[0]; renderCurrentTab(); }));
        }
        hsv.addView(chips);
        filterCard.addView(hsv);
        contentContainer.addView(filterCard);
        contentContainer.addView(profilesBox);
        fillProfilesList(profilesBox, activeId);
    }

    private void fillProfilesList(LinearLayout profilesBox, String activeId) {
        profilesBox.removeAllViews();
        String q = profileQuery.toLowerCase().trim();
        for (Map<String, Object> p : profilesData) {
            String pid = JsonLite.str(p, "id", "");
            String cat = JsonLite.str(p, "category", "");
            String label = JsonLite.str(p, "label", "");
            String model = JsonLite.str(p, "model", "");
            String brand = JsonLite.str(p, "brand", "");
            boolean isCust = JsonLite.bool(p, "custom", false);

            if ("flagship_new".equals(profileCat) && !NEW_FLAGSHIPS.contains(pid) && !isCust) continue;
            if ("gaming".equals(profileCat) && !"rog_phone".equals(cat) && !"redmagic".equals(cat) && !"black_shark".equals(cat)) continue;
            if ("xiaomi_flagship".equals(profileCat) && !"xiaomi_flagship".equals(cat)) continue;
            if ("samsung_ultra".equals(profileCat) && !"samsung_ultra".equals(cat)) continue;
            if (!q.isEmpty() && !(label + " " + model + " " + brand + " " + pid).toLowerCase().contains(q)) continue;

            boolean isSel = pid.equals(activeId);
            LinearLayout card = M3Views.card(this, theme, isSel);
            String compat = JsonLite.str(p, "compat_level", "OPTIMAL");
            long score = JsonLite.num(p, "compat_score", 80);
            card.addView(M3Views.cardHeader(this, theme,
                label + (isSel ? " ✓" : ""),
                JsonLite.str(p, "soc_family", "") + "/" + JsonLite.str(p, "gpu_family", "")
                    + " • " + JsonLite.num(p, "max_hz", 120) + "Hz • " + JsonLite.num(p, "ram_gb", 12) + "GB",
                M3Views.pill(this, compat + " " + score,
                    "OPTIMAL".equals(compat) ? theme.okContainer : theme.surface4,
                    "OPTIMAL".equals(compat) ? theme.ok : theme.onSurfaceVar)));
            card.addView(M3Views.kvRow(this, theme, "Brand / Model", brand + " / " + model, true));
            card.addView(M3Views.kvRow(this, theme, "Device / Product",
                JsonLite.str(p, "device", "") + " / " + JsonLite.str(p, "product", ""), true));

            LinearLayout btnRow = rowButtons();
            addGap(btnRow, M3Views.button(this, theme,
                isSel ? "Đang dùng Toàn Hệ Thống" : "Áp dụng Toàn Hệ Thống",
                isSel ? theme.okContainer : theme.primary,
                isSel ? theme.ok : theme.onPrimary, true,
                v -> {
                    runAction("spoof", "apply-global", pid);
                    toast("Đã spoof -> " + model + ". Bấm Soft-Reboot (Temproot) để áp dụng!");
                }));
            if (isCust) {
                addGap(btnRow, M3Views.button(this, theme, "Xóa", theme.errorContainer, theme.error, true, v -> {
                    runAction("profiles", "delete", pid);
                    loadProfilesAsync();
                }));
            }
            card.addView(btnRow);
            profilesBox.addView(card);
        }
    }

    private void confirmSoftReboot() {
        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Soft-Reboot (An toàn Temproot)?")
            .setMessage("Thao tác này chạy /data/adb/ksud soft-reboot để khởi động lại userspace Android (giữ nguyên Temproot, KHÔNG reboot nguồn cứng) nhằm áp dụng Spoof & ReZygisk.")
            .setPositiveButton("Soft-Reboot ngay", (d, w) -> runAction("system", "soft-reboot"))
            .setNegativeButton("Hủy", null)
            .show();
    }

    private void showCreateProfileDialog() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setBackgroundColor(theme.surface3);
        int p = M3Views.dp(this, 16);
        body.setPadding(p, p, p, p);

        EditText eId = styledInput("ID (vd: rog9_custom)", "");
        EditText eLbl = styledInput("Tên (vd: ROG Phone 9 Pro)", "");
        EditText eBrd = styledInput("Brand (vd: asus)", "asus");
        EditText eMdl = styledInput("Model (vd: ASUS_AI2501_D)", "ASUS_AI2501_D");
        EditText eDev = styledInput("Device (vd: AI2501)", "AI2501");
        EditText ePrd = styledInput("Product (vd: WW_AI2501)", "WW_AI2501");
        EditText eHz = styledInput("Max Hz (120/144/165)", "144");
        eHz.setInputType(InputType.TYPE_CLASS_NUMBER);
        for (View v : new View[]{eId, eLbl, eBrd, eMdl, eDev, ePrd, eHz}) body.addView(v);

        ScrollView cpScroll = new ScrollView(this);
        cpScroll.addView(body);

        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Tạo Profile Thiết Bị")
            .setView(cpScroll)
            .setPositiveButton("Lưu", (d, w) -> {
                String payload = eId.getText().toString().trim() + "\t"
                    + eLbl.getText().toString().trim() + "\tsnapdragon\tadreno\t3\t"
                    + eHz.getText().toString().trim() + "\t16\t"
                    + eBrd.getText().toString().trim() + "\t" + eBrd.getText().toString().trim() + "\t"
                    + eMdl.getText().toString().trim() + "\t" + eDev.getText().toString().trim() + "\t"
                    + ePrd.getText().toString().trim() + "\t-\tCustom profile";
                runAction("profiles", "create-b64", RustBridge.encodeB64(payload));
                loadProfilesAsync();
            })
            .setNegativeButton("Hủy", null)
            .show();
    }

    // ------------------------------------------------------------------
    // TAB 3: GAMING ENGINE
    // ------------------------------------------------------------------
    private void renderEngine() {
        Map<String, Object> pw = statusData != null ? JsonLite.asMap(statusData.get("power")) : new java.util.LinkedHashMap<>();
        Map<String, Object> th = statusData != null ? JsonLite.asMap(statusData.get("thermal")) : new java.util.LinkedHashMap<>();

        LinearLayout c1 = M3Views.card(this, theme, false);
        c1.addView(M3Views.cardHeader(this, theme, "CPU, GPU & Thermal Anti-Throttle",
            "Sustained Sweet-Spot + Anti-TMU Relief", null));
        c1.addView(M3Views.switchRow(this, theme, "Exynos Sustained Sweet-Spot (~82% Peak)",
            "Khóa trần hiệu suất vàng giữ 120FPS ổn định và mát hơn 6–10°C",
            JsonLite.bool(engineData, "SUSTAINED_SWEET_SPOT", false),
            on -> runAction("engine", "set", "SUSTAINED_SWEET_SPOT", on ? "1" : "0")));
        c1.addView(M3Views.switchRow(this, theme, "Sustained Peak Thermal Unlock",
            "Chặn SDHMS/SIOP/restricted_device_performance; mở max clock & giữ 120Hz",
            JsonLite.bool(engineData, "THERMAL_UNLOCK", false),
            on -> runAction("engine", "set", "THERMAL_UNLOCK", on ? "1" : "0")));
        c1.addView(M3Views.switchRow(this, theme, "Fast Ramp Clock Boost",
            "Giữ floor phản hồi nhanh & ưu tiên luồng RenderThread/UnityMain",
            JsonLite.bool(engineData, "MAX_CLOCK_LOCK", false),
            on -> runAction("engine", "set", "MAX_CLOCK_LOCK", on ? "1" : "0")));
        c1.addView(M3Views.switchRow(this, theme, "Hạ trần êm theo nhiệt độ pin (Soft Step-Down)",
            "Hạ nhẹ nấc -10% (>=41°C pin / 82°C CPU) & -20% (>=43°C / 87°C) • Đang: Tier " + JsonLite.num(th, "soft_step_tier", 0),
            JsonLite.bool(engineData, "SOFT_THERMAL_STEP", false),
            on -> runAction("engine", "set", "SOFT_THERMAL_STEP", on ? "1" : "0")));
        c1.addView(M3Views.switchRow(this, theme, "Thermal Guard (khi tắt Peak/Sweet-Spot)",
            "Tự hạ bậc mượt khi pin >= 41°C",
            JsonLite.bool(engineData, "THERMAL_GUARD_ENABLED", true),
            on -> runAction("engine", "set", "THERMAL_GUARD_ENABLED", on ? "1" : "0")));
        c1.addView(M3Views.switchRow(this, theme, "Samsung GOS Neutralizer (Tắt GOS)",
            "Tắt com.samsung.android.game.gos tránh bóp FPS/độ phân giải (tự bật lại khi Safe Mode)",
            JsonLite.bool(engineData, "GOS_NEUTRALIZE", false),
            on -> runAction("engine", "set", "GOS_NEUTRALIZE", on ? "1" : "0")));
        contentContainer.addView(c1);

        Map<String, Object> ext = statusData != null ? JsonLite.asMap(statusData.get("ext_display")) : new java.util.LinkedHashMap<>();
        boolean extConn = JsonLite.bool(ext, "connected", false);
        boolean extOff = JsonLite.bool(ext, "internal_screen_off", false);
        String extName = JsonLite.str(ext, "external_name", "");
        Map<String, Object> resSt = statusData != null ? JsonLite.asMap(statusData.get("res_override")) : new java.util.LinkedHashMap<>();
        boolean resAct = JsonLite.bool(resSt, "active", false);
        String curResScope = JsonLite.str(engineData, "RES_OVERRIDE_SCOPE", "ext_scrcpy");
        String curResPreset = JsonLite.str(engineData, "RES_OVERRIDE_PRESET", "1080x1920");
        String curResDens = JsonLite.str(engineData, "RES_OVERRIDE_DENSITY", "auto");

        LinearLayout cExt = M3Views.card(this, theme, false);
        cExt.addView(M3Views.cardHeader(this, theme, "Màn Hình Rời, scrcpy & Ép Độ Phân Giải",
            "Tự tắt màn AMOLED khi cắm ngoài + Đổi tỉ lệ 16:9 / hạ độ phân giải",
            M3Views.pill(this, extConn ? "Ngoài ON" : (resAct ? JsonLite.str(resSt, "current_res", "Res") : "Gốc"),
                (extConn || resAct) ? theme.okContainer : theme.surface4,
                (extConn || resAct) ? theme.ok : theme.onSurfaceVar)));
        cExt.addView(M3Views.switchRow(this, theme, "Tự tắt màn hình máy khi cắm màn hình rời",
            "Chỉ tắt khi phát hiện DP/HDMI ngoài; rút cáp hoặc Safe Mode tự sáng lại",
            JsonLite.bool(engineData, "EXT_DISPLAY_SCREEN_OFF", false),
            on -> runAction("engine", "set", "EXT_DISPLAY_SCREEN_OFF", on ? "1" : "0")));
        cExt.addView(M3Views.kvRow(this, theme, "Trạng thái màn máy / rời",
            (extConn ? ("Ngoài: " + extName) : "Chưa cắm ngoài") + (extOff ? " • Màn máy TẮT" : " • Màn máy BẬT"),
            false));
        cExt.addView(M3Views.switchRow(this, theme, "Ép độ phân giải toàn hệ thống (wm size)",
            "Dùng tỉ lệ 16:9 (hết viền đen PC/DeX) hoặc hạ 900p/720p tăng FPS",
            JsonLite.bool(engineData, "RES_OVERRIDE_ENABLED", false),
            on -> runAction("engine", "set", "RES_OVERRIDE_ENABLED", on ? "1" : "0")));

        LinearLayout scopeRow = rowButtons();
        String[][] scopes = {{"ext_scrcpy", "Màn ngoài & scrcpy"}, {"always", "Toàn hệ thống"}};
        for (String[] sc : scopes) {
            boolean sel = sc[0].equals(curResScope);
            addGap(scopeRow, M3Views.button(this, theme, sc[1],
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true,
                v -> runAction("engine", "set", "RES_OVERRIDE_SCOPE", sc[0])));
        }
        cExt.addView(M3Views.subtitle(this, theme, "Phạm vi áp dụng:"));
        cExt.addView(scopeRow);

        LinearLayout presetRow = rowButtons();
        for (String pr : new String[]{"1080x1920", "900x1600", "720x1280", "1440x2560"}) {
            boolean sel = pr.equals(curResPreset);
            addGap(presetRow, M3Views.button(this, theme, pr,
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true,
                v -> runAction("engine", "set", "RES_OVERRIDE_PRESET", pr)));
        }
        HorizontalScrollView pHsv = new HorizontalScrollView(this);
        pHsv.setHorizontalScrollBarEnabled(false);
        pHsv.addView(presetRow);
        cExt.addView(M3Views.subtitle(this, theme, "Độ phân giải mục tiêu:"));
        cExt.addView(pHsv);

        LinearLayout densRow = rowButtons();
        for (String dn : new String[]{"auto", "360", "400", "440", "480"}) {
            boolean sel = dn.equals(curResDens);
            addGap(densRow, M3Views.button(this, theme, "auto".equals(dn) ? "Auto DPI" : dn,
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true,
                v -> runAction("engine", "set", "RES_OVERRIDE_DENSITY", dn)));
        }
        cExt.addView(M3Views.subtitle(this, theme, "Mật độ DPI:"));
        cExt.addView(densRow);

        cExt.addView(M3Views.kvRow(this, theme, "Độ phân giải hiện hành",
            resAct ? (JsonLite.str(resSt, "current_res", "--") + " @ " + JsonLite.str(resSt, "current_density", "--") + "dpi (" + JsonLite.str(resSt, "source", "") + ")") : "Mặc định thiết bị",
            true));

        LinearLayout extBtns = rowButtons();
        addGap(extBtns, M3Views.button(this, theme, "Bật lại màn máy", theme.primaryContainer, theme.onPrimaryContainer, true,
            v -> runAction("display", "internal-power", "on")));
        addGap(extBtns, M3Views.button(this, theme, "Khôi phục gốc (wm reset)", theme.errorContainer, theme.error, true,
            v -> runAction("display", "res-reset")));
        cExt.addView(extBtns);
        cExt.addView(M3Views.subtitle(this, theme,
            "Quick Settings Tiles: Kéo thanh trạng thái → nút Sửa → thêm KGX Mode, Bypass Charge, FPS Overlay."));
        contentContainer.addView(cExt);

        // Card Freezer: View & DeX-safe cgroup v2 App Freezer
        Map<String, Object> fz = freezerData != null ? freezerData
            : (statusData != null ? JsonLite.asMap(statusData.get("freezer")) : new java.util.LinkedHashMap<>());
        boolean fzSup = JsonLite.bool(fz, "supported", false);
        long fzTargets = JsonLite.num(fz, "target_count", 0);
        long fzFrozen = JsonLite.num(fz, "frozen_count", 0);
        LinearLayout cFrz = M3Views.card(this, theme, false);
        cFrz.addView(M3Views.cardHeader(this, theme, "App Freezer (cgroup v2)",
            "Chỉ đóng băng app nền rảnh khi chơi • Bảo vệ app mở Pop-up View & DeX",
            M3Views.pill(this, fzFrozen + " Đang đóng băng",
                fzFrozen > 0 ? theme.okContainer : theme.surface4,
                fzFrozen > 0 ? theme.ok : theme.onSurfaceVar)));
        cFrz.addView(M3Views.switchRow(this, theme, "Bật App Freezer thông minh khi vào game",
            "Tự rã băng ngay < 50ms nếu bạn mở app đó ở cửa sổ nổi hoặc Samsung DeX",
            JsonLite.bool(engineData, "FREEZER_ENABLED", false),
            on -> runAction("engine", "set", "FREEZER_ENABLED", on ? "1" : "0")));
        cFrz.addView(M3Views.kvRow(this, theme, "Trạng thái kernel cgroup.freeze",
            (fzSup ? "Hỗ trợ sẵn" : "Không khả dụng") + " • Danh sách: " + fzTargets + " app", false));
        LinearLayout fzBtns = rowButtons();
        addGap(fzBtns, M3Views.button(this, theme, "Chọn App đóng băng (" + fzTargets + ")", theme.primary, theme.onPrimary, true,
            v -> showFreezerPickerDialog()));
        fzBtns.addView(M3Views.button(this, theme, "Rã băng tất cả", theme.secondaryContainer, theme.onSecondaryContainer, true,
            v -> runAction("freezer", "unfreeze-all")));
        cFrz.addView(fzBtns);
        contentContainer.addView(cFrz);

        // Card Thermal Alert (#18)
        LinearLayout cAl = M3Views.card(this, theme, false);
        boolean alOn = JsonLite.bool(engineData, "THERMAL_ALERT_ENABLED", true);
        long alBatt = JsonLite.num(engineData, "THERMAL_ALERT_BATT_C", 44);
        long alCpu = JsonLite.num(engineData, "THERMAL_ALERT_CPU_C", 92);
        String alAct = JsonLite.str(engineData, "THERMAL_ALERT_ACTION", "notify");
        cAl.addView(M3Views.cardHeader(this, theme, "Cảnh báo quá nhiệt & Bảo vệ pin",
            "Báo chấm ▲ gọn trên Popup + rung nhẹ 40ms khi vượt ngưỡng",
            M3Views.pill(this, alBatt + "°C / " + alCpu + "°C",
                alOn ? theme.warnContainer : theme.surface4, alOn ? theme.warn : theme.onSurfaceVar)));
        cAl.addView(M3Views.switchRow(this, theme, "Bật cảnh báo quá nhiệt",
            "Bảo vệ pin & màn hình AMOLED S22 khi chơi nặng", alOn,
            on -> runAction("engine", "set", "THERMAL_ALERT_ENABLED", on ? "1" : "0")));
        LinearLayout bRow = rowButtons();
        for (int bv : new int[]{42, 44, 46}) {
            boolean sel = (bv == alBatt);
            final String bStr = String.valueOf(bv);
            addGap(bRow, M3Views.button(this, theme, "Pin " + bv + "°C",
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true,
                v -> runAction("engine", "set", "THERMAL_ALERT_BATT_C", bStr)));
        }
        cAl.addView(M3Views.subtitle(this, theme, "Ngưỡng cảnh báo nhiệt Pin:"));
        cAl.addView(bRow);

        LinearLayout cpuRow = rowButtons();
        for (int cv : new int[]{88, 92, 95}) {
            boolean sel = (cv == alCpu);
            final String cStr = String.valueOf(cv);
            addGap(cpuRow, M3Views.button(this, theme, "CPU " + cv + "°C",
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true,
                v -> runAction("engine", "set", "THERMAL_ALERT_CPU_C", cStr)));
        }
        cAl.addView(M3Views.subtitle(this, theme, "Ngưỡng cảnh báo nhiệt CPU:"));
        cAl.addView(cpuRow);

        LinearLayout actRow = rowButtons();
        String[][] acts = {{"notify", "Chỉ báo"}, {"bypass", "+ Bypass"}, {"step_down", "+ Hạ xung"}, {"both", "Cả hai"}};
        for (String[] ac : acts) {
            boolean sel = ac[0].equals(alAct);
            addGap(actRow, M3Views.button(this, theme, ac[1],
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true,
                v -> runAction("engine", "set", "THERMAL_ALERT_ACTION", ac[0])));
        }
        cAl.addView(M3Views.subtitle(this, theme, "Hành động khi quá nhiệt:"));
        cAl.addView(actRow);
        contentContainer.addView(cAl);

        LinearLayout cPow = M3Views.card(this, theme, false);
        cPow.addView(M3Views.cardHeader(this, theme, "Pin & Bypass Charging",
            "Ngắt dòng sạc vào pin khi cắm cáp chơi game giúp giảm 4–7°C",
            M3Views.pill(this, JsonLite.num(pw, "battery_pct", 0) + "%", theme.secondaryContainer, theme.onSecondaryContainer)));
        cPow.addView(M3Views.switchRow(this, theme, "Bật Bypass Charging (Samsung/Kernel Node)",
            "Tự khôi phục sạc bình thường khi thoát game hoặc bật Safe Mode",
            JsonLite.bool(engineData, "BYPASS_CHARGING", false),
            on -> runAction("engine", "set", "BYPASS_CHARGING", on ? "1" : "0")));
        cPow.addView(M3Views.kvRow(this, theme, "Trạng thái nguồn", formatPowerText(pw), false));

        long curMinPct = JsonLite.num(engineData, "BYPASS_MIN_PCT", 80);
        LinearLayout pctRow = rowButtons();
        for (int pVal : new int[]{70, 80, 85, 90}) {
            boolean sel = (pVal == curMinPct);
            final String pStr = String.valueOf(pVal);
            addGap(pctRow, M3Views.button(this, theme, pStr + "%",
                sel ? theme.primary : theme.surface4, sel ? theme.onPrimary : theme.onSurface, true,
                v -> runAction("engine", "set", "BYPASS_MIN_PCT", pStr)));
        }
        cPow.addView(M3Views.subtitle(this, theme, "Ngưỡng pin tối thiểu để bật Bypass:"));
        cPow.addView(pctRow);
        contentContainer.addView(cPow);

        LinearLayout c2 = M3Views.card(this, theme, false);
        c2.addView(M3Views.cardHeader(this, theme, "RAM, Touch, Display & Wi-Fi Low-Latency",
            "Đã loại bỏ hoàn toàn netpolicy gây ngắt USB Samsung", null));
        c2.addView(M3Views.switchRow(this, theme, "Tối ưu RAM & Background", "Trim theo áp lực bộ nhớ PSI",
            JsonLite.bool(engineData, "RAM_OPT_ENABLED", true),
            on -> runAction("engine", "set", "RAM_OPT_ENABLED", on ? "1" : "0")));
        c2.addView(M3Views.switchRow(this, theme, "Touch Game Mode Node", "Hỗ trợ Samsung /sys/class/sec/tsp/cmd",
            JsonLite.bool(engineData, "TOUCH_OPT_ENABLED", true),
            on -> runAction("engine", "set", "TOUCH_OPT_ENABLED", on ? "1" : "0")));
        c2.addView(M3Views.switchRow(this, theme, "Khóa 120Hz khi vào game", "Chống SDHMS tự hạ 120Hz xuống 60Hz",
            JsonLite.bool(engineData, "DISPLAY_AUTO_HZ", true),
            on -> runAction("engine", "set", "DISPLAY_AUTO_HZ", on ? "1" : "0")));
        c2.addView(M3Views.switchRow(this, theme, "Wi-Fi Low-Latency Mode", "cmd wifi force-low-latency-mode",
            JsonLite.bool(engineData, "NET_WIFI_LOW_LATENCY", true),
            on -> runAction("engine", "set", "NET_WIFI_LOW_LATENCY", on ? "1" : "0")));

        LinearLayout testRow = rowButtons();
        addGap(testRow, M3Views.button(this, theme, "Đo Touch Rate (2s)", theme.primaryContainer, theme.onPrimaryContainer, true,
            v -> runBg(() -> {
                Map<String, Object> res = JsonLite.asMap(RustBridge.call("touch", "measure"));
                touchOut = JsonLite.str(res, "driver", "") + " | " + JsonLite.num(res, "hz", 0) + " Hz (" + JsonLite.num(res, "samples", 0) + " samples)";
                ui.post(this::renderCurrentTab);
            })));
        addGap(testRow, M3Views.button(this, theme, "Đo Ping 1.1.1.1", theme.primary, theme.onPrimary, true,
            v -> runBg(() -> {
                Map<String, Object> res = JsonLite.asMap(RustBridge.call("net", "test", "1.1.1.1"));
                pingOut = JsonLite.str(res, "transport", "") + " | Avg " + JsonLite.str(res, "avg_ms", "0") + "ms | Loss " + JsonLite.str(res, "loss_pct", "0") + "%";
                ui.post(this::renderCurrentTab);
            })));
        c2.addView(testRow);
        if (!touchOut.isEmpty()) c2.addView(M3Views.subtitle(this, theme, "Touch: " + touchOut));
        if (!pingOut.isEmpty()) c2.addView(M3Views.subtitle(this, theme, "Net: " + pingOut));
        contentContainer.addView(c2);
    }

    // ------------------------------------------------------------------
    // TAB 4: SETTINGS & LOGS
    // ------------------------------------------------------------------
    private void renderSettings() {
        LinearLayout c1 = M3Views.card(this, theme, false);
        c1.addView(M3Views.cardHeader(this, theme, "Điều Khiển Hệ Thống", "Daemon & Safety Guard", null));
        c1.addView(M3Views.switchRow(this, theme, "Tự động tối ưu khi mở game", "",
            JsonLite.bool(engineData, "AUTO_OPTIMIZE", true),
            on -> runAction("engine", "set", "AUTO_OPTIMIZE", on ? "1" : "0")));
        c1.addView(M3Views.switchRow(this, theme, "Bật Whole-System Spoof Engine", "",
            JsonLite.bool(engineData, "SPOOF_ENABLED", true),
            on -> runAction("engine", "set", "SPOOF_ENABLED", on ? "1" : "0")));
        c1.addView(M3Views.switchRow(this, theme, "Safe Mode", "Tạm dừng mọi spoof & tweak và khôi phục gốc",
            JsonLite.bool(engineData, "SAFE_MODE", false),
            on -> runAction("safemode", on ? "on" : "off")));

        LinearLayout dRow = rowButtons();
        addGap(dRow, M3Views.button(this, theme, "Start", theme.okContainer, theme.ok, true, v -> runAction("daemon", "start")));
        addGap(dRow, M3Views.button(this, theme, "Restart", theme.primaryContainer, theme.onPrimaryContainer, true, v -> runAction("daemon", "restart")));
        addGap(dRow, M3Views.button(this, theme, "Stop", theme.errorContainer, theme.error, true, v -> runAction("daemon", "stop")));
        addGap(dRow, M3Views.button(this, theme, "Rollback Hết", theme.errorContainer, theme.error, true, v -> runAction("rollback")));
        c1.addView(dRow);
        contentContainer.addView(c1);

        LinearLayout c2 = M3Views.card(this, theme, false);
        c2.addView(M3Views.cardHeader(this, theme, "Backup & Logs", "Sao lưu cấu hình nhanh",
            M3Views.button(this, theme, "+ Backup", theme.primary, theme.onPrimary, true, v -> {
                runAction("backup", "create", "manual");
                loadSettingsExtrasAsync();
            })));
        for (Map<String, Object> b : backupsData) {
            String bn = JsonLite.str(b, "name", "");
            LinearLayout r = M3Views.kvRow(this, theme, bn, Math.max(1, JsonLite.num(b, "size_bytes", 0) / 1024) + " KB", true);
            r.setOnClickListener(v -> runAction("backup", "restore", bn));
            c2.addView(r);
        }

        TextView logBox = new TextView(this);
        logBox.setTypeface(Typeface.MONOSPACE);
        logBox.setTextSize(10.5f);
        logBox.setTextColor(theme.onSurface);
        logBox.setBackground(M3Views.roundRect(theme.bg, theme.outlineSoft, M3Views.dp(this, 1), M3Views.dp(this, 12)));
        int lp = M3Views.dp(this, 10);
        logBox.setPadding(lp, lp, lp, lp);
        logBox.setText(logsData.isEmpty() ? "(Đang tải logs...)" : String.join("\n", logsData));
        c2.addView(logBox);
        contentContainer.addView(c2);
    }

    private void showFreezerPickerDialog() {
        toast("Đang tải danh sách ứng dụng...");
        runBg(() -> {
            Map<String, Object> fz = JsonLite.asMap(RustBridge.call("freezer", "status"));
            freezerData = fz;
            Set<String> selected = new HashSet<>();
            for (Object o : JsonLite.asList(fz.get("targets"))) {
                selected.add(String.valueOf(o));
            }
            Map<String, Object> scan = JsonLite.asMap(RustBridge.call("games", "scan"));
            Set<String> known = new HashSet<>();
            for (Object o : JsonLite.asList(scan.get("matched_known"))) {
                known.add(JsonLite.str(JsonLite.asMap(o), "package", ""));
            }
            List<String> allPkgs = new ArrayList<>();
            for (Object o : JsonLite.asList(scan.get("third_party_packages"))) {
                String pkg = String.valueOf(o);
                if (!"com.kgx.ultimate".equals(pkg) && !known.contains(pkg)) {
                    allPkgs.add(pkg);
                }
            }
            for (String s : selected) {
                if (!allPkgs.contains(s) && !"com.kgx.ultimate".equals(s)) allPkgs.add(0, s);
            }

            ui.post(() -> {
                LinearLayout body = new LinearLayout(this);
                body.setOrientation(LinearLayout.VERTICAL);
                body.setBackgroundColor(theme.surface3);
                int p = M3Views.dp(this, 14);
                body.setPadding(p, p, p, p);

                EditText search = styledInput("Tìm package app nền cần đóng băng...", "");
                LinearLayout list = new LinearLayout(this);
                list.setOrientation(LinearLayout.VERTICAL);
                ScrollView sc = new ScrollView(this);
                sc.addView(list);
                body.addView(search);
                body.addView(sc, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, M3Views.dp(this, 340)));

                Runnable populate = () -> {
                    list.removeAllViews();
                    String q = search.getText().toString().toLowerCase().trim();
                    int shown = 0;
                    for (String pkg : allPkgs) {
                        if (!q.isEmpty() && !pkg.toLowerCase().contains(q)) continue;
                        if (shown++ >= 80) break;
                        CheckBox cb = new CheckBox(this);
                        cb.setText(pkg);
                        cb.setTextSize(12.5f);
                        cb.setTextColor(theme.onSurface);
                        cb.setChecked(selected.contains(pkg));
                        cb.setOnCheckedChangeListener((b, ch) -> {
                            if (ch) selected.add(pkg);
                            else selected.remove(pkg);
                        });
                        list.addView(cb);
                    }
                };
                search.addTextChangedListener(new TextWatcher() {
                    public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
                    public void onTextChanged(CharSequence s, int a, int b, int c) {}
                    public void afterTextChanged(Editable s) { populate.run(); }
                });
                populate.run();

                new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                    .setTitle("Chọn App nền đóng băng (An toàn View/DeX)")
                    .setView(body)
                    .setPositiveButton("Lưu (" + selected.size() + ")", (d, w) -> {
                        StringBuilder sb = new StringBuilder();
                        for (String s : selected) {
                            if (sb.length() > 0) sb.append('\n');
                            sb.append(s);
                        }
                        runAction("freezer", "set-b64", RustBridge.encodeB64(sb.toString()));
                        loadFreezerAsync();
                    })
                    .setNegativeButton("Hủy", null)
                    .show();
            });
        });
    }

    private String resolveAppLabel(PackageManager pm, String pkg) {
        if (pm == null || pkg == null || pkg.isEmpty()) return pkg == null ? "" : pkg;
        try {
            ApplicationInfo ai = pm.getApplicationInfo(pkg, 0);
            CharSequence cs = pm.getApplicationLabel(ai);
            if (cs != null && cs.length() > 0) return cs.toString();
        } catch (Exception ignored) {
        }
        return pkg;
    }

    private void showSpoofDenylistPickerDialog() {
        toast("Đang tải danh sách ứng dụng...");
        runBg(() -> {
            Map<String, Object> dl = JsonLite.asMap(RustBridge.call("spoof", "denylist"));
            spoofDenylistData = dl;
            boolean exSettings = JsonLite.bool(engineData, "SPOOF_EXCLUDE_SETTINGS",
                JsonLite.bool(dl, "exclude_settings", true));
            Set<String> selected = new LinkedHashSet<>();
            for (Object o : JsonLite.asList(dl.get("packages"))) {
                String p = String.valueOf(o).trim();
                if (!p.isEmpty()) selected.add(p);
            }

            Map<String, Object> apps = JsonLite.asMap(RustBridge.call("spoof", "apps"));
            List<String> userPkgs = new ArrayList<>();
            List<String> sysPkgs = new ArrayList<>();
            Set<String> seenAll = new HashSet<>();
            for (Object o : JsonLite.asList(apps.get("user_packages"))) {
                String p = String.valueOf(o).trim();
                if (!p.isEmpty() && !"com.kgx.ultimate".equals(p) && seenAll.add(p)) {
                    userPkgs.add(p);
                }
            }
            for (Object o : JsonLite.asList(apps.get("system_packages"))) {
                String p = String.valueOf(o).trim();
                if (!p.isEmpty() && !"com.kgx.ultimate".equals(p) && seenAll.add(p)) {
                    sysPkgs.add(p);
                }
            }

            PackageManager pm = getPackageManager();
            Map<String, String> labels = new HashMap<>();
            for (String p : userPkgs) labels.put(p, resolveAppLabel(pm, p));
            for (String p : sysPkgs) labels.put(p, resolveAppLabel(pm, p));
            for (String p : selected) {
                if (!labels.containsKey(p)) labels.put(p, resolveAppLabel(pm, p));
                if (!seenAll.contains(p)) {
                    seenAll.add(p);
                    userPkgs.add(0, p);
                }
            }

            ui.post(() -> {
                LinearLayout body = new LinearLayout(this);
                body.setOrientation(LinearLayout.VERTICAL);
                body.setBackgroundColor(theme.surface3);
                int p = M3Views.dp(this, 14);
                body.setPadding(p, p, p, p);

                EditText search = styledInput("Tìm tên ứng dụng hoặc package...", "");
                body.addView(search);

                final int[] modeHolder = new int[]{0};
                HorizontalScrollView modeHsv = new HorizontalScrollView(this);
                modeHsv.setHorizontalScrollBarEnabled(false);
                LinearLayout modeRow = rowButtons();
                TextView btnUser = M3Views.button(this, theme, "App người dùng", theme.secondaryContainer, theme.onSecondaryContainer, true, null);
                TextView btnAll = M3Views.button(this, theme, "Tất cả (+Hệ thống)", theme.surface4, theme.onSurfaceVar, true, null);
                TextView btnSel = M3Views.button(this, theme, "Đã chọn (" + selected.size() + ")", theme.surface4, theme.onSurfaceVar, true, null);
                addGap(modeRow, btnUser);
                addGap(modeRow, btnAll);
                addGap(modeRow, btnSel);
                modeHsv.addView(modeRow);
                LinearLayout.LayoutParams mrlp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                mrlp.bottomMargin = M3Views.dp(this, 8);
                body.addView(modeHsv, mrlp);

                LinearLayout list = new LinearLayout(this);
                list.setOrientation(LinearLayout.VERTICAL);
                ScrollView sc = new ScrollView(this);
                sc.addView(list);
                body.addView(sc, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, M3Views.dp(this, 340)));

                AlertDialog dlg = new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                    .setTitle("Spoof Denylist — Chọn app không spoof")
                    .setView(body)
                    .setPositiveButton("Lưu (" + selected.size() + ")", (d, w) -> {
                        StringBuilder sb = new StringBuilder();
                        for (String s : selected) {
                            if (sb.length() > 0) sb.append('\n');
                            sb.append(s);
                        }
                        String b64 = RustBridge.encodeB64(sb.toString());
                        runBg(() -> {
                            Map<String, Object> res = JsonLite.asMap(RustBridge.call("spoof", "denylist-set-b64", b64));
                            boolean ok = !res.containsKey("ok") || JsonLite.bool(res, "ok", true);
                            if (ok) spoofDenylistData = res;
                            ui.post(() -> {
                                if (!ok) toast("Lỗi lưu Denylist: " + JsonLite.str(res, "error", "unknown"));
                                else toast("Đã lưu Spoof Denylist (" + selected.size() + " app)");
                                refreshAll(false);
                                if (currentTab == 2) renderCurrentTab();
                            });
                        });
                    })
                    .setNegativeButton("Hủy", null)
                    .create();

                Runnable updateChips = () -> {
                    int m = modeHolder[0];
                    btnUser.setBackground(M3Views.roundRect(m == 0 ? theme.secondaryContainer : theme.surface4, 0, 0, M3Views.dp(this, 999)));
                    btnUser.setTextColor(m == 0 ? theme.onSecondaryContainer : theme.onSurfaceVar);
                    btnAll.setBackground(M3Views.roundRect(m == 1 ? theme.secondaryContainer : theme.surface4, 0, 0, M3Views.dp(this, 999)));
                    btnAll.setTextColor(m == 1 ? theme.onSecondaryContainer : theme.onSurfaceVar);
                    btnSel.setBackground(M3Views.roundRect(m == 2 ? theme.secondaryContainer : theme.surface4, 0, 0, M3Views.dp(this, 999)));
                    btnSel.setTextColor(m == 2 ? theme.onSecondaryContainer : theme.onSurfaceVar);
                    btnSel.setText("Đã chọn (" + selected.size() + ")");
                    android.widget.Button pos = dlg.getButton(AlertDialog.BUTTON_POSITIVE);
                    if (pos != null) pos.setText("Lưu (" + selected.size() + ")");
                };

                Runnable populate = () -> {
                    updateChips.run();
                    list.removeAllViews();
                    String q = search.getText().toString().toLowerCase().trim();
                    List<String> pool = new ArrayList<>();
                    Set<String> poolSeen = new HashSet<>();
                    for (String s : selected) {
                        if (poolSeen.add(s)) pool.add(s);
                    }
                    if (modeHolder[0] != 2) {
                        for (String u : userPkgs) {
                            if (poolSeen.add(u)) pool.add(u);
                        }
                        if (modeHolder[0] == 1) {
                            for (String s : sysPkgs) {
                                if (poolSeen.add(s)) pool.add(s);
                            }
                        }
                    }

                    int shown = 0;
                    for (String pkg : pool) {
                        String lbl = labels.containsKey(pkg) ? labels.get(pkg) : pkg;
                        if (!q.isEmpty() && !pkg.toLowerCase().contains(q) && !lbl.toLowerCase().contains(q)) continue;
                        if (shown++ >= 120) break;
                        CheckBox cb = new CheckBox(this);
                        String title = lbl.equals(pkg) ? pkg : (lbl + "\n" + pkg);
                        if (exSettings && ("com.android.settings".equals(pkg) || pkg.startsWith("com.android.settings."))) {
                            title += "\n[Đã mặc định không spoof qua công tắc Cài đặt]";
                        }
                        cb.setText(title);
                        cb.setTextSize(12f);
                        cb.setTextColor(theme.onSurface);
                        cb.setChecked(selected.contains(pkg));
                        cb.setOnCheckedChangeListener((b, ch) -> {
                            if (ch) selected.add(pkg);
                            else selected.remove(pkg);
                            updateChips.run();
                        });
                        list.addView(cb);
                    }
                };

                btnUser.setOnClickListener(v -> { modeHolder[0] = 0; populate.run(); });
                btnAll.setOnClickListener(v -> { modeHolder[0] = 1; populate.run(); });
                btnSel.setOnClickListener(v -> { modeHolder[0] = 2; populate.run(); });
                search.addTextChangedListener(new TextWatcher() {
                    public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
                    public void onTextChanged(CharSequence s, int a, int b, int c) {}
                    public void afterTextChanged(Editable s) { populate.run(); }
                });
                dlg.setOnShowListener(d -> populate.run());
                dlg.show();
            });
        });
    }

    private void runAction(String... args) {
        runBg(() -> {
            Map<String, Object> res = JsonLite.asMap(RustBridge.call(args));
            boolean ok = !res.containsKey("ok") || JsonLite.bool(res, "ok", true);
            ui.post(() -> {
                if (!ok) toast("Thất bại: " + JsonLite.str(res, "error", "unknown"));
                else toast("Đã cập nhật (" + args[0] + ")");
                refreshAll(false);
                if ("games".equals(args[0]) && currentTab == 1) {
                    loadGamesAsync();
                }
                if ("spoof".equals(args[0]) || (args.length >= 3 && "SPOOF_EXCLUDE_SETTINGS".equals(args[2]))) {
                    loadSpoofDenylistAsync();
                }
                if (("freezer".equals(args[0]) || (args.length >= 3 && "FREEZER_ENABLED".equals(args[2]))) && currentTab == 3) {
                    loadFreezerAsync();
                }
            });
        });
    }

    private EditText styledInput(String hint, String initial) {
        EditText et = new EditText(this);
        et.setHint(hint);
        et.setText(initial);
        et.setTextColor(theme.onSurface);
        et.setHintTextColor(theme.onSurfaceVar);
        et.setTextSize(12.5f);
        et.setBackground(M3Views.roundRect(theme.surface1, theme.outline, M3Views.dp(this, 1), M3Views.dp(this, 12)));
        int p = M3Views.dp(this, 10);
        et.setPadding(p, p, p, p);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = M3Views.dp(this, 8);
        et.setLayoutParams(lp);
        return et;
    }

    private Spinner makeSpinner(String[] opts, String selected) {
        Spinner sp = new Spinner(this);
        ArrayAdapter<String> ad = new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, opts);
        sp.setAdapter(ad);
        for (int i = 0; i < opts.length; i++) {
            if (opts[i].equals(selected)) {
                sp.setSelection(i);
                break;
            }
        }
        return sp;
    }

    private LinearLayout labeledSpinner(String label, Spinner sp) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.addView(M3Views.subtitle(this, theme, label));
        box.addView(sp);
        return box;
    }
}
