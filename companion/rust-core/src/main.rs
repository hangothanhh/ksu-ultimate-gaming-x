// SPDX-License-Identifier: GPL-3.0-or-later
// KSU Ultimate Gaming X v1.0.0 - Native AArch64 Rust Telemetry, Scene Overlay, Freezer & Daemon Core
// Zero external crate dependencies (pure std + NDK libc FFI).

use std::collections::{BTreeMap, HashMap, HashSet};
use std::env;
use std::ffi::{CStr, CString};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::os::raw::c_char;
use std::path::Path;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[repr(C)]
struct Timespec {
    tv_sec: i64,
    tv_nsec: i64,
}

const CLOCK_MONOTONIC: i32 = 1;
const PRIO_PROCESS: i32 = 0;

extern "C" {
    fn __system_property_get(name: *const c_char, value: *mut c_char) -> i32;
    fn clock_gettime(clk_id: i32, tp: *mut Timespec) -> i32;
    fn chmod(path: *const c_char, mode: u32) -> i32;
    fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize;
    fn kill(pid: i32, sig: i32) -> i32;
    fn setpriority(which: i32, who: u32, prio: i32) -> i32;
}

fn native_chmod(path: &str, mode: u32) {
    if let Ok(c_path) = CString::new(path) {
        unsafe {
            chmod(c_path.as_ptr(), mode);
        }
    }
}

fn now_monotonic_ns() -> i64 {
    let mut ts = Timespec { tv_sec: 0, tv_nsec: 0 };
    let rc = unsafe { clock_gettime(CLOCK_MONOTONIC, &mut ts) };
    if rc == 0 {
        ts.tv_sec.saturating_mul(1_000_000_000).saturating_add(ts.tv_nsec)
    } else {
        0
    }
}

static STOP_DAEMON: AtomicBool = AtomicBool::new(false);
static HW_HEAL_TRIED: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_stop_signal(_sig: i32) {
    STOP_DAEMON.store(true, Ordering::Relaxed);
}

fn load_hw_profile_healed(moddir: &str, datadir: &str) -> HashMap<String, String> {
    let path = format!("{datadir}/state/hw_profile.env");
    let hw = parse_env_file(&path);
    let max_hz = hw.get("DISPLAY_MAX_HZ").and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
    if max_hz <= 60 && !HW_HEAL_TRIED.swap(true, Ordering::Relaxed) && get_prop("sys.boot_completed") == "1" {
        let _ = call_kgxctl(moddir, &["hw"]);
        return parse_env_file(&path);
    }
    hw
}

fn now_epoch_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn get_prop(name: &str) -> String {
    let Ok(c_name) = CString::new(name) else {
        return String::new();
    };
    let mut buf = [0u8; 96];
    let len = unsafe { __system_property_get(c_name.as_ptr(), buf.as_mut_ptr() as *mut c_char) };
    if len <= 0 {
        return String::new();
    }
    unsafe { CStr::from_ptr(buf.as_ptr() as *const c_char) }
        .to_string_lossy()
        .trim_end_matches(|c| c == '\r' || c == '\n')
        .to_string()
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 8);
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\t' => out.push_str("\\t"),
            '\r' => {}
            '\n' => out.push_str("\\n"),
            c if (c as u32) < 0x20 => {}
            c => out.push(c),
        }
    }
    out
}

fn read_trimmed(path: &str) -> String {
    fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .next()
        .unwrap_or("")
        .trim_end_matches('\r')
        .trim()
        .to_string()
}

fn read_u64_digits(path: &str) -> u64 {
    let s = read_trimmed(path);
    let digits: String = s.chars().filter(|c| c.is_ascii_digit()).collect();
    digits.parse::<u64>().unwrap_or(0)
}

fn parse_env_file(path: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let Ok(txt) = fs::read_to_string(path) else {
        return map;
    };
    for raw in txt.lines() {
        let line = raw.trim_end_matches('\r').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            let mut val = v.trim().to_string();
            if val.len() >= 2 && val.starts_with('\'') && val.ends_with('\'') {
                val = val[1..val.len() - 1].to_string();
            }
            map.insert(k.trim().to_string(), val);
        }
    }
    map
}

fn load_config(moddir: &str, datadir: &str) -> HashMap<String, String> {
    let mut cfg = HashMap::new();
    let defaults = [
        ("AUTO_OPTIMIZE", "1"),
        ("SAFE_MODE", "0"),
        ("SPOOF_ENABLED", "1"),
        ("PLAY_INTEGRITY_SHIELD", "1"),
        ("SPOOF_EXCLUDE_SETTINGS", "1"),
        ("GLOBAL_SPOOF_PROFILE", "realme_14_5g"),
        ("DEFAULT_MODE", "high_performance"),
        ("FPS_ENGINE_ENABLED", "1"),
        ("DISPLAY_AUTO_HZ", "1"),
        ("TOUCH_OPT_ENABLED", "1"),
        ("RAM_OPT_ENABLED", "1"),
        ("THERMAL_GUARD_ENABLED", "1"),
        ("THERMAL_UNLOCK", "0"),
        ("SUSTAINED_SWEET_SPOT", "0"),
        ("MAX_CLOCK_LOCK", "0"),
        ("SOFT_THERMAL_STEP", "0"),
        ("GOS_NEUTRALIZE", "0"),
        ("EXT_DISPLAY_SCREEN_OFF", "0"),
        ("RES_OVERRIDE_ENABLED", "0"),
        ("RES_OVERRIDE_SCOPE", "ext_scrcpy"),
        ("RES_OVERRIDE_PRESET", "1080x1920"),
        ("RES_OVERRIDE_DENSITY", "auto"),
        ("FREEZER_ENABLED", "0"),
        ("THERMAL_ALERT_ENABLED", "1"),
        ("THERMAL_ALERT_BATT_C", "44"),
        ("THERMAL_ALERT_CPU_C", "92"),
        ("THERMAL_ALERT_ACTION", "notify"),
        ("BYPASS_CHARGING", "0"),
        ("BYPASS_MIN_PCT", "80"),
        ("THERMAL_WARN_BATT", "38"),
        ("THERMAL_HOT_BATT", "41"),
        ("THERMAL_CRIT_BATT", "44"),
        ("THERMAL_WARN_CPU", "68"),
        ("THERMAL_HOT_CPU", "76"),
        ("THERMAL_CRIT_CPU", "85"),
        ("NET_OPT_ENABLED", "1"),
        ("NET_WIFI_LOW_LATENCY", "1"),
        ("NET_PING_HOST", "1.1.1.1"),
        ("POLL_INTERVAL_ACTIVE", "2"),
        ("POLL_INTERVAL_IDLE", "3"),
        ("EXIT_DEBOUNCE_SEC", "3"),
        ("KEEP_BACKUPS_ON_UNINSTALL", "0"),
    ];
    for (k, v) in defaults {
        cfg.insert(k.to_string(), v.to_string());
    }
    for path in [
        format!("{moddir}/data/default_global.conf"),
        format!("{datadir}/config/global.conf"),
    ] {
        for (k, v) in parse_env_file(&path) {
            if cfg.contains_key(&k) {
                cfg.insert(k, v);
            }
        }
    }
    cfg
}

fn cfg_int(cfg: &HashMap<String, String>, k: &str, def: i64) -> i64 {
    cfg.get(k).and_then(|v| v.parse::<i64>().ok()).unwrap_or(def)
}

fn cfg_bool(cfg: &HashMap<String, String>, k: &str) -> bool {
    cfg.get(k).map(|v| v == "1").unwrap_or(false)
}

fn normalize_temp_c(raw: &str) -> i64 {
    let cleaned: String = raw
        .split('.')
        .next()
        .unwrap_or("")
        .chars()
        .filter(|c| c.is_ascii_digit() || *c == '-')
        .collect();
    if cleaned.is_empty() {
        return 0;
    }
    let val = cleaned.parse::<i64>().unwrap_or(0);
    if val >= 10000 || val <= -10000 {
        val / 1000
    } else if val >= 150 {
        val / 10
    } else {
        val
    }
}

fn freq_to_mhz(v: u64) -> u64 {
    if v >= 10_000_000 {
        v / 1_000_000
    } else if v >= 10_000 {
        v / 1_000
    } else {
        v
    }
}

fn read_cpu_usage_pct(datadir: &str, proc_root: &str, prev_name: &str) -> u64 {
    let Ok(txt) = fs::read_to_string(format!("{proc_root}/stat")) else {
        return 0;
    };
    let Some(first) = txt.lines().find(|l| l.starts_with("cpu ")) else {
        return 0;
    };
    let parts: Vec<&str> = first.split_whitespace().collect();
    if parts.len() < 5 {
        return 0;
    }
    let mut cur_tot = 0u64;
    for tok in &parts[1..] {
        cur_tot += tok.parse::<u64>().unwrap_or(0);
    }
    let cur_idle = parts.get(4).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0)
        + parts.get(5).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);

    let state_dir = format!("{datadir}/state");
    let _ = fs::create_dir_all(&state_dir);
    let prev_path = format!("{state_dir}/{prev_name}");
    let prev_str = read_trimmed(&prev_path);
    let mut pct = 0u64;
    if let Some((pt, pi)) = prev_str.split_once(' ') {
        let prev_tot = pt.trim().parse::<u64>().unwrap_or(0);
        let prev_idle = pi.trim().parse::<u64>().unwrap_or(0);
        if prev_tot > 0 && cur_tot > prev_tot {
            let dt = cur_tot - prev_tot;
            let di = cur_idle.saturating_sub(prev_idle);
            if dt > di {
                pct = (((dt - di) * 100) / dt).clamp(0, 100);
            }
        }
    }
    let tmp = format!("{prev_path}.tmp");
    if fs::write(&tmp, format!("{cur_tot} {cur_idle}\n")).is_ok() {
        let _ = fs::rename(&tmp, &prev_path);
    }
    pct
}

fn read_first_num_clamped(path: &str) -> Option<u64> {
    let raw = read_trimmed(path);
    if raw.is_empty() {
        return None;
    }
    for tok in raw.split_whitespace() {
        let clean: String = tok
            .chars()
            .take_while(|c| c.is_ascii_digit())
            .collect();
        if let Ok(v) = clean.parse::<u64>() {
            return Some(v.clamp(0, 100));
        }
    }
    None
}

fn read_cpu_gpu_json(
    datadir: &str,
    sys_root: &str,
    proc_root: &str,
    hw: &HashMap<String, String>,
    stat_slot: &str,
) -> (String, u64, u64, u64, u64) {
    let pols_str = hw.get("CPU_POLICIES").cloned().unwrap_or_default();
    let mut pols: Vec<String> = pols_str.split_whitespace().map(|s| s.to_string()).collect();
    if pols.is_empty() {
        if let Ok(rd) = fs::read_dir(format!("{sys_root}/devices/system/cpu/cpufreq")) {
            for ent in rd.flatten() {
                let name = ent.file_name().to_string_lossy().to_string();
                if name.starts_with("policy") {
                    pols.push(name);
                }
            }
            pols.sort();
        }
    }

    let cpu_pct = read_cpu_usage_pct(datadir, proc_root, stat_slot);
    let mut max_cpu_mhz = 0u64;
    let mut clusters = Vec::new();
    for pol in pols {
        let p = format!("{sys_root}/devices/system/cpu/cpufreq/{pol}");
        if !Path::new(&p).is_dir() {
            continue;
        }
        let cur = read_u64_digits(&format!("{p}/scaling_cur_freq")) / 1000;
        let minf = read_u64_digits(&format!("{p}/scaling_min_freq")) / 1000;
        let maxf = read_u64_digits(&format!("{p}/scaling_max_freq")) / 1000;
        if cur > max_cpu_mhz {
            max_cpu_mhz = cur;
        }
        let gov = read_trimmed(&format!("{p}/scaling_governor"));
        let gov_out = if gov.is_empty() { "unknown" } else { gov.as_str() };
        clusters.push(format!(
            "{{\"policy\":\"{}\",\"gov\":\"{}\",\"cur_mhz\":{},\"min_mhz\":{},\"max_mhz\":{}}}",
            json_escape(&pol),
            json_escape(gov_out),
            cur,
            minf,
            maxf
        ));
    }

    let mut gpu_cur = 0u64;
    let mut gpu_max = 0u64;
    let mut gpu_gov = String::from("unknown");
    let mut gpu_pct_opt: Option<u64> = None;
    let ex_gpu = hw.get("EXYNOS_GPU_DIR").map(|s| s.as_str()).unwrap_or("");
    let df_gpu = hw.get("GPU_DEVFREQ_DIR").map(|s| s.as_str()).unwrap_or("");
    if !ex_gpu.is_empty() && Path::new(&format!("{ex_gpu}/gpu_clock")).exists() {
        gpu_cur = read_u64_digits(&format!("{ex_gpu}/gpu_clock"));
        gpu_max = read_u64_digits(&format!("{ex_gpu}/gpu_max_clock"));
        let g = read_trimmed(&format!("{ex_gpu}/gpu_governor"));
        if !g.is_empty() {
            gpu_gov = g;
        }
        if gpu_cur == 0 && !df_gpu.is_empty() && Path::new(&format!("{df_gpu}/cur_freq")).exists() {
            gpu_cur = read_u64_digits(&format!("{df_gpu}/cur_freq"));
        }
        gpu_pct_opt = read_first_num_clamped(&format!("{ex_gpu}/gpu_busy"));
    } else if !df_gpu.is_empty() && Path::new(df_gpu).is_dir() {
        gpu_cur = read_u64_digits(&format!("{df_gpu}/cur_freq"));
        gpu_max = read_u64_digits(&format!("{df_gpu}/max_freq"));
        let g = read_trimmed(&format!("{df_gpu}/governor"));
        if !g.is_empty() {
            gpu_gov = g;
        }
        gpu_pct_opt = read_first_num_clamped(&format!("{sys_root}/class/kgsl/kgsl-3d0/gpu_busy_percentage"))
            .or_else(|| read_first_num_clamped(&format!("{df_gpu}/load")));
    }
    let gpu_mhz = freq_to_mhz(gpu_cur);
    let gpu_max_mhz = freq_to_mhz(gpu_max);
    let gpu_pct = gpu_pct_opt.unwrap_or_else(|| {
        if gpu_max_mhz > 0 && gpu_mhz > 0 {
            ((gpu_mhz * 100) / gpu_max_mhz).clamp(0, 100)
        } else {
            0
        }
    });

    let json = format!(
        "{{\"clusters\":[{}],\"cpu_pct\":{},\"gpu_pct\":{},\"gpu_cur_mhz\":{},\"gpu_max_mhz\":{},\"gpu_gov\":\"{}\"}}",
        clusters.join(","),
        cpu_pct,
        gpu_pct,
        gpu_mhz,
        gpu_max_mhz,
        json_escape(&gpu_gov)
    );
    (json, cpu_pct, max_cpu_mhz, gpu_pct, gpu_mhz)
}

fn detect_external_display(sys_root: &str, allow_dumpsys: bool) -> Option<String> {
    let mut saw_hw_node = false;
    if let Ok(rd) = fs::read_dir(format!("{sys_root}/class/drm")) {
        let mut names: Vec<String> = rd
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_string())
            .collect();
        names.sort();
        for name in names {
            if name.contains("eDP") || name.contains("DSI") || name.contains("LVDS") || name.contains("Virtual") {
                continue;
            }
            if !(name.contains("-DP-") || name.contains("-HDMI-") || name.contains("-DVI-") || name.contains("-VGA-")) {
                continue;
            }
            saw_hw_node = true;
            let st = read_trimmed(&format!("{sys_root}/class/drm/{name}/status"));
            if st == "connected" {
                return Some(name);
            }
        }
    }
    let dp_sec = format!("{sys_root}/class/dp_sec");
    if Path::new(&dp_sec).is_dir() {
        saw_hw_node = true;
        if read_trimmed(&format!("{dp_sec}/dex")) == "1" {
            return Some("samsung-dex".to_string());
        }
        let mi = read_trimmed(&format!("{dp_sec}/monitor_info"));
        if !mi.is_empty() && mi != ",0x0,0x0" && mi != "0x0,0x0" {
            return Some("samsung-dp".to_string());
        }
    }
    if saw_hw_node || !allow_dumpsys {
        return None;
    }
    if let Ok(out) = Command::new("dumpsys").arg("display").output() {
        let txt = String::from_utf8_lossy(&out.stdout);
        for line in txt.lines() {
            if line.contains("DisplayDeviceInfo{") && line.contains("type EXTERNAL") && !line.contains("state OFF") {
                if let Some(after) = line.split("DisplayDeviceInfo{\"").nth(1) {
                    if let Some((disp_name, _)) = after.split_once('"') {
                        if !disp_name.is_empty() {
                            return Some(disp_name.to_string());
                        }
                    }
                }
                return Some("EXTERNAL".to_string());
            }
        }
    }
    None
}

struct RamMetrics {
    total_mb: u64,
    avail_mb: u64,
    used_mb: u64,
    used_pct: u64,
    psi_some: String,
    psi_full: String,
    pressure: &'static str,
}

fn read_ram_metrics(proc_root: &str) -> RamMetrics {
    let mut total_kb = 0u64;
    let mut avail_kb = 0u64;
    let mut free_kb = 0u64;

    if let Ok(txt) = fs::read_to_string(format!("{proc_root}/meminfo")) {
        for line in txt.lines() {
            if let Some(rest) = line.strip_prefix("MemTotal:") {
                total_kb = rest.split_whitespace().next().and_then(|s| s.parse().ok()).unwrap_or(0);
            } else if let Some(rest) = line.strip_prefix("MemAvailable:") {
                avail_kb = rest.split_whitespace().next().and_then(|s| s.parse().ok()).unwrap_or(0);
            } else if let Some(rest) = line.strip_prefix("MemFree:") {
                free_kb = rest.split_whitespace().next().and_then(|s| s.parse().ok()).unwrap_or(0);
            }
        }
    }
    if avail_kb == 0 {
        avail_kb = free_kb;
    }

    let total_mb = total_kb / 1024;
    let avail_mb = avail_kb / 1024;
    let used_mb = total_mb.saturating_sub(avail_mb);
    let used_pct = if total_mb > 0 { (used_mb * 100) / total_mb } else { 0 };
    let avail_pct = if total_kb > 0 { (avail_kb * 100) / total_kb } else { 100 };

    let mut psi_some = String::from("0.00");
    let mut psi_full = String::from("0.00");
    if let Ok(txt) = fs::read_to_string(format!("{proc_root}/pressure/memory")) {
        for line in txt.lines() {
            if line.starts_with("some ") {
                for tok in line.split_whitespace() {
                    if let Some(v) = tok.strip_prefix("avg10=") {
                        psi_some = v.to_string();
                        break;
                    }
                }
            } else if line.starts_with("full ") {
                for tok in line.split_whitespace() {
                    if let Some(v) = tok.strip_prefix("avg10=") {
                        psi_full = v.to_string();
                        break;
                    }
                }
            }
        }
    }

    let s_f = psi_some.parse::<f64>().unwrap_or(0.0);
    let f_f = psi_full.parse::<f64>().unwrap_or(0.0);
    let pressure = if avail_pct < 15 || f_f >= 15.0 {
        "CRITICAL"
    } else if avail_pct < 25 || s_f >= 25.0 {
        "HIGH"
    } else if avail_pct < 40 || s_f >= 10.0 {
        "MODERATE"
    } else {
        "LOW"
    };

    RamMetrics { total_mb, avail_mb, used_mb, used_pct, psi_some, psi_full, pressure }
}

fn evaluate_thermal(cfg: &HashMap<String, String>, batt_c: i64, cpu_c: i64, gpu_c: i64, prev: &str) -> (&'static str, i64) {
    if cfg_bool(cfg, "SUSTAINED_SWEET_SPOT") {
        if cpu_c >= 78 || gpu_c >= 76 || batt_c >= 43 {
            return ("SWEET_SPOT_COOL", 144);
        }
        if prev == "SWEET_SPOT_COOL" && (cpu_c > 72 || gpu_c > 70 || batt_c > 41) {
            return ("SWEET_SPOT_COOL", 144);
        }
        return ("SWEET_SPOT", 144);
    }

    if cfg_bool(cfg, "THERMAL_UNLOCK") {
        if cpu_c >= 78 || gpu_c >= 76 || batt_c >= 43 {
            return ("UNLOCKED_COOL", 144);
        }
        if prev == "UNLOCKED_COOL" && (cpu_c > 72 || gpu_c > 70 || batt_c > 41) {
            return ("UNLOCKED_COOL", 144);
        }
        return ("UNLOCKED", 144);
    }

    let wb = cfg_int(cfg, "THERMAL_WARN_BATT", 38);
    let hb = cfg_int(cfg, "THERMAL_HOT_BATT", 41);
    let cb = cfg_int(cfg, "THERMAL_CRIT_BATT", 44);
    let wc = cfg_int(cfg, "THERMAL_WARN_CPU", 68);
    let hc = cfg_int(cfg, "THERMAL_HOT_CPU", 76);
    let cc = cfg_int(cfg, "THERMAL_CRIT_CPU", 85);

    let mut stage = if batt_c >= cb || cpu_c >= cc {
        "CRITICAL"
    } else if batt_c >= hb || cpu_c >= hc {
        "HOT"
    } else if batt_c >= wb || cpu_c >= wc {
        "WARM"
    } else {
        "NORMAL"
    };

    if prev == "CRITICAL" && stage != "CRITICAL" && (batt_c > cb - 2 || cpu_c > cc - 4) {
        stage = "CRITICAL";
    } else if prev == "HOT" && (stage == "WARM" || stage == "NORMAL") && (batt_c > hb - 2 || cpu_c > hc - 4) {
        stage = "HOT";
    } else if prev == "WARM" && stage == "NORMAL" && (batt_c > wb - 2 || cpu_c > wc - 4) {
        stage = "WARM";
    }

    let fps_cap = match stage {
        "CRITICAL" => 60,
        "HOT" => 90,
        _ => 144,
    };
    (stage, fps_cap)
}

fn read_live_fps(sys_root: &str) -> String {
    for node in [
        format!("{sys_root}/class/drm/sde-crtc-0/measured_fps"),
        format!("{sys_root}/class/drm/card0-DSI-1/measured_fps"),
        format!("{sys_root}/class/graphics/fb0/measured_fps"),
    ] {
        let raw = read_trimmed(&node);
        if raw.is_empty() {
            continue;
        }
        for tok in raw.split(|c: char| !c.is_ascii_digit() && c != '.') {
            if let Some(int_part) = tok.split('.').next() {
                if let Ok(v) = int_part.parse::<u64>() {
                    if v > 0 && v <= 240 {
                        return v.to_string();
                    }
                }
            }
        }
    }
    "null".to_string()
}

fn read_live_fps_u64(sys_root: &str) -> Option<u64> {
    read_live_fps(sys_root).parse::<u64>().ok()
}

fn is_sf_chrome_layer(line: &str) -> bool {
    line.starts_with("Background for ")
        || line.starts_with("Bounds for ")
        || line.starts_with("ColorFade")
        || line.starts_with("Dim Layer")
        || line.starts_with("Letterbox")
        || line.contains("LockscreenShortcutBlur")
        || line.contains("NotificationShade")
        || line.contains("StatusBar")
        || line.contains("NavigationBar")
        || line.contains("ScreenDecor")
        || line.contains("Wallpaper")
        || line.contains("SnapshotStartingWindow")
        || line.contains("TaskMotion")
        || line.contains("com.android.systemui")
        || line.contains("InputMethod")
        || line.contains("ShellDropTarget")
        || line.contains("EdgeBackGesture")
        || line.contains("SecondaryHome")
        || line.contains("FloatingRotation")
}

fn extract_pkg_before_slash(line: &str) -> Option<String> {
    let bytes = line.as_bytes();
    for (i, &b) in bytes.iter().enumerate() {
        if b == b'/' {
            let mut start = i;
            while start > 0 {
                let c = bytes[start - 1];
                if c.is_ascii_alphanumeric() || c == b'.' || c == b'_' {
                    start -= 1;
                } else {
                    break;
                }
            }
            let cand = &line[start..i];
            if cand.contains('.')
                && !cand.starts_with("android.")
                && cand.as_bytes().first().is_some_and(|c| c.is_ascii_alphabetic())
            {
                return Some(cand.to_string());
            }
        }
    }
    None
}

fn scan_sf_list(preferred_pkg: &str, skip_self: bool) -> (String, Vec<String>, HashSet<String>) {
    let mut open_pkgs = HashSet::new();
    let Ok(out) = Command::new("dumpsys")
        .args(["SurfaceFlinger", "--list"])
        .output()
    else {
        return (preferred_pkg.to_string(), Vec::new(), open_pkgs);
    };
    let txt = String::from_utf8_lossy(&out.stdout);

    for raw in txt.lines() {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        if let Some(pkg) = extract_pkg_before_slash(line) {
            open_pkgs.insert(pkg);
        }
    }

    let mut det_pkg = preferred_pkg.to_string();
    if det_pkg.is_empty() {
        let mut sv_blast_pkg = String::new();
        let mut sv_pkg = String::new();
        let mut win_pkg = String::new();
        let mut act_pkg = String::new();
        for raw in txt.lines().rev() {
            let line = raw.trim();
            if line.is_empty() || is_sf_chrome_layer(line) {
                continue;
            }
            let is_act_rec = line.starts_with("ActivityRecord{");
            if let Some(pkg) = extract_pkg_before_slash(line) {
                if skip_self && pkg == "com.kgx.ultimate" {
                    continue;
                }
                if !is_act_rec {
                    if line.contains("SurfaceView") && line.contains("(BLAST)") {
                        sv_blast_pkg = pkg;
                        break;
                    }
                    if line.contains("SurfaceView") && sv_pkg.is_empty() {
                        sv_pkg = pkg;
                    } else if win_pkg.is_empty() {
                        win_pkg = pkg;
                    }
                } else if act_pkg.is_empty() {
                    act_pkg = pkg;
                }
            }
        }
        det_pkg = if !sv_blast_pkg.is_empty() {
            sv_blast_pkg
        } else if !sv_pkg.is_empty() {
            sv_pkg
        } else if !win_pkg.is_empty() {
            win_pkg
        } else {
            act_pkg
        };
    }

    if det_pkg.is_empty() {
        return (det_pkg, Vec::new(), open_pkgs);
    }

    let sv1 = format!("SurfaceView[{det_pkg}");
    let sv2 = format!("SurfaceView - {det_pkg}");
    let slash = format!("{det_pkg}/");

    let mut p0_blast: Vec<String> = Vec::new();
    let mut p1_sv: Vec<String> = Vec::new();
    let mut p2_buf: Vec<String> = Vec::new();
    let mut p3_win: Vec<String> = Vec::new();

    for raw in txt.lines().rev() {
        let line = raw.trim();
        if line.is_empty() || is_sf_chrome_layer(line) || line.starts_with("ActivityRecord{") {
            continue;
        }
        let matches_sv = line.contains(&sv1) || line.contains(&sv2) || line.contains(&slash);
        if line.contains("SurfaceView") && line.contains("(BLAST)") && matches_sv {
            p0_blast.push(line.to_string());
        } else if line.contains("SurfaceView") && matches_sv {
            p1_sv.push(line.to_string());
        } else if line.contains(&slash) && line.contains("$_") {
            p2_buf.push(line.to_string());
        } else if line.contains(&slash) {
            p3_win.push(line.to_string());
        }
    }

    let mut cands = Vec::with_capacity(4);
    let mut seen = HashSet::new();
    for bucket in [p0_blast, p1_sv, p2_buf, p3_win] {
        for layer in bucket {
            if seen.insert(layer.clone()) {
                cands.push(layer);
                if cands.len() >= 4 {
                    return (det_pkg, cands, open_pkgs);
                }
            }
        }
    }
    (det_pkg, cands, open_pkgs)
}

fn detect_sf_fg_and_candidates(preferred_pkg: &str, skip_self: bool) -> (String, Vec<String>) {
    let (pkg, cands, _) = scan_sf_list(preferred_pkg, skip_self);
    (pkg, cands)
}

fn detect_sf_fg_and_layer(preferred_pkg: &str, skip_self: bool) -> (String, Option<String>) {
    let (pkg, cands) = detect_sf_fg_and_candidates(preferred_pkg, skip_self);
    (pkg, cands.into_iter().next())
}

fn is_transient_focus_window(line: &str) -> bool {
    line.contains("=null")
        || is_sf_chrome_layer(line)
        || line.contains("VolumeDialog")
        || line.contains("EdgePanel")
        || line.contains("Application Error")
        || line.contains("PopupWindow")
}

fn detect_focused_pkg(moddir: &str, datadir: &str) -> String {
    if let Ok(out) = Command::new("dumpsys").args(["window", "displays"]).output() {
        let txt = String::from_utf8_lossy(&out.stdout);
        let mut candidates: Vec<String> = Vec::new();
        let mut cur_focus = String::new();
        let mut foc_app = String::new();

        for raw in txt.lines() {
            let line = raw.trim();
            if line.starts_with("Display #") {
                let picked = if !cur_focus.is_empty() {
                    cur_focus.clone()
                } else {
                    foc_app.clone()
                };
                if !picked.is_empty() {
                    candidates.push(picked);
                }
                cur_focus.clear();
                foc_app.clear();
            } else if line.starts_with("mCurrentFocus=") && cur_focus.is_empty() {
                if !is_transient_focus_window(line) {
                    if let Some(p) = extract_pkg_before_slash(line) {
                        cur_focus = p;
                    }
                }
            } else if line.starts_with("mFocusedApp=") && foc_app.is_empty() {
                if let Some(p) = extract_pkg_before_slash(line) {
                    foc_app = p;
                }
            }
        }
        let last = if !cur_focus.is_empty() { cur_focus } else { foc_app };
        if !last.is_empty() {
            candidates.push(last);
        }

        if let Some(game_pkg) = candidates.iter().find(|p| should_optimize_pkg(moddir, datadir, p)) {
            return game_pkg.clone();
        }
        if let Some(first) = candidates.into_iter().next() {
            return first;
        }
    }
    scan_sf_list("", false).0
}

fn parse_wxh(wxh: &str) -> Option<(u64, u64)> {
    let (ws, hs) = wxh.trim().split_once('x')?;
    let w = ws.parse::<u64>().ok()?;
    let h = hs.parse::<u64>().ok()?;
    if (480..=3840).contains(&w) && (480..=3840).contains(&h) {
        Some((w, h))
    } else {
        None
    }
}

fn lookup_game_wm_res(datadir: &str, pkg: &str) -> String {
    if pkg.is_empty() {
        return String::new();
    }
    if let Ok(txt) = fs::read_to_string(format!("{datadir}/config/custom_games.tsv")) {
        for raw in txt.lines() {
            let line = raw.trim_end_matches('\r');
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() >= 10 && f[0] == pkg && f[1] == "1" {
                let wres = f[9].trim();
                if wres != "default" && parse_wxh(wres).is_some() {
                    return wres.to_string();
                }
                return String::new();
            }
        }
    }
    String::new()
}

fn capture_orig_res_if_missing(datadir: &str) -> (u64, u64, u64) {
    let orig_path = format!("{datadir}/state/orig_res.env");
    if Path::new(&orig_path).is_file() {
        let map = parse_env_file(&orig_path);
        let ow = map.get("ORIG_W").and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
        let oh = map.get("ORIG_H").and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
        let od = map.get("ORIG_DENS").and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
        if ow >= 480 && oh >= 480 && od >= 120 {
            return (ow, oh, od);
        }
    }
    let mut ow = 1080u64;
    let mut oh = 2340u64;
    let mut od = 480u64;
    if let Ok(out) = Command::new("wm").arg("size").output() {
        for raw in String::from_utf8_lossy(&out.stdout).lines() {
            if let Some(pos) = raw.find("Physical size:") {
                let val = raw[pos + "Physical size:".len()..].trim();
                if let Some((w, h)) = parse_wxh(val) {
                    ow = w;
                    oh = h;
                    break;
                }
            }
        }
    }
    if let Ok(out) = Command::new("wm").arg("density").output() {
        for raw in String::from_utf8_lossy(&out.stdout).lines() {
            if let Some(pos) = raw.find("Physical density:") {
                let digits: String = raw[pos + "Physical density:".len()..]
                    .chars()
                    .take_while(|c| c.is_ascii_digit() || c.is_whitespace())
                    .filter(|c| c.is_ascii_digit())
                    .collect();
                if let Ok(d) = digits.parse::<u64>() {
                    if d >= 120 {
                        od = d;
                        break;
                    }
                }
            }
        }
    }
    let _ = fs::create_dir_all(format!("{datadir}/state"));
    let _ = fs::write(&orig_path, format!("ORIG_W='{ow}'\nORIG_H='{oh}'\nORIG_DENS='{od}'\n"));
    (ow, oh, od)
}

fn apply_game_res_fast(datadir: &str, wxh: &str) {
    let Some((w, _)) = parse_wxh(wxh) else {
        return;
    };
    let state_path = format!("{datadir}/state/active_res.env");
    let cur = parse_env_file(&state_path);
    let cur_src = cur.get("ACTIVE_RES_SOURCE").map(|s| s.as_str()).unwrap_or("");
    let cur_res = cur.get("ACTIVE_RES").map(|s| s.as_str()).unwrap_or("");
    if cur_src == "global" || (cur_src == "game" && cur_res == wxh) {
        return;
    }

    let (orig_w, _, orig_d) = capture_orig_res_if_missing(datadir);
    let target_d = ((orig_d * w + orig_w / 2) / orig_w.max(1)).clamp(240, 640);
    let ok = Command::new("wm")
        .args(["size", wxh])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !ok {
        return;
    }
    let _ = Command::new("wm")
        .args(["density", &target_d.to_string()])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
    let _ = fs::create_dir_all(format!("{datadir}/state"));
    let _ = fs::write(
        &state_path,
        format!("ACTIVE_RES='{wxh}'\nACTIVE_DENSITY='{target_d}'\nACTIVE_RES_SOURCE='game'\n"),
    );
}

fn reset_game_res_fast(datadir: &str) {
    let state_path = format!("{datadir}/state/active_res.env");
    if !Path::new(&state_path).is_file() {
        return;
    }
    let cur = parse_env_file(&state_path);
    if cur.get("ACTIVE_RES_SOURCE").map(|s| s.as_str()).unwrap_or("") != "game" {
        return;
    }
    let _ = Command::new("wm")
        .args(["size", "reset"])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
    let _ = Command::new("wm")
        .args(["density", "reset"])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
    let _ = fs::remove_file(&state_path);
}

fn find_top_app_cgroup_node(sys_root: &str) -> Option<String> {
    let dev_root = env::var("KGX_DEV_ROOT").unwrap_or_else(|_| "/dev".to_string());
    for dir in [format!("{dev_root}/cpuctl/top-app"), format!("{sys_root}/fs/cgroup/top-app")] {
        for f in ["cgroup.threads", "tasks"] {
            let p = format!("{dir}/{f}");
            if Path::new(&p).exists() {
                return Some(p);
            }
        }
    }
    None
}

fn cmd_pin_threads(sys_root: &str, proc_root: &str, pid_s: &str, nice_s: &str) {
    let Ok(pid) = pid_s.trim().parse::<u64>() else {
        println!("0");
        return;
    };
    if pid <= 1 {
        println!("0");
        return;
    }
    let rnice = nice_s.trim().parse::<i32>().unwrap_or(-6).clamp(-20, 19);
    let cg_node = find_top_app_cgroup_node(sys_root);
    let Ok(rd) = fs::read_dir(format!("{proc_root}/{pid}/task")) else {
        println!("0");
        return;
    };

    let mut pinned = 0u64;
    for entry in rd.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let Ok(tid) = name.parse::<u32>() else {
            continue;
        };
        let Ok(comm) = fs::read_to_string(format!("{proc_root}/{pid}/task/{name}/comm")) else {
            continue;
        };
        let lower = comm.trim().to_ascii_lowercase();
        let is_render = lower.contains("renderthread")
            || lower.contains("unitymain")
            || lower.contains("unitygfx")
            || lower.contains("gamethread")
            || lower.contains("rhithread")
            || lower.contains("renderworker")
            || lower.contains("asyncrender")
            || lower.contains("glthread")
            || lower.contains("vulkan");
        if !is_render {
            continue;
        }
        if let Some(ref node) = cg_node {
            let _ = write_kernel_node(node, &name);
        }
        if rnice != 0 {
            unsafe {
                setpriority(PRIO_PROCESS, tid, rnice);
            }
        }
        pinned += 1;
    }
    println!("{pinned}");
}

fn is_valid_pkg_name(s: &str) -> bool {
    !s.is_empty()
        && s.contains('.')
        && s.as_bytes().first().is_some_and(|c| c.is_ascii_alphabetic())
        && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'_')
}

fn cmd_trim_list(moddir: &str, proc_root: &str, active_pkg: &str, max_cnt: usize) {
    let mut protected: HashSet<String> = HashSet::new();
    if let Ok(txt) = fs::read_to_string(format!("{moddir}/data/protected_pkgs.list")) {
        for raw in txt.lines() {
            let line = raw.trim();
            if !line.is_empty() && !line.starts_with('#') {
                protected.insert(line.to_string());
            }
        }
    }

    let Ok(rd) = fs::read_dir(proc_root) else {
        return;
    };
    let mut seen: HashSet<String> = HashSet::new();
    let mut out: Vec<String> = Vec::with_capacity(max_cnt);
    for entry in rd.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.is_empty() || !name.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let Ok(raw) = fs::read(format!("{proc_root}/{name}/cmdline")) else {
            continue;
        };
        let end = raw.iter().position(|&b| b == 0).unwrap_or(raw.len());
        let first = String::from_utf8_lossy(&raw[..end]);
        let pkg = first.split(':').next().unwrap_or("").trim();
        if !is_valid_pkg_name(pkg) || pkg == active_pkg || protected.contains(pkg) {
            continue;
        }
        let lower = pkg.to_ascii_lowercase();
        if pkg == "android"
            || pkg == "com.kgx.ultimate"
            || pkg.starts_with("com.android.")
            || pkg.starts_with("com.google.android.gms")
            || pkg.starts_with("com.google.android.gsf")
            || pkg.starts_with("me.weishu.kernelsu")
            || pkg.starts_with("com.rifsxd.ksunext")
            || pkg.starts_with("me.bmax.apatch")
            || pkg.starts_with("com.topjohnwu.magisk")
            || lower.contains("inputmethod")
            || lower.contains("launcher")
            || lower.contains("telecom")
            || lower.contains("systemui")
        {
            continue;
        }
        if let Some(adj) = read_i64_signed(&format!("{proc_root}/{name}/oom_score_adj")) {
            if adj <= 300 {
                continue;
            }
        }
        if seen.insert(pkg.to_string()) {
            out.push(pkg.to_string());
            if out.len() >= max_cnt {
                break;
            }
        }
    }
    for pkg in out {
        println!("{pkg}");
    }
}

fn compute_fps_from_timestamps(ts_list: &[i64], mono_ns: i64) -> Option<(u64, u64)> {
    if ts_list.len() < 5 {
        return None;
    }
    let max_ts = *ts_list.iter().max()?;
    if mono_ns > 0 {
        if mono_ns.saturating_sub(max_ts) > 2_500_000_000
            || max_ts.saturating_sub(mono_ns) > 1_000_000_000
        {
            return None;
        }
    }
    let mut all_deltas = Vec::with_capacity(ts_list.len());
    let mut recent_deltas = Vec::with_capacity(ts_list.len());
    let mut prev = ts_list[0];
    for &cur in &ts_list[1..] {
        if cur > prev {
            let dt = cur - prev;
            if (2_000_000..=500_000_000).contains(&dt) {
                all_deltas.push(dt);
                if max_ts.saturating_sub(cur) <= 2_000_000_000 {
                    recent_deltas.push(dt);
                }
            }
        }
        prev = cur;
    }
    let mut deltas = if recent_deltas.len() >= 4 {
        recent_deltas
    } else {
        all_deltas
    };
    if deltas.len() < 4 {
        return None;
    }
    let sum_dt: f64 = deltas.iter().map(|&d| d as f64).sum();
    let mean_dt = sum_dt / (deltas.len() as f64);
    let avg = ((1_000_000_000.0 / mean_dt).round() as i64).clamp(1, 240) as u64;

    deltas.sort_unstable_by(|a, b| b.cmp(a));
    let k = (deltas.len() / 100).max(1);
    let slow_mean = deltas[..k].iter().map(|&d| d as f64).sum::<f64>() / (k as f64);
    let low1 = ((1_000_000_000.0 / slow_mean).round() as i64).clamp(1, avg as i64) as u64;
    Some((avg, low1))
}

fn read_fps_latency_for_layer(layer: &str, mono_ns: i64) -> (Option<u64>, Option<u64>, &'static str) {
    let Ok(out) = Command::new("dumpsys")
        .args(["SurfaceFlinger", "--latency", layer])
        .output()
    else {
        return (None, None, "none");
    };
    let txt = String::from_utf8_lossy(&out.stdout);
    let mut c0 = Vec::with_capacity(128);
    let mut c1 = Vec::with_capacity(128);
    let mut c2 = Vec::with_capacity(128);
    let max_valid = i64::MAX / 2;
    for (idx, raw) in txt.lines().enumerate() {
        if idx == 0 {
            continue;
        }
        let cols: Vec<&str> = raw.split_whitespace().collect();
        if cols.len() < 3 {
            continue;
        }
        if let Ok(ts) = cols[0].parse::<i64>() {
            if ts > 0 && ts < max_valid {
                c0.push(ts);
            }
        }
        if let Ok(ts) = cols[1].parse::<i64>() {
            if ts > 0 && ts < max_valid {
                c1.push(ts);
            }
        }
        if let Ok(ts) = cols[2].parse::<i64>() {
            if ts > 0 && ts < max_valid {
                c2.push(ts);
            }
        }
    }
    if let Some((avg, low1)) = compute_fps_from_timestamps(&c1, mono_ns) {
        return (Some(avg), Some(low1), "surfaceflinger");
    }
    if let Some((avg, low1)) = compute_fps_from_timestamps(&c2, mono_ns) {
        return (Some(avg), Some(low1), "sf_ready");
    }
    if let Some((avg, low1)) = compute_fps_from_timestamps(&c0, mono_ns) {
        return (Some(avg), Some(low1), "sf_desired");
    }
    (None, None, "none")
}

fn read_sf_pageflip_count() -> Option<u32> {
    let out = Command::new("service")
        .args(["call", "SurfaceFlinger", "1013"])
        .output()
        .ok()?;
    let txt = String::from_utf8_lossy(&out.stdout);
    let pos = txt.find("Parcel(")?;
    let tok = txt[pos + 7..].split_whitespace().next()?;
    if tok.is_empty() || !tok.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    u32::from_str_radix(tok, 16).ok()
}

fn compute_flip_fps(df: u64, dt_ns: i64) -> Option<u64> {
    if df > 0 && (200_000_000..=10_000_000_000).contains(&dt_ns) {
        let fps = ((df as f64) * 1_000_000_000.0 / (dt_ns as f64)).round() as i64;
        if fps >= 1 {
            return Some(fps.clamp(1, 240) as u64);
        }
    }
    None
}

fn read_fps_sf_pageflip(datadir: &str, slot: &str, mono_ns: i64) -> Option<u64> {
    let cur_cnt = read_sf_pageflip_count()?;
    let ts_ns = if mono_ns > 0 {
        mono_ns
    } else {
        (now_epoch_secs() as i64).saturating_mul(1_000_000_000)
    };
    let state_dir = format!("{datadir}/state");
    let _ = fs::create_dir_all(&state_dir);
    let ppath = format!("{state_dir}/sf_flip_{slot}.prev");
    let prev_raw = read_trimmed(&ppath);

    let tmp = format!("{ppath}.tmp");
    if fs::write(&tmp, format!("{ts_ns} {cur_cnt}\n")).is_ok() {
        let _ = fs::rename(&tmp, &ppath);
    }

    let (p_ns_s, p_cnt_s) = prev_raw.split_once(' ')?;
    let prev_ns = p_ns_s.trim().parse::<i64>().ok()?;
    let prev_cnt = p_cnt_s.trim().parse::<u32>().ok()?;
    compute_flip_fps(cur_cnt.wrapping_sub(prev_cnt) as u64, ts_ns - prev_ns)
}

fn read_active_display_flips() -> Option<(String, u64)> {
    let mut child = Command::new("dumpsys")
        .arg("SurfaceFlinger")
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .ok()?;
    let stdout = child.stdout.take()?;
    let mut reader = BufReader::new(stdout);
    let mut line = String::new();

    let mut devs: Vec<(String, bool, bool, bool, u64)> = Vec::new();
    let mut in_dev = false;
    let mut cur_id = String::new();
    let mut cur_primary = false;
    let mut cur_virtual = false;
    let mut cur_on = false;
    let mut cur_flips = 0u64;

    loop {
        line.clear();
        let Ok(n) = reader.read_line(&mut line) else {
            break;
        };
        if n == 0 {
            break;
        }
        let t = line.trim();
        if (in_dev || !devs.is_empty())
            && (t.starts_with("EGL_") || t.contains("HWC layers:") || t.starts_with("Visible layers"))
        {
            break;
        }
        if let Some(rest) = t.strip_prefix("+ DisplayDevice{") {
            if in_dev && !cur_id.is_empty() {
                devs.push((cur_id.clone(), cur_primary, cur_virtual, cur_on, cur_flips));
            }
            cur_id = rest
                .split(|c| c == ',' || c == '}')
                .next()
                .unwrap_or("")
                .trim()
                .to_string();
            cur_primary = t.contains(", primary");
            cur_virtual = t.contains(", virtual");
            cur_on = false;
            cur_flips = 0;
            in_dev = true;
            continue;
        }
        if in_dev {
            if t.contains("powerMode=On") {
                cur_on = true;
            }
            if t.contains("isVirtual=true") {
                cur_virtual = true;
            }
            if let Some(pos) = t.find("flips=") {
                let digits: String = t[pos + 6..]
                    .chars()
                    .take_while(|c| c.is_ascii_digit())
                    .collect();
                if let Ok(v) = digits.parse::<u64>() {
                    cur_flips = v;
                }
            }
        }
    }
    if in_dev && !cur_id.is_empty() {
        devs.push((cur_id, cur_primary, cur_virtual, cur_on, cur_flips));
    }

    drop(reader);
    let _ = child.kill();
    let _ = child.wait();

    let chosen = devs
        .iter()
        .find(|d| !d.1 && d.3 && d.4 > 0)
        .or_else(|| devs.iter().find(|d| d.3 && d.4 > 0))?;
    Some((chosen.0.clone(), chosen.4))
}

fn read_fps_sf_display_flips(datadir: &str, slot: &str, mono_ns: i64) -> Option<u64> {
    let (disp_id, cur_flips) = read_active_display_flips()?;
    let ts_ns = if mono_ns > 0 {
        mono_ns
    } else {
        (now_epoch_secs() as i64).saturating_mul(1_000_000_000)
    };
    let state_dir = format!("{datadir}/state");
    let _ = fs::create_dir_all(&state_dir);
    let ppath = format!("{state_dir}/sf_vflip_{slot}.prev");
    let prev_raw = read_trimmed(&ppath);

    let tmp = format!("{ppath}.tmp");
    if fs::write(&tmp, format!("{ts_ns} {disp_id} {cur_flips}\n")).is_ok() {
        let _ = fs::rename(&tmp, &ppath);
    }

    let mut parts = prev_raw.split_whitespace();
    let prev_ns = parts.next()?.parse::<i64>().ok()?;
    let prev_id = parts.next()?;
    let prev_flips = parts.next()?.parse::<u64>().ok()?;
    if prev_id != disp_id {
        return None;
    }
    compute_flip_fps(cur_flips.saturating_sub(prev_flips), ts_ns - prev_ns)
}

fn read_fps_surfaceflinger_ex(
    datadir: &str,
    pkg: &str,
    sys_root: &str,
    flip_slot: Option<&str>,
) -> (Option<u64>, Option<u64>, &'static str) {
    if let Some(v) = read_live_fps_u64(sys_root) {
        return (Some(v), None, "drm");
    }
    let mono_ns = now_monotonic_ns();
    if !pkg.is_empty() {
        let (_, cands) = detect_sf_fg_and_candidates(pkg, false);
        for cand in cands.iter().take(3) {
            let (live, low1, src) = read_fps_latency_for_layer(cand, mono_ns);
            if live.is_some() {
                return (live, low1, src);
            }
        }
    }
    if let Some(slot) = flip_slot {
        if let Some(v) = read_fps_sf_pageflip(datadir, slot, mono_ns) {
            return (Some(v), None, "sf_flip");
        }
        if let Some(v) = read_fps_sf_display_flips(datadir, slot, mono_ns) {
            return (Some(v), None, "sf_vflip");
        }
    }
    (None, None, "none")
}

fn read_cached_or_live_fps(datadir: &str, sys_root: &str, pkg: &str, sess_active: bool) -> (Option<u64>, Option<u64>, String) {
    let fpath = format!("{datadir}/state/live_fps.env");
    let map = parse_env_file(&fpath);
    if !map.is_empty() {
        let ts = map.get("FPS_TS").and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
        if now_epoch_secs().saturating_sub(ts) <= 6 {
            let live = map.get("LIVE_FPS").and_then(|s| s.parse::<u64>().ok());
            let low1 = map.get("LOW1_FPS").and_then(|s| s.parse::<u64>().ok());
            let src = map.get("FPS_SRC").cloned().unwrap_or_else(|| "none".to_string());
            if live.is_some() {
                return (live, low1, src);
            }
        }
    }
    if sess_active && !pkg.is_empty() {
        let (live, low1, src) = read_fps_surfaceflinger_ex(datadir, pkg, sys_root, None);
        return (live, low1, src.to_string());
    }
    if let Some(v) = read_live_fps_u64(sys_root) {
        return (Some(v), None, "drm".to_string());
    }
    (None, None, "none".to_string())
}

fn resolve_bypass_node(hw: &HashMap<String, String>, sys_root: &str) -> String {
    if let Some(n) = hw.get("BYPASS_NODE") {
        if !n.is_empty() && Path::new(n).exists() {
            return n.clone();
        }
    }
    for name in ["batt_slate_mode", "input_suspend", "charging_enabled", "store_mode"] {
        let p = format!("{sys_root}/class/power_supply/battery/{name}");
        if Path::new(&p).exists() {
            return p;
        }
    }
    String::new()
}

fn read_battery_pct(hw: &HashMap<String, String>, sys_root: &str) -> u64 {
    let node = hw
        .get("BATT_CAPACITY_NODE")
        .filter(|s| !s.is_empty())
        .cloned()
        .unwrap_or_else(|| format!("{sys_root}/class/power_supply/battery/capacity"));
    read_u64_digits(&node).min(100)
}

fn read_i64_signed(path: &str) -> Option<i64> {
    let s = read_trimmed(path);
    if s.is_empty() {
        return None;
    }
    let clean: String = s.chars().filter(|c| c.is_ascii_digit() || *c == '-').collect();
    if clean.is_empty() || clean == "-" {
        return None;
    }
    clean.parse::<i64>().ok()
}

fn read_battery_power(hw: &HashMap<String, String>, sys_root: &str) -> (i64, i64, bool) {
    let cur_opt = read_i64_signed(&format!("{sys_root}/class/power_supply/battery/current_now"))
        .or_else(|| read_i64_signed(&format!("{sys_root}/class/power_supply/battery/current_avg")));
    let volt_opt = read_i64_signed(&format!("{sys_root}/class/power_supply/battery/voltage_now"))
        .or_else(|| read_i64_signed(&format!("{sys_root}/class/power_supply/battery/voltage_avg")));

    let mut ma = cur_opt.unwrap_or(0);
    if ma.abs() > 25_000 {
        ma /= 1000;
    }
    let mv = match volt_opt.unwrap_or(3850) {
        v if v > 100_000 => v / 1000,
        v if v > 100 => v,
        _ => 3850,
    };
    let power_mw = (ma.abs().saturating_mul(mv)) / 1000;

    let st_node = hw
        .get("BATT_STATUS_NODE")
        .filter(|s| !s.is_empty())
        .cloned()
        .unwrap_or_else(|| format!("{sys_root}/class/power_supply/battery/status"));
    let st = read_trimmed(&st_node);
    let charging = st == "Charging" || st == "Full";
    (power_mw, ma, charging)
}

fn evaluate_thermal_alert(cfg: &HashMap<String, String>, batt_c: i64, cpu_c: i64) -> (bool, String) {
    if !cfg_bool(cfg, "THERMAL_ALERT_ENABLED") {
        return (false, String::new());
    }
    let batt_lim = cfg_int(cfg, "THERMAL_ALERT_BATT_C", 44).clamp(38, 50);
    let cpu_lim = cfg_int(cfg, "THERMAL_ALERT_CPU_C", 92).clamp(75, 100);
    let mut parts = Vec::new();
    if batt_c >= batt_lim {
        parts.push(format!("Pin {batt_c}°C"));
    }
    if cpu_c >= cpu_lim {
        parts.push(format!("CPU {cpu_c}°C"));
    }
    (!parts.is_empty(), parts.join(" · "))
}

fn read_power_json(cfg: &HashMap<String, String>, hw: &HashMap<String, String>, datadir: &str, sys_root: &str) -> String {
    let bypass_node = resolve_bypass_node(hw, sys_root);
    let supported = !bypass_node.is_empty();
    let enabled = cfg_bool(cfg, "BYPASS_CHARGING");
    let active = Path::new(&format!("{datadir}/state/bypass_active.state")).is_file();
    let min_pct = cfg_int(cfg, "BYPASS_MIN_PCT", 80).clamp(20, 95);
    let batt_pct = read_battery_pct(hw, sys_root);
    let (power_mw, current_ma, charging) = read_battery_power(hw, sys_root);
    format!(
        "{{\"bypass_supported\":{},\"bypass_enabled\":{},\"bypass_active\":{},\"bypass_node\":\"{}\",\"bypass_min_pct\":{},\"battery_pct\":{},\"power_mw\":{},\"current_ma\":{},\"charging\":{}}}",
        supported,
        enabled,
        active,
        json_escape(&bypass_node),
        min_pct,
        batt_pct,
        power_mw,
        current_ma,
        charging
    )
}

fn detect_transport(sys_root: &str) -> &'static str {
    if read_trimmed(&format!("{sys_root}/class/net/wlan0/operstate")) == "up" {
        return "WIFI";
    }
    if let Ok(rd) = fs::read_dir(format!("{sys_root}/class/net")) {
        for ent in rd.flatten() {
            let name = ent.file_name().to_string_lossy().to_string();
            let op = read_trimmed(&format!("{sys_root}/class/net/{name}/operstate"));
            if op == "up" {
                if name.starts_with("wlan") {
                    return "WIFI";
                }
                if name.starts_with("rmnet") || name.starts_with("ccmni") {
                    return "MOBILE";
                }
                if name.starts_with("eth") {
                    return "ETHERNET";
                }
            }
        }
    }
    "NONE"
}

fn cmd_engine_get(moddir: &str, datadir: &str) {
    let cfg = load_config(moddir, datadir);
    println!(
        "{{\"AUTO_OPTIMIZE\":{},\"SAFE_MODE\":{},\"SPOOF_ENABLED\":{},\"PLAY_INTEGRITY_SHIELD\":{},\"SPOOF_EXCLUDE_SETTINGS\":{},\"GLOBAL_SPOOF_PROFILE\":\"{}\",\"DEFAULT_MODE\":\"{}\",\"FPS_ENGINE_ENABLED\":{},\"DISPLAY_AUTO_HZ\":{},\"TOUCH_OPT_ENABLED\":{},\"RAM_OPT_ENABLED\":{},\"THERMAL_GUARD_ENABLED\":{},\"THERMAL_UNLOCK\":{},\"SUSTAINED_SWEET_SPOT\":{},\"MAX_CLOCK_LOCK\":{},\"SOFT_THERMAL_STEP\":{},\"GOS_NEUTRALIZE\":{},\"EXT_DISPLAY_SCREEN_OFF\":{},\"RES_OVERRIDE_ENABLED\":{},\"RES_OVERRIDE_SCOPE\":\"{}\",\"RES_OVERRIDE_PRESET\":\"{}\",\"RES_OVERRIDE_DENSITY\":\"{}\",\"FREEZER_ENABLED\":{},\"THERMAL_ALERT_ENABLED\":{},\"THERMAL_ALERT_BATT_C\":{},\"THERMAL_ALERT_CPU_C\":{},\"THERMAL_ALERT_ACTION\":\"{}\",\"BYPASS_CHARGING\":{},\"BYPASS_MIN_PCT\":{},\"THERMAL_WARN_BATT\":{},\"THERMAL_HOT_BATT\":{},\"THERMAL_CRIT_BATT\":{},\"THERMAL_WARN_CPU\":{},\"THERMAL_HOT_CPU\":{},\"THERMAL_CRIT_CPU\":{},\"NET_OPT_ENABLED\":{},\"NET_WIFI_LOW_LATENCY\":{},\"NET_PING_HOST\":\"{}\",\"KEEP_BACKUPS_ON_UNINSTALL\":{}}}",
        cfg_int(&cfg, "AUTO_OPTIMIZE", 1),
        cfg_int(&cfg, "SAFE_MODE", 0),
        cfg_int(&cfg, "SPOOF_ENABLED", 1),
        cfg_int(&cfg, "PLAY_INTEGRITY_SHIELD", 1),
        cfg_int(&cfg, "SPOOF_EXCLUDE_SETTINGS", 1),
        json_escape(cfg.get("GLOBAL_SPOOF_PROFILE").map(|s| s.as_str()).unwrap_or("realme_14_5g")),
        json_escape(cfg.get("DEFAULT_MODE").map(|s| s.as_str()).unwrap_or("high_performance")),
        cfg_int(&cfg, "FPS_ENGINE_ENABLED", 1),
        cfg_int(&cfg, "DISPLAY_AUTO_HZ", 1),
        cfg_int(&cfg, "TOUCH_OPT_ENABLED", 1),
        cfg_int(&cfg, "RAM_OPT_ENABLED", 1),
        cfg_int(&cfg, "THERMAL_GUARD_ENABLED", 1),
        cfg_int(&cfg, "THERMAL_UNLOCK", 0),
        cfg_int(&cfg, "SUSTAINED_SWEET_SPOT", 0),
        cfg_int(&cfg, "MAX_CLOCK_LOCK", 0),
        cfg_int(&cfg, "SOFT_THERMAL_STEP", 0),
        cfg_int(&cfg, "GOS_NEUTRALIZE", 0),
        cfg_int(&cfg, "EXT_DISPLAY_SCREEN_OFF", 0),
        cfg_int(&cfg, "RES_OVERRIDE_ENABLED", 0),
        json_escape(cfg.get("RES_OVERRIDE_SCOPE").map(|s| s.as_str()).unwrap_or("ext_scrcpy")),
        json_escape(cfg.get("RES_OVERRIDE_PRESET").map(|s| s.as_str()).unwrap_or("1080x1920")),
        json_escape(cfg.get("RES_OVERRIDE_DENSITY").map(|s| s.as_str()).unwrap_or("auto")),
        cfg_int(&cfg, "FREEZER_ENABLED", 0),
        cfg_int(&cfg, "THERMAL_ALERT_ENABLED", 1),
        cfg_int(&cfg, "THERMAL_ALERT_BATT_C", 44),
        cfg_int(&cfg, "THERMAL_ALERT_CPU_C", 92),
        json_escape(cfg.get("THERMAL_ALERT_ACTION").map(|s| s.as_str()).unwrap_or("notify")),
        cfg_int(&cfg, "BYPASS_CHARGING", 0),
        cfg_int(&cfg, "BYPASS_MIN_PCT", 80),
        cfg_int(&cfg, "THERMAL_WARN_BATT", 38),
        cfg_int(&cfg, "THERMAL_HOT_BATT", 41),
        cfg_int(&cfg, "THERMAL_CRIT_BATT", 44),
        cfg_int(&cfg, "THERMAL_WARN_CPU", 68),
        cfg_int(&cfg, "THERMAL_HOT_CPU", 76),
        cfg_int(&cfg, "THERMAL_CRIT_CPU", 85),
        cfg_int(&cfg, "NET_OPT_ENABLED", 1),
        cfg_int(&cfg, "NET_WIFI_LOW_LATENCY", 1),
        json_escape(cfg.get("NET_PING_HOST").map(|s| s.as_str()).unwrap_or("1.1.1.1")),
        cfg_int(&cfg, "KEEP_BACKUPS_ON_UNINSTALL", 0),
    );
}

fn cmd_logs(datadir: &str, count: usize) {
    let path = format!("{datadir}/logs/engine.log");
    let mut ring: Vec<String> = Vec::new();
    if let Ok(f) = File::open(&path) {
        let reader = BufReader::new(f);
        for line in reader.lines().flatten() {
            ring.push(line);
            if ring.len() > count {
                ring.remove(0);
            }
        }
    }
    let items: Vec<String> = ring
        .into_iter()
        .map(|s| format!("\"{}\"", json_escape(&s)))
        .collect();
    println!("{{\"lines\":[{}]}}", items.join(","));
}

fn score_profile(
    pid: &str,
    p_gpu: &str,
    p_tier: i64,
    p_hz: i64,
    gpu_vendor: &str,
    hw_tier: i64,
    max_hz: i64,
    pref_adreno: &str,
    pref_mali: &str,
) -> (i64, &'static str, String) {
    let mut score: i64 = 0;
    let mut reason: String;
    if gpu_vendor == "unknown" {
        score += 30;
        reason = "GPU unknown (neutral)".to_string();
    } else if p_gpu == gpu_vendor {
        score += 50;
        reason = format!("Exact GPU match ({p_gpu})");
    } else if gpu_vendor == "xclipse" {
        if p_gpu == "adreno" && !pref_adreno.is_empty() && pid == pref_adreno {
            score += 30;
            reason = "Exynos Xclipse + game-preferred whitelist profile".to_string();
        } else if p_gpu == "adreno" && p_tier >= 3 {
            score += 20;
            reason = "Exynos Xclipse + flagship whitelist profile".to_string();
        } else {
            score += 10;
            reason = "Exynos Xclipse compatible profile".to_string();
        }
    } else {
        score -= 40;
        reason = format!("GPU_MISMATCH (real={gpu_vendor} vs profile={p_gpu})");
    }

    if !pref_adreno.is_empty() || !pref_mali.is_empty() {
        if (gpu_vendor == "adreno" || gpu_vendor == "xclipse") && pid == pref_adreno {
            score += 35;
            reason.push_str("; Game primary whitelist match");
        } else if gpu_vendor == "mali" && pid == pref_mali {
            score += 35;
            reason.push_str("; Game primary Mali match");
        } else if pid == pref_adreno || pid == pref_mali {
            score += 10;
            reason.push_str("; Game secondary match");
        }
    }

    let td = (p_tier - hw_tier).abs();
    if td == 0 {
        score += 15;
        reason.push_str(&format!("; Tier {p_tier} match"));
    } else if td == 1 {
        score += 8;
        reason.push_str("; Tier within 1");
    }

    if p_hz >= max_hz {
        score += 10;
    } else if p_hz >= 90 {
        score += 5;
    }
    score = score.clamp(0, 100);

    let compat = if p_gpu != gpu_vendor && gpu_vendor != "unknown" && gpu_vendor != "xclipse" {
        "GPU_MISMATCH"
    } else if score >= 70 {
        "OPTIMAL"
    } else if score >= 45 {
        "COMPATIBLE"
    } else {
        "LOW"
    };

    (score, compat, reason)
}

fn cmd_profiles_list(moddir: &str, datadir: &str, pkg: &str) {
    let hw = load_hw_profile_healed(moddir, datadir);
    let gpu_vendor = hw.get("GPU_VENDOR").map(|s| s.as_str()).unwrap_or("unknown");
    let hw_tier = hw.get("HW_TIER").and_then(|s| s.parse::<i64>().ok()).unwrap_or(2);
    let max_hz = hw.get("DISPLAY_MAX_HZ").and_then(|s| s.parse::<i64>().ok()).unwrap_or(60);

    let mut pref_adreno = String::new();
    let mut pref_mali = String::new();
    if !pkg.is_empty() {
        if let Ok(txt) = fs::read_to_string(format!("{moddir}/data/games.tsv")) {
            for line in txt.lines() {
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }
                let f: Vec<&str> = line.split('\t').collect();
                if f.len() >= 11 && f[0] == pkg {
                    pref_adreno = f[6].to_string();
                    pref_mali = f[7].to_string();
                    break;
                }
            }
        }
    }

    let mut items = Vec::new();
    for (is_cust, path) in [
        (true, format!("{datadir}/profiles/custom_profiles.tsv")),
        (false, format!("{moddir}/data/devices.tsv")),
    ] {
        let Ok(txt) = fs::read_to_string(&path) else {
            continue;
        };
        for raw in txt.lines() {
            let line = raw.trim_end_matches('\r');
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() < 15 {
                continue;
            }
            let tier = f[5].parse::<i64>().unwrap_or(2);
            let hz = f[6].parse::<i64>().unwrap_or(120);
            let ram = f[7].parse::<i64>().unwrap_or(12);
            let fp = if f[13] == "-" { "" } else { f[13] };
            let (sc, comp, rsn) = score_profile(f[0], f[4], tier, hz, gpu_vendor, hw_tier, max_hz, &pref_adreno, &pref_mali);

            items.push(format!(
                "{{\"id\":\"{}\",\"label\":\"{}\",\"category\":\"{}\",\"soc_family\":\"{}\",\"gpu_family\":\"{}\",\"tier\":{},\"max_hz\":{},\"ram_gb\":{},\"brand\":\"{}\",\"manufacturer\":\"{}\",\"model\":\"{}\",\"device\":\"{}\",\"product\":\"{}\",\"fingerprint\":\"{}\",\"notes\":\"{}\",\"custom\":{},\"compat_score\":{},\"compat_level\":\"{}\",\"compat_reason\":\"{}\"}}",
                json_escape(f[0]), json_escape(f[1]), json_escape(f[2]),
                json_escape(f[3]), json_escape(f[4]), tier, hz, ram,
                json_escape(f[8]), json_escape(f[9]), json_escape(f[10]),
                json_escape(f[11]), json_escape(f[12]), json_escape(fp),
                json_escape(f[14]), is_cust, sc, json_escape(comp), json_escape(&rsn)
            ));
        }
    }

    println!(
        "{{\"gpu_vendor\":\"{}\",\"hw_tier\":{},\"profiles\":[{}]}}",
        json_escape(gpu_vendor),
        hw_tier,
        items.join(",")
    );
}

fn fps_analysis_inline(datadir: &str, moddir: &str, pkg: &str, req_fps: i64, stage: &str, spoof_active: bool, hw: &HashMap<String, String>) -> String {
    let mut g_emax = 144i64;
    let mut g_ltype = "OPEN".to_string();
    let mut g_gload = "medium".to_string();
    if let Ok(txt) = fs::read_to_string(format!("{moddir}/data/games.tsv")) {
        for line in txt.lines() {
            if line.is_empty() || line.starts_with('#') { continue; }
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() >= 11 && f[0] == pkg {
                g_emax = f[2].parse().unwrap_or(144);
                g_ltype = f[3].to_string();
                g_gload = f[9].to_string();
                break;
            }
        }
    }
    let disp_cap = hw.get("DISPLAY_MAX_HZ").and_then(|s| s.parse::<i64>().ok()).unwrap_or(60);
    let hw_tier = hw.get("HW_TIER").and_then(|s| s.parse::<i64>().ok()).unwrap_or(2);
    let therm_cap = match stage {
        "CRITICAL" => 60,
        "HOT" => 90,
        _ => 144,
    };
    let hw_cap = match (hw_tier, g_gload.as_str()) {
        (1, "extreme") => 60,
        (1, "high") => 90,
        (2, "extreme") => 90,
        (2, "high") => 120,
        (3, "extreme") => 120,
        _ => 144,
    };
    let wl = if g_ltype == "WHITELIST" { 1 } else { 0 };
    let effective = req_fps.min(g_emax).min(disp_cap).min(therm_cap);
    let _ = datadir;

    let (limiter, can_unlock, reason) = if therm_cap < req_fps && effective == therm_cap {
        ("THERMAL_LIMIT", false, format!("Thermal stage {stage} limits target FPS to {therm_cap} FPS."))
    } else if disp_cap < req_fps && disp_cap <= g_emax {
        ("DISPLAY_LIMIT", false, format!("Display max refresh rate is {disp_cap}Hz."))
    } else if req_fps > g_emax && g_ltype == "GAME_CAP" {
        ("GAME_LIMIT", false, format!("Game engine caps Android at {g_emax} FPS."))
    } else if wl == 1 && !spoof_active {
        ("WHITELIST_LIMIT", true, format!("Game gates >60 FPS behind whitelist; enable Device Spoof (up to {effective} FPS)."))
    } else if effective > hw_cap {
        ("HARDWARE_LIMIT", true, format!("GPU/SoC tier {hw_tier} under '{g_gload}' load sustains ~{hw_cap} FPS."))
    } else {
        ("NONE", true, format!("Targeting {effective} FPS within {disp_cap}Hz panel and {stage} thermal budget."))
    };

    format!(
        "{{\"package\":\"{}\",\"requested_fps\":{},\"effective_fps\":{},\"game_engine_cap\":{},\"limit_type\":\"{}\",\"whitelist_gated\":{},\"display_cap\":{},\"hw_sustainable_fps\":{},\"thermal_cap\":{},\"primary_limiter\":\"{}\",\"can_unlock\":{},\"explanation\":\"{}\"}}",
        json_escape(pkg), req_fps, effective, g_emax, json_escape(&g_ltype), wl, disp_cap, hw_cap, therm_cap,
        limiter, can_unlock, json_escape(&reason)
    )
}

fn read_temps_c(hw: &HashMap<String, String>) -> (i64, i64, i64) {
    let batt_node = hw.get("THERMAL_BATT_NODE").map(|s| s.as_str()).unwrap_or("");
    let cpu_node = hw.get("THERMAL_CPU_NODE").map(|s| s.as_str()).unwrap_or("");
    let gpu_node = hw.get("THERMAL_GPU_NODE").map(|s| s.as_str()).unwrap_or("");
    let batt_c = if batt_node.is_empty() { 0 } else { normalize_temp_c(&read_trimmed(batt_node)) };
    let cpu_c = if cpu_node.is_empty() { 0 } else { normalize_temp_c(&read_trimmed(cpu_node)) };
    let mut gpu_c = if gpu_node.is_empty() { 0 } else { normalize_temp_c(&read_trimmed(gpu_node)) };
    if gpu_c == 0 { gpu_c = cpu_c; }
    (batt_c, cpu_c, gpu_c)
}

fn is_freezer_supported(cgroup_root: &str) -> bool {
    let Ok(rd) = fs::read_dir(cgroup_root) else {
        return false;
    };
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().to_string();
        if name.starts_with("uid_") && ent.path().join("cgroup.freeze").is_file() {
            return true;
        }
    }
    false
}

fn cmd_status(moddir: &str, datadir: &str, sys_root: &str, proc_root: &str) {
    let cfg = load_config(moddir, datadir);
    let hw = load_hw_profile_healed(moddir, datadir);
    let sess = parse_env_file(&format!("{datadir}/state/active_session.env"));
    let sp_env = parse_env_file(&format!("{datadir}/state/active_spoof.env"));
    let disp_env = parse_env_file(&format!("{datadir}/state/active_display.env"));
    let res_env = parse_env_file(&format!("{datadir}/state/active_res.env"));

    let d_pid = read_u64_digits(&format!("{datadir}/state/daemon.pid"));
    let d_running = d_pid > 0 && Path::new(&format!("{proc_root}/{d_pid}")).exists();

    let def_mode = cfg.get("DEFAULT_MODE").map(|s| s.as_str()).unwrap_or("high_performance");
    let sess_active = !sess.is_empty();
    let act_pkg = sess.get("ACTIVE_PKG").map(|s| s.as_str()).unwrap_or("");
    let act_name = sess.get("ACTIVE_NAME").map(|s| s.as_str()).unwrap_or("");
    let act_mode = sess.get("ACTIVE_MODE").map(|s| s.as_str()).unwrap_or(def_mode);
    let act_fps = sess.get("ACTIVE_FPS").and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);

    let sp_active = sp_env.get("SPOOF_ACTIVE").map(|s| s == "1").unwrap_or(false);
    let sp_id = sp_env.get("SPOOF_PROFILE_ID").map(|s| s.as_str()).unwrap_or("");
    let sp_label = sp_env.get("SPOOF_LABEL").map(|s| s.as_str()).unwrap_or("");
    let sp_brand = sp_env.get("SPOOF_BRAND").map(|s| s.as_str()).unwrap_or("");
    let sp_model = sp_env.get("SPOOF_MODEL").map(|s| s.as_str()).unwrap_or("");
    let sp_device = sp_env.get("SPOOF_DEVICE").map(|s| s.as_str()).unwrap_or("");

    let (batt_c, cpu_c, gpu_c) = read_temps_c(&hw);

    let prev_stage = read_trimmed(&format!("{datadir}/state/thermal_stage.state"));
    let (therm_stage, therm_fps) = evaluate_thermal(&cfg, batt_c, cpu_c, gpu_c, if prev_stage.is_empty() { "NORMAL" } else { &prev_stage });
    let soft_step_tier = read_trimmed(&format!("{datadir}/state/soft_step.tier")).parse::<u8>().unwrap_or(0);
    let alert_enabled = cfg_bool(&cfg, "THERMAL_ALERT_ENABLED");
    let (alert_hit, alert_msg) = evaluate_thermal_alert(&cfg, batt_c, cpu_c);

    let (cpu_gpu_json, _, _, _, _) = read_cpu_gpu_json(datadir, sys_root, proc_root, &hw, "cpu_stat.prev");
    let ram = read_ram_metrics(proc_root);

    let ext_name_opt = detect_external_display(sys_root, false);
    let ext_connected = ext_name_opt.is_some();
    let ext_name = ext_name_opt.unwrap_or_default();
    let ext_off_enabled = cfg_bool(&cfg, "EXT_DISPLAY_SCREEN_OFF");
    let ext_internal_off = Path::new(&format!("{datadir}/state/ext_internal_off.state")).is_file();

    let res_enabled = cfg_bool(&cfg, "RES_OVERRIDE_ENABLED");
    let res_scope = cfg.get("RES_OVERRIDE_SCOPE").map(|s| s.as_str()).unwrap_or("ext_scrcpy");
    let res_preset = cfg.get("RES_OVERRIDE_PRESET").map(|s| s.as_str()).unwrap_or("1080x1920");
    let res_density = cfg.get("RES_OVERRIDE_DENSITY").map(|s| s.as_str()).unwrap_or("auto");
    let cur_res = res_env.get("ACTIVE_RES").map(|s| s.as_str()).unwrap_or("");
    let cur_res_dens = res_env.get("ACTIVE_DENSITY").map(|s| s.as_str()).unwrap_or("");
    let cur_res_src = res_env.get("ACTIVE_RES_SOURCE").map(|s| s.as_str()).unwrap_or("");
    let res_active = !cur_res.is_empty();

    let cgroup_root = env::var("KGX_CGROUP_ROOT").unwrap_or_else(|_| "/sys/fs/cgroup".to_string());
    let frz_enabled = cfg_bool(&cfg, "FREEZER_ENABLED");
    let frz_sup = is_freezer_supported(&cgroup_root);
    let frozen_count = fs::read_to_string(format!("{datadir}/state/frozen_uids.tsv"))
        .unwrap_or_default()
        .lines()
        .filter(|l| l.contains('\t'))
        .count();
    let target_count = fs::read_to_string(format!("{datadir}/config/freezer_apps.list"))
        .unwrap_or_default()
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .count();

    let max_hz = hw.get("DISPLAY_MAX_HZ").map(|s| s.as_str()).unwrap_or("60");
    let cur_hz = disp_env.get("ACTIVE_DISPLAY_HZ").map(|s| s.as_str()).filter(|s| !s.is_empty()).unwrap_or(max_hz);
    let (live_fps_opt, low1_opt, fps_src) = read_cached_or_live_fps(datadir, sys_root, act_pkg, sess_active);
    let live_fps = live_fps_opt.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string());
    let low1_fps = low1_opt.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string());
    let net_tr = detect_transport(sys_root);
    let power_json = read_power_json(&cfg, &hw, datadir, sys_root);

    let sys_prop_act = Path::new(&format!("{moddir}/system.prop")).is_file();
    let rust_core_act = Path::new(&format!("{moddir}/bin/kgx-core")).is_file();
    let mods_root = env::var("KGX_MODULES_ROOT").unwrap_or_else(|_| "/data/adb/modules".to_string());
    let has_zygisk = ["zygisksu", "rezygisk", "zygisk_lsposed", "neozygisk"].iter().any(|d| {
        let p = format!("{mods_root}/{d}");
        Path::new(&p).is_dir()
            && !Path::new(&format!("{p}/disable")).exists()
            && !Path::new(&format!("{p}/remove")).exists()
    });
    let pi_cfg = cfg_bool(&cfg, "PLAY_INTEGRITY_SHIELD");
    let pi_act = pi_cfg && has_zygisk;
    let sp_ex_set = cfg_bool(&cfg, "SPOOF_EXCLUDE_SETTINGS");
    let sp_deny_cnt = fs::read_to_string(format!("{datadir}/config/spoof_denylist.list"))
        .unwrap_or_default()
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .count();

    let cur_prop_model = get_prop("ro.product.model");
    let cur_prop_mkt = get_prop("ro.product.marketname");

    let fps_json = if !act_pkg.is_empty() {
        fps_analysis_inline(datadir, moddir, act_pkg, act_fps, therm_stage, sp_active, &hw)
    } else {
        "null".to_string()
    };

    let mut real_get = BTreeMap::new();
    for k in [
        "REAL_BRAND", "REAL_MANUFACTURER", "REAL_MODEL", "REAL_DEVICE", "REAL_PRODUCT",
        "SOC_PLATFORM", "GPU_MODEL", "GPU_VENDOR", "SOC_VENDOR", "HW_TIER",
        "REAL_ANDROID_API", "DISPLAY_SUPPORTED_HZ", "TOUCH_GAME_NODE",
        "HAS_RESETPROP", "HAS_CMD_GAME", "HAS_UCLAMP",
    ] {
        real_get.insert(k, hw.get(k).map(|s| s.as_str()).unwrap_or(""));
    }

    let r_brand = if real_get["REAL_BRAND"].is_empty() { get_prop("ro.product.brand") } else { real_get["REAL_BRAND"].to_string() };
    let r_mfg = if real_get["REAL_MANUFACTURER"].is_empty() { get_prop("ro.product.manufacturer") } else { real_get["REAL_MANUFACTURER"].to_string() };
    let r_model = if real_get["REAL_MODEL"].is_empty() { get_prop("ro.product.model") } else { real_get["REAL_MODEL"].to_string() };
    let r_device = if real_get["REAL_DEVICE"].is_empty() { get_prop("ro.product.device") } else { real_get["REAL_DEVICE"].to_string() };
    let r_product = if real_get["REAL_PRODUCT"].is_empty() { get_prop("ro.product.name") } else { real_get["REAL_PRODUCT"].to_string() };
    let hw_tier_n = real_get["HW_TIER"].parse::<i64>().unwrap_or(2);
    let api_n = real_get["REAL_ANDROID_API"].parse::<i64>().unwrap_or(0);
    let exynos_b = real_get["SOC_VENDOR"] == "exynos";

    println!(
        "{{\"module_version\":\"v1.0.0\",\"safe_mode\":{},\"auto_optimize\":{},\"thermal_unlock\":{},\"sustained_sweet_spot\":{},\"max_clock_lock\":{},\"soft_thermal_step\":{},\"gos_neutralize\":{},\"daemon\":{{\"running\":{},\"pid\":{}}},\"ext_display\":{{\"screen_off_enabled\":{},\"connected\":{},\"internal_screen_off\":{},\"external_name\":\"{}\"}},\"res_override\":{{\"enabled\":{},\"scope\":\"{}\",\"preset\":\"{}\",\"density\":\"{}\",\"active\":{},\"current_res\":\"{}\",\"current_density\":\"{}\",\"source\":\"{}\"}},\"freezer\":{{\"enabled\":{},\"supported\":{},\"frozen_count\":{},\"target_count\":{}}},\"power\":{},\"real_device\":{{\"brand\":\"{}\",\"manufacturer\":\"{}\",\"model\":\"{}\",\"device\":\"{}\",\"product\":\"{}\",\"soc\":\"{}\",\"gpu\":\"{}\",\"gpu_vendor\":\"{}\",\"tier\":{},\"api\":{},\"exynos\":{}}},\"spoof\":{{\"active\":{},\"enabled\":{},\"play_integrity_shield\":{},\"play_integrity_shield_active\":{},\"exclude_settings\":{},\"denylist_count\":{},\"global_profile\":\"{}\",\"system_prop_active\":{},\"profile_id\":\"{}\",\"label\":\"{}\",\"brand\":\"{}\",\"model\":\"{}\",\"device\":\"{}\",\"current_prop_model\":\"{}\",\"current_prop_marketname\":\"{}\"}},\"session\":{{\"active\":{},\"package\":\"{}\",\"name\":\"{}\",\"mode\":\"{}\",\"target_fps\":{}}},\"cpu_gpu\":{},\"ram\":{{\"total_mb\":{},\"avail_mb\":{},\"used_mb\":{},\"used_pct\":{},\"psi_some\":\"{}\",\"psi_full\":\"{}\",\"pressure\":\"{}\"}},\"thermal\":{{\"battery_c\":{},\"cpu_c\":{},\"gpu_c\":{},\"stage\":\"{}\",\"thermal_fps_cap\":{},\"soft_step_tier\":{},\"alert_enabled\":{},\"alert\":{},\"alert_msg\":\"{}\"}},\"display\":{{\"current_hz\":{},\"max_hz\":{},\"supported_hz\":\"{}\"}},\"fps\":{{\"live\":{},\"low1\":{},\"source\":\"{}\",\"analysis\":{}}},\"network\":{{\"transport\":\"{}\"}},\"capabilities\":{{\"has_resetprop\":{},\"has_zygisk\":{},\"has_cmd_game\":{},\"has_uclamp\":{},\"rust_core\":{},\"touch_node\":\"{}\"}}}}",
        cfg_bool(&cfg, "SAFE_MODE"),
        cfg_bool(&cfg, "AUTO_OPTIMIZE"),
        cfg_bool(&cfg, "THERMAL_UNLOCK"),
        cfg_bool(&cfg, "SUSTAINED_SWEET_SPOT"),
        cfg_bool(&cfg, "MAX_CLOCK_LOCK"),
        cfg_bool(&cfg, "SOFT_THERMAL_STEP"),
        cfg_bool(&cfg, "GOS_NEUTRALIZE"),
        d_running, d_pid,
        ext_off_enabled, ext_connected, ext_internal_off, json_escape(&ext_name),
        res_enabled, json_escape(res_scope), json_escape(res_preset), json_escape(res_density),
        res_active, json_escape(cur_res), json_escape(cur_res_dens), json_escape(cur_res_src),
        frz_enabled, frz_sup, frozen_count, target_count,
        power_json,
        json_escape(&r_brand), json_escape(&r_mfg), json_escape(&r_model),
        json_escape(&r_device), json_escape(&r_product), json_escape(real_get["SOC_PLATFORM"]),
        json_escape(real_get["GPU_MODEL"]), json_escape(real_get["GPU_VENDOR"]), hw_tier_n, api_n, exynos_b,
        sp_active, cfg_bool(&cfg, "SPOOF_ENABLED"), pi_cfg, pi_act, sp_ex_set, sp_deny_cnt,
        json_escape(cfg.get("GLOBAL_SPOOF_PROFILE").map(|s| s.as_str()).unwrap_or("realme_14_5g")),
        sys_prop_act,
        json_escape(sp_id), json_escape(sp_label), json_escape(sp_brand),
        json_escape(sp_model), json_escape(sp_device),
        json_escape(&cur_prop_model), json_escape(&cur_prop_mkt),
        sess_active, json_escape(act_pkg), json_escape(act_name), json_escape(act_mode), act_fps,
        cpu_gpu_json,
        ram.total_mb, ram.avail_mb, ram.used_mb, ram.used_pct, json_escape(&ram.psi_some), json_escape(&ram.psi_full), ram.pressure,
        batt_c, cpu_c, gpu_c, therm_stage, therm_fps, soft_step_tier, alert_enabled, alert_hit, json_escape(&alert_msg),
        cur_hz, max_hz, json_escape(real_get["DISPLAY_SUPPORTED_HZ"]),
        live_fps, low1_fps, json_escape(&fps_src), fps_json,
        net_tr,
        real_get["HAS_RESETPROP"] == "1",
        has_zygisk,
        real_get["HAS_CMD_GAME"] == "1",
        real_get["HAS_UCLAMP"] == "1",
        rust_core_act,
        json_escape(real_get["TOUCH_GAME_NODE"]),
    );
}

fn cmd_fps(datadir: &str, sys_root: &str, pkg_arg: &str) {
    let sess = parse_env_file(&format!("{datadir}/state/active_session.env"));
    let pkg = if !pkg_arg.is_empty() {
        pkg_arg.to_string()
    } else {
        sess.get("ACTIVE_PKG").cloned().unwrap_or_default()
    };
    let (live_opt, low1_opt, src) = read_fps_surfaceflinger_ex(datadir, &pkg, sys_root, None);
    let live_s = live_opt.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string());
    let low1_s = low1_opt.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string());
    println!(
        "{{\"ok\":true,\"package\":\"{}\",\"live\":{},\"low1\":{},\"source\":\"{}\"}}",
        json_escape(&pkg),
        live_s,
        low1_s,
        src
    );
}

fn cmd_overlay_tick(moddir: &str, datadir: &str, sys_root: &str, proc_root: &str, pkg_arg: &str) {
    let cfg = load_config(moddir, datadir);
    let hw = parse_env_file(&format!("{datadir}/state/hw_profile.env"));
    let sess = parse_env_file(&format!("{datadir}/state/active_session.env"));
    let sess_pkg = sess.get("ACTIVE_PKG").map(|s| s.as_str()).unwrap_or("");
    let pkg_pref = if !pkg_arg.is_empty() {
        pkg_arg.to_string()
    } else {
        sess_pkg.to_string()
    };

    let now = now_epoch_secs();
    let mut pkg = pkg_pref.clone();
    let mut cached_layer = String::new();
    let cache_path = format!("{datadir}/state/ov_layer.cache");
    if let Ok(raw) = fs::read_to_string(&cache_path) {
        let f: Vec<&str> = raw.trim_end_matches(&['\r', '\n'][..]).split('\t').collect();
        if f.len() >= 3 {
            let ts = f[0].parse::<u64>().unwrap_or(0);
            if now.saturating_sub(ts) <= 2 && (pkg_pref.is_empty() || pkg_pref == f[1]) {
                pkg = f[1].to_string();
                cached_layer = f[2].to_string();
            }
        }
    }

    let mut live_opt: Option<u64> = None;
    let mut low1_opt: Option<u64> = None;
    let mut fps_src = String::from("none");
    let fpath = format!("{datadir}/state/live_fps.env");
    if pkg_pref.is_empty() || pkg_pref == sess_pkg {
        let map = parse_env_file(&fpath);
        if !map.is_empty() {
            let ts = map.get("FPS_TS").and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
            if now.saturating_sub(ts) <= 3 {
                if let Some(l) = map.get("LIVE_FPS").and_then(|s| s.parse::<u64>().ok()) {
                    live_opt = Some(l);
                    low1_opt = map.get("LOW1_FPS").and_then(|s| s.parse::<u64>().ok());
                    fps_src = map.get("FPS_SRC").cloned().unwrap_or_else(|| "none".to_string());
                }
            }
        }
    }
    if live_opt.is_none() {
        if let Some(v) = read_live_fps_u64(sys_root) {
            live_opt = Some(v);
            fps_src = String::from("drm");
        } else {
            let mono_ns = now_monotonic_ns();
            let cache_is_none = cached_layer == "__NONE__";
            if !cached_layer.is_empty() && !cache_is_none {
                let (l, l1, src) = read_fps_latency_for_layer(&cached_layer, mono_ns);
                live_opt = l;
                low1_opt = l1;
                fps_src = src.to_string();
            }
            if live_opt.is_none() && !cache_is_none {
                let (det_pkg, cands) = detect_sf_fg_and_candidates(&pkg_pref, true);
                if pkg.is_empty() {
                    pkg = det_pkg;
                }
                let mut won_layer = String::new();
                for cand in cands.iter().take(3) {
                    let (l, l1, src) = read_fps_latency_for_layer(cand, mono_ns);
                    if l.is_some() {
                        live_opt = l;
                        low1_opt = l1;
                        fps_src = src.to_string();
                        won_layer = cand.clone();
                        break;
                    }
                }
                let cache_val = if won_layer.is_empty() { "__NONE__" } else { won_layer.as_str() };
                let _ = fs::create_dir_all(format!("{datadir}/state"));
                let _ = fs::write(&cache_path, format!("{now}\t{pkg}\t{cache_val}\n"));
            }
            if live_opt.is_none() {
                if let Some(v) = read_fps_sf_pageflip(datadir, "ov", mono_ns) {
                    live_opt = Some(v);
                    low1_opt = None;
                    fps_src = String::from("sf_flip");
                } else if let Some(v) = read_fps_sf_display_flips(datadir, "ov", mono_ns) {
                    live_opt = Some(v);
                    low1_opt = None;
                    fps_src = String::from("sf_vflip");
                }
            }
        }
    }

    let (_, cpu_pct, max_cpu_mhz, gpu_pct, gpu_mhz) =
        read_cpu_gpu_json(datadir, sys_root, proc_root, &hw, "cpu_stat_ov.prev");
    let ram = read_ram_metrics(proc_root);
    let (batt_c, cpu_c, gpu_c) = read_temps_c(&hw);
    let batt_pct = read_battery_pct(&hw, sys_root);
    let (power_mw, current_ma, charging) = read_battery_power(&hw, sys_root);
    let soft_step = read_trimmed(&format!("{datadir}/state/soft_step.tier")).parse::<u8>().unwrap_or(0);
    let (thermal_alert, thermal_alert_msg) = evaluate_thermal_alert(&cfg, batt_c, cpu_c);
    let ts = now_epoch_secs();

    let fps_s = live_opt.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string());
    let low1_s = low1_opt.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string());
    println!(
        "{{\"ok\":true,\"ts\":{},\"pkg\":\"{}\",\"fps\":{},\"low1\":{},\"fps_src\":\"{}\",\"cpu_pct\":{},\"cpu_c\":{},\"cpu_mhz\":{},\"gpu_pct\":{},\"gpu_mhz\":{},\"gpu_c\":{},\"ram_used_mb\":{},\"ram_total_mb\":{},\"ram_pct\":{},\"batt_c\":{},\"batt_pct\":{},\"power_mw\":{},\"current_ma\":{},\"charging\":{},\"soft_step\":{},\"thermal_alert\":{},\"thermal_alert_msg\":\"{}\"}}",
        ts,
        json_escape(&pkg),
        fps_s,
        low1_s,
        json_escape(&fps_src),
        cpu_pct,
        cpu_c,
        max_cpu_mhz,
        gpu_pct,
        gpu_mhz,
        gpu_c,
        ram.used_mb,
        ram.total_mb,
        ram.used_pct,
        batt_c,
        batt_pct,
        power_mw,
        current_ma,
        charging,
        soft_step,
        thermal_alert,
        json_escape(&thermal_alert_msg)
    );
}

fn cmd_pi_diag(datadir: &str) {
    let mods_root = env::var("KGX_MODULES_ROOT").unwrap_or_else(|_| "/data/adb/modules".to_string());
    let rz_prop = fs::read_to_string(format!("{mods_root}/rezygisk/module.prop")).unwrap_or_default();
    let mut rz_desc = String::new();
    for line in rz_prop.lines() {
        if let Some(rest) = line.trim_end_matches('\r').strip_prefix("description=") {
            rz_desc = rest.to_string();
            break;
        }
    }
    let state_json = fs::read_to_string("/data/adb/rezygisk/state.json").unwrap_or_default();
    let module_loaded = state_json.contains("ksu_ultimate_gaming_x");
    let socket_ok = Path::new("/data/adb/rezygisk/cp64.sock").exists();
    let zygisk_active = ["zygisksu", "rezygisk", "zygisk_lsposed", "neozygisk"].iter().any(|d| {
        let p = format!("{mods_root}/{d}");
        Path::new(&p).is_dir()
            && !Path::new(&format!("{p}/disable")).exists()
            && !Path::new(&format!("{p}/remove")).exists()
    });

    let mut orig_fp = String::new();
    if let Ok(tsv) = fs::read_to_string(format!("{datadir}/state/orig_props.tsv")) {
        for line in tsv.lines() {
            if let Some(v) = line.trim_end_matches('\r').strip_prefix("ro.build.fingerprint\t") {
                orig_fp = v.to_string();
                break;
            }
        }
    }
    let cur_fp = get_prop("ro.build.fingerprint");
    let fp_stock = orig_fp.is_empty() || orig_fp == cur_fp;

    let mut procs = Vec::new();
    let mut seen = HashSet::new();
    let mut logs = Vec::new();
    let mut jni_active = false;
    if let Ok(out) = Command::new("logcat").args(["-d", "-s", "KGX_PIShield"]).output() {
        let txt = String::from_utf8_lossy(&out.stdout);
        for raw in txt.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with("---------") {
                continue;
            }
            if let Some(idx) = line.find("Shield active in ") {
                let rest = &line[idx + 17..];
                let proc_name = rest.split(" (").next().unwrap_or("").trim();
                if !proc_name.is_empty() && seen.insert(proc_name.to_string()) {
                    procs.push(proc_name.to_string());
                }
                if rest.contains("jni=1") || rest.contains("jni=2") {
                    jni_active = true;
                }
            }
            logs.push(line.to_string());
            if logs.len() > 8 {
                logs.remove(0);
            }
        }
    }

    let p_json: Vec<String> = procs.iter().map(|s| format!("\"{}\"", json_escape(s))).collect();
    let l_json: Vec<String> = logs.iter().map(|s| format!("\"{}\"", json_escape(s))).collect();
    println!(
        "{{\"ok\":true,\"zygisk_active\":{},\"module_loaded\":{},\"socket_ok\":{},\"rezygisk_desc\":\"{}\",\"fingerprint_stock\":{},\"jni_active\":{},\"shielded_count\":{},\"shielded_procs\":[{}],\"recent_logs\":[{}]}}",
        zygisk_active,
        module_loaded,
        socket_ok,
        json_escape(&rz_desc),
        fp_stock,
        jni_active,
        procs.len(),
        p_json.join(","),
        l_json.join(",")
    );
}

fn is_pid_daemon(proc_root: &str, pid: u64) -> bool {
    if pid == 0 {
        return false;
    }
    let path = format!("{proc_root}/{pid}/cmdline");
    let Ok(raw) = fs::read(&path) else {
        return false;
    };
    let cmd = String::from_utf8_lossy(&raw).replace('\0', " ");
    cmd.contains("gaming_daemon.sh") || (cmd.contains("kgx-core") && cmd.contains("daemon"))
}

fn kill_stale_daemon_procs(proc_root: &str, self_pid: u32) {
    let Ok(rd) = fs::read_dir(proc_root) else {
        return;
    };
    let mut victims = Vec::new();
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().to_string();
        let Ok(pid) = name.parse::<u32>() else {
            continue;
        };
        if pid == self_pid || pid <= 1 {
            continue;
        }
        if is_pid_daemon(proc_root, pid as u64) {
            victims.push(pid);
        }
    }
    if victims.is_empty() {
        return;
    }
    for &pid in &victims {
        unsafe { kill(pid as i32, 15); }
    }
    thread::sleep(Duration::from_millis(500));
    for pid in victims {
        if Path::new(&format!("{proc_root}/{pid}")).exists() {
            unsafe { kill(pid as i32, 9); }
        }
    }
}

fn sleep_interruptible(secs: u64) {
    let total = secs.max(1);
    for _ in 0..total {
        if STOP_DAEMON.load(Ordering::Relaxed) {
            break;
        }
        thread::sleep(Duration::from_secs(1));
    }
}

fn is_scrcpy_active(proc_root: &str) -> bool {
    let Ok(rd) = fs::read_dir(proc_root) else {
        return false;
    };
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().to_string();
        if name.is_empty() || !name.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        if let Ok(raw) = fs::read(format!("{proc_root}/{name}/cmdline")) {
            let cmd = String::from_utf8_lossy(&raw);
            if cmd.contains("scrcpy") {
                return true;
            }
        }
    }
    false
}

fn is_screen_awake(hw: &HashMap<String, String>, proc_root: &str) -> bool {
    if let Some(node) = hw.get("BACKLIGHT_NODE") {
        if !node.is_empty() {
            let txt = read_trimmed(node);
            if !txt.is_empty() {
                if let Ok(v) = txt.parse::<i64>() {
                    if v > 0 {
                        return true;
                    }
                }
            }
        }
    }
    if let Ok(out) = Command::new("dumpsys").arg("power").output() {
        let txt = String::from_utf8_lossy(&out.stdout);
        for line in txt.lines() {
            if line.contains("mWakefulness=") {
                if line.contains("Awake") {
                    return true;
                }
                if line.contains("Asleep") || line.contains("Dozing") {
                    return false;
                }
            }
        }
    }
    is_scrcpy_active(proc_root)
}

fn should_optimize_pkg(moddir: &str, datadir: &str, pkg: &str) -> bool {
    if pkg.is_empty() || !pkg.contains('.') {
        return false;
    }
    if let Ok(txt) = fs::read_to_string(format!("{datadir}/config/custom_games.tsv")) {
        for raw in txt.lines() {
            let line = raw.trim_end_matches('\r');
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() >= 2 && f[0] == pkg {
                return f[1] == "1";
            }
        }
    }
    if let Ok(txt) = fs::read_to_string(format!("{moddir}/data/games.tsv")) {
        for raw in txt.lines() {
            let line = raw.trim_end_matches('\r');
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((first, _)) = line.split_once('\t') {
                if first == pkg {
                    return true;
                }
            }
        }
    }
    false
}

fn call_kgxctl_inner(moddir: &str, args: &[&str], ignore_stop: bool) -> bool {
    let Ok(mut child) = Command::new("sh")
        .arg(format!("{moddir}/bin/kgxctl"))
        .args(args)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
    else {
        return false;
    };
    let max_ticks = if ignore_stop { 100 } else { 200 };
    for _ in 0..max_ticks {
        if let Ok(Some(st)) = child.try_wait() {
            return st.success();
        }
        if !ignore_stop && STOP_DAEMON.load(Ordering::Relaxed) {
            let _ = child.kill();
            let _ = child.wait();
            return false;
        }
        thread::sleep(Duration::from_millis(100));
    }
    let _ = child.kill();
    let _ = child.wait();
    false
}

fn call_kgxctl(moddir: &str, args: &[&str]) -> bool {
    call_kgxctl_inner(moddir, args, false)
}

fn call_kgxctl_cleanup(moddir: &str, args: &[&str]) -> bool {
    call_kgxctl_inner(moddir, args, true)
}

fn fast_ceilings_breached(datadir: &str, sys_root: &str, hw: &HashMap<String, String>) -> bool {
    let ceils = parse_env_file(&format!("{datadir}/state/unlocked_ceilings.env"));
    if ceils.is_empty() {
        return false;
    }
    if let Some(ufcc) = hw.get("EXYNOS_UFCC_DIR").filter(|s| !s.is_empty()) {
        let p = format!("{ufcc}/cpufreq_max_limit");
        if Path::new(&p).exists() && read_trimmed(&p) != "-1" {
            return true;
        }
    }
    if let (Some(egpu), Some(gmax)) = (
        hw.get("EXYNOS_GPU_DIR").filter(|s| !s.is_empty()),
        ceils.get("UNLOCK_GMAX").filter(|s| !s.is_empty()),
    ) {
        let p = format!("{egpu}/gpu_max_clock");
        if Path::new(&p).exists() && read_trimmed(&p) != *gmax {
            return true;
        }
    }
    if let (Some(big_pol), Some(c2max_s)) = (
        hw.get("CPU_BIG_POLICY").filter(|s| !s.is_empty()),
        ceils.get("UNLOCK_C2MAX").filter(|s| !s.is_empty()),
    ) {
        if let Ok(target) = c2max_s.parse::<u64>() {
            let cur = read_u64_digits(&format!("{sys_root}/devices/system/cpu/cpufreq/{big_pol}/scaling_max_freq"));
            if cur > 0 && cur < target {
                return true;
            }
        }
    }
    false
}

fn write_live_fps_cache(datadir: &str, live: Option<u64>, low1: Option<u64>, src: &str) {
    let fpath = format!("{datadir}/state/live_fps.env");
    if let Some(l) = live {
        let tmp = format!("{fpath}.tmp");
        let content = format!(
            "LIVE_FPS={}\nLOW1_FPS={}\nFPS_SRC='{}'\nFPS_TS={}\n",
            l,
            low1.map(|v| v.to_string()).unwrap_or_default(),
            src,
            now_epoch_secs()
        );
        if fs::write(&tmp, content).is_ok() {
            let _ = fs::rename(&tmp, &fpath);
        }
    } else {
        let _ = fs::remove_file(&fpath);
    }
}

fn pick_freq_from_table(path: &str, pct: u64) -> Option<String> {
    let txt = fs::read_to_string(path).ok()?;
    let mut vals: Vec<u64> = txt
        .split_whitespace()
        .filter_map(|s| s.parse::<u64>().ok())
        .collect();
    vals.sort_unstable();
    vals.dedup();
    if vals.is_empty() {
        return None;
    }
    let n = vals.len();
    let idx = (((n - 1) * (pct.min(100) as usize) * 2) + 100) / 200;
    Some(vals[idx.min(n - 1)].to_string())
}

fn evaluate_soft_step_tier(cfg: &HashMap<String, String>, batt_c: i64, cpu_c: i64, prev_tier: u8, force_t2: bool) -> u8 {
    if force_t2 {
        return 2;
    }
    if !cfg_bool(cfg, "SOFT_THERMAL_STEP") {
        return 0;
    }
    if batt_c >= 43 || cpu_c >= 87 {
        2
    } else if prev_tier >= 2 && (batt_c > 41 || cpu_c > 82) {
        2
    } else if batt_c >= 41 || cpu_c >= 82 {
        1
    } else if prev_tier >= 1 && (batt_c > 39 || cpu_c > 77) {
        1
    } else {
        0
    }
}

fn write_kernel_node(path: &str, val: &str) -> bool {
    let Ok(mut f) = fs::OpenOptions::new().write(true).open(path) else {
        return false;
    };
    f.write_all(format!("{val}\n").as_bytes()).is_ok()
}

fn sysfs_write_native(path: &str, val: &str, lock_after: bool, failed_nodes: &mut HashSet<String>) -> bool {
    if path.is_empty() || val.is_empty() || failed_nodes.contains(path) || !Path::new(path).exists() {
        return false;
    }
    let cur = read_trimmed(path);
    if !cur.is_empty() && cur == val {
        if lock_after {
            native_chmod(path, 0o444);
        }
        return true;
    }
    native_chmod(path, 0o664);
    if !write_kernel_node(path, val) {
        failed_nodes.insert(path.to_string());
        return false;
    }
    if lock_after {
        native_chmod(path, 0o444);
    }
    true
}

fn apply_ceilings_and_soft_step_native(
    datadir: &str,
    sys_root: &str,
    hw: &HashMap<String, String>,
    cfg: &HashMap<String, String>,
    new_tier: u8,
    tier_changed: bool,
    failed_nodes: &mut HashSet<String>,
) {
    let lock_active = cfg_bool(cfg, "THERMAL_UNLOCK") || cfg_bool(cfg, "SUSTAINED_SWEET_SPOT");
    let ceil_path = format!("{datadir}/state/unlocked_ceilings.env");
    let mut ceils = parse_env_file(&ceil_path);

    if tier_changed {
        let _ = fs::write(format!("{datadir}/state/soft_step.tier"), format!("{new_tier}\n"));
        let scale: u64 = match new_tier {
            1 => 90,
            2 => 80,
            _ => 100,
        };
        let (base_mid, base_big, base_gpu) = if cfg_bool(cfg, "SUSTAINED_SWEET_SPOT") {
            (88u64, 82u64, 82u64)
        } else {
            (100u64, 100u64, 100u64)
        };
        let mid_pct = (base_mid * scale) / 100;
        let big_pct = (base_big * scale) / 100;
        let gpu_pct = (base_gpu * scale) / 100;

        if let Some(mid_pol) = hw.get("CPU_MID_POLICY").filter(|s| !s.is_empty()) {
            if let Some(f) = pick_freq_from_table(&format!("{sys_root}/devices/system/cpu/cpufreq/{mid_pol}/scaling_available_frequencies"), mid_pct) {
                ceils.insert("UNLOCK_C1MAX".to_string(), f);
            }
        }
        if let Some(big_pol) = hw.get("CPU_BIG_POLICY").filter(|s| !s.is_empty()) {
            if let Some(f) = pick_freq_from_table(&format!("{sys_root}/devices/system/cpu/cpufreq/{big_pol}/scaling_available_frequencies"), big_pct) {
                ceils.insert("UNLOCK_C2MAX".to_string(), f);
            }
        }
        if let Some(egpu) = hw.get("EXYNOS_GPU_DIR").filter(|s| !s.is_empty()) {
            if let Some(f) = pick_freq_from_table(&format!("{egpu}/gpu_freq_table"), gpu_pct) {
                ceils.insert("UNLOCK_GMAX".to_string(), f);
            }
        } else if let Some(df) = hw.get("GPU_DEVFREQ_DIR").filter(|s| !s.is_empty()) {
            if let Some(f) = pick_freq_from_table(&format!("{df}/available_frequencies"), gpu_pct) {
                ceils.insert("UNLOCK_GMAX".to_string(), f);
            }
        }
        if lock_active || !ceils.is_empty() {
            let content = format!(
                "UNLOCK_GMAX='{}'\nUNLOCK_C0MAX='{}'\nUNLOCK_C1MAX='{}'\nUNLOCK_C2MAX='{}'\nUNLOCK_MIFMAX='{}'\nUNLOCK_DSUMAX='{}'\n",
                ceils.get("UNLOCK_GMAX").map(|s| s.as_str()).unwrap_or(""),
                ceils.get("UNLOCK_C0MAX").map(|s| s.as_str()).unwrap_or(""),
                ceils.get("UNLOCK_C1MAX").map(|s| s.as_str()).unwrap_or(""),
                ceils.get("UNLOCK_C2MAX").map(|s| s.as_str()).unwrap_or(""),
                ceils.get("UNLOCK_MIFMAX").map(|s| s.as_str()).unwrap_or(""),
                ceils.get("UNLOCK_DSUMAX").map(|s| s.as_str()).unwrap_or(""),
            );
            let tmp = format!("{ceil_path}.tmp");
            if fs::write(&tmp, content).is_ok() {
                let _ = fs::rename(&tmp, &ceil_path);
            }
        }
    }

    if let Some(ufcc) = hw.get("EXYNOS_UFCC_DIR").filter(|s| !s.is_empty()) {
        if lock_active {
            sysfs_write_native(&format!("{ufcc}/cpufreq_max_limit"), "-1", lock_active, failed_nodes);
        }
    }
    if let Some(c0) = ceils.get("UNLOCK_C0MAX").filter(|s| !s.is_empty()) {
        if let Some(p0) = hw.get("CPU_LITTLE_POLICY").filter(|s| !s.is_empty()) {
            if lock_active {
                sysfs_write_native(&format!("{sys_root}/devices/system/cpu/cpufreq/{p0}/scaling_max_freq"), c0, lock_active, failed_nodes);
            }
        }
    }
    if let Some(c1) = ceils.get("UNLOCK_C1MAX").filter(|s| !s.is_empty()) {
        if let Some(p1) = hw.get("CPU_MID_POLICY").filter(|s| !s.is_empty()) {
            sysfs_write_native(&format!("{sys_root}/devices/system/cpu/cpufreq/{p1}/scaling_max_freq"), c1, lock_active, failed_nodes);
        }
        if let Some(migov) = hw.get("EXYNOS_MIGOV_DIR").filter(|s| !s.is_empty()) {
            sysfs_write_native(&format!("{migov}/cl1/cl1_pm_qos_max_freq"), c1, lock_active, failed_nodes);
        }
    }
    if let Some(c2) = ceils.get("UNLOCK_C2MAX").filter(|s| !s.is_empty()) {
        if let Some(p2) = hw.get("CPU_BIG_POLICY").filter(|s| !s.is_empty()) {
            sysfs_write_native(&format!("{sys_root}/devices/system/cpu/cpufreq/{p2}/scaling_max_freq"), c2, lock_active, failed_nodes);
        }
        if let Some(migov) = hw.get("EXYNOS_MIGOV_DIR").filter(|s| !s.is_empty()) {
            sysfs_write_native(&format!("{migov}/cl2/cl2_pm_qos_max_freq"), c2, lock_active, failed_nodes);
        }
    }
    if let Some(gmax) = ceils.get("UNLOCK_GMAX").filter(|s| !s.is_empty()) {
        if let Some(egpu) = hw.get("EXYNOS_GPU_DIR").filter(|s| !s.is_empty()) {
            sysfs_write_native(&format!("{egpu}/gpu_siop_max_clock"), gmax, lock_active, failed_nodes);
            sysfs_write_native(&format!("{egpu}/gpu_max_clock"), gmax, lock_active, failed_nodes);
        }
        if let Some(df) = hw.get("GPU_DEVFREQ_DIR").filter(|s| !s.is_empty()) {
            sysfs_write_native(&format!("{df}/max_freq"), gmax, lock_active, failed_nodes);
        }
        if let Some(migov) = hw.get("EXYNOS_MIGOV_DIR").filter(|s| !s.is_empty()) {
            sysfs_write_native(&format!("{migov}/gpu/gpu_pm_qos_max_freq"), gmax, lock_active, failed_nodes);
        }
    }
}

fn is_battery_plugged_native(hw: &HashMap<String, String>, sys_root: &str) -> bool {
    let st_node = hw
        .get("BATT_STATUS_NODE")
        .filter(|s| !s.is_empty())
        .cloned()
        .unwrap_or_else(|| format!("{sys_root}/class/power_supply/battery/status"));
    let st = read_trimmed(&st_node);
    if !st.is_empty() {
        return matches!(st.as_str(), "Charging" | "Full" | "Not charging");
    }
    for p in [
        format!("{sys_root}/class/power_supply/usb/online"),
        format!("{sys_root}/class/power_supply/ac/online"),
    ] {
        if read_trimmed(&p) == "1" {
            return true;
        }
    }
    false
}

fn apply_bypass_native(
    datadir: &str,
    sys_root: &str,
    hw: &HashMap<String, String>,
    enable: bool,
    failed_nodes: &mut HashSet<String>,
) {
    let bnode = resolve_bypass_node(hw, sys_root);
    if bnode.is_empty() {
        return;
    }
    let mode = hw.get("BYPASS_MODE").map(|s| s.as_str()).unwrap_or("slate");
    let (on_val, off_val) = match mode {
        "zero_off" => ("0", "1"),
        "slate" | "invert1" => ("1", "0"),
        _ => return,
    };
    let state_file = format!("{datadir}/state/bypass_active.state");
    if enable {
        if is_battery_plugged_native(hw, sys_root) && sysfs_write_native(&bnode, on_val, false, failed_nodes) {
            let _ = fs::write(&state_file, "1\n");
        }
    } else {
        let _ = sysfs_write_native(&bnode, off_val, false, failed_nodes);
        let _ = fs::remove_file(&state_file);
    }
}

fn is_freezer_protected(pkg: &str, moddir: &str) -> bool {
    if pkg.is_empty()
        || pkg == "android"
        || pkg == "com.kgx.ultimate"
        || pkg.starts_with("com.android.")
        || pkg.starts_with("com.sec.android.desktopmode")
        || pkg.starts_with("com.sec.android.app.desktoplauncher")
        || pkg.starts_with("com.sec.android.app.dexonpc")
        || pkg.starts_with("com.samsung.android.app.cocktailbarservice")
        || pkg.starts_with("com.samsung.android.honeyboard")
        || pkg.starts_with("com.sec.android.app.launcher")
        || pkg.starts_with("com.google.android.gms")
        || pkg.starts_with("com.google.android.gsf")
    {
        return true;
    }
    if let Ok(txt) = fs::read_to_string(format!("{moddir}/data/protected_pkgs.list")) {
        for raw in txt.lines() {
            if raw.trim() == pkg {
                return true;
            }
        }
    }
    false
}

fn load_pkg_uid_map() -> HashMap<String, u32> {
    let mut map = HashMap::new();
    let plist = env::var("KGX_PKGS_LIST").unwrap_or_else(|_| "/data/system/packages.list".to_string());
    if let Ok(txt) = fs::read_to_string(&plist) {
        for line in txt.lines() {
            let mut it = line.split_whitespace();
            if let (Some(pkg), Some(uid_s)) = (it.next(), it.next()) {
                if let Ok(uid) = uid_s.parse::<u32>() {
                    map.insert(pkg.to_string(), uid);
                }
            }
        }
    }
    map
}

fn scan_uid_min_oom_adj(proc_root: &str) -> HashMap<u32, i64> {
    let mut map: HashMap<u32, i64> = HashMap::new();
    let Ok(rd) = fs::read_dir(proc_root) else {
        return map;
    };
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().to_string();
        if name.is_empty() || !name.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let Ok(st) = fs::read_to_string(format!("{proc_root}/{name}/status")) else {
            continue;
        };
        let mut uid_opt = None;
        for line in st.lines() {
            if let Some(rest) = line.strip_prefix("Uid:") {
                uid_opt = rest.split_whitespace().next().and_then(|s| s.parse::<u32>().ok());
                break;
            }
        }
        let Some(uid) = uid_opt else {
            continue;
        };
        if uid < 10000 {
            continue;
        }
        if let Some(adj) = read_i64_signed(&format!("{proc_root}/{name}/oom_score_adj")) {
            let entry = map.entry(uid).or_insert(9999);
            if adj < *entry {
                *entry = adj;
            }
        }
    }
    map
}

fn set_uid_freeze_native(cgroup_root: &str, uid: u32, freeze: bool) -> bool {
    let fnode = format!("{cgroup_root}/uid_{uid}/cgroup.freeze");
    if !Path::new(&fnode).is_file() {
        return false;
    }
    native_chmod(&fnode, 0o644);
    write_kernel_node(&fnode, if freeze { "1" } else { "0" })
}

fn unfreeze_all_native(datadir: &str, cgroup_root: &str) {
    let state_file = format!("{datadir}/state/frozen_uids.tsv");
    if let Ok(txt) = fs::read_to_string(&state_file) {
        for line in txt.lines() {
            if let Some((uid_s, _)) = line.split_once('\t') {
                if let Ok(uid) = uid_s.trim().parse::<u32>() {
                    let _ = set_uid_freeze_native(cgroup_root, uid, false);
                }
            }
        }
        let _ = fs::remove_file(&state_file);
    }
}

fn sync_freezer_native(
    moddir: &str,
    datadir: &str,
    proc_root: &str,
    cgroup_root: &str,
    cfg: &HashMap<String, String>,
    active_pkg: &str,
    open_sf_pkgs: &HashSet<String>,
) {
    if cfg_bool(cfg, "SAFE_MODE") || !cfg_bool(cfg, "FREEZER_ENABLED") || !is_freezer_supported(cgroup_root) {
        unfreeze_all_native(datadir, cgroup_root);
        return;
    }

    let cfg_path = format!("{datadir}/config/freezer_apps.list");
    let mut targets: Vec<String> = Vec::new();
    let mut target_set: HashSet<String> = HashSet::new();
    if let Ok(txt) = fs::read_to_string(&cfg_path) {
        for raw in txt.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if target_set.insert(line.to_string()) {
                targets.push(line.to_string());
            }
        }
    }

    let adj_map = scan_uid_min_oom_adj(proc_root);
    let state_file = format!("{datadir}/state/frozen_uids.tsv");
    let mut kept: Vec<(u32, String)> = Vec::new();
    let mut kept_uids: HashSet<u32> = HashSet::new();

    if let Ok(txt) = fs::read_to_string(&state_file) {
        for line in txt.lines() {
            let Some((uid_s, pkg_s)) = line.split_once('\t') else {
                continue;
            };
            let Ok(uid) = uid_s.trim().parse::<u32>() else {
                continue;
            };
            let pkg = pkg_s.trim();
            let min_adj = adj_map.get(&uid).copied().unwrap_or(9999);
            let should_unfreeze = pkg == active_pkg
                || is_freezer_protected(pkg, moddir)
                || !target_set.contains(pkg)
                || open_sf_pkgs.contains(pkg)
                || min_adj <= 300;
            if should_unfreeze {
                let _ = set_uid_freeze_native(cgroup_root, uid, false);
            } else if kept_uids.insert(uid) {
                kept.push((uid, pkg.to_string()));
            }
        }
    }

    if !active_pkg.is_empty() && !targets.is_empty() {
        let uid_map = load_pkg_uid_map();
        for pkg in targets {
            if pkg == active_pkg || is_freezer_protected(&pkg, moddir) || open_sf_pkgs.contains(&pkg) {
                continue;
            }
            let Some(&uid) = uid_map.get(&pkg) else {
                continue;
            };
            if uid < 10000 || kept_uids.contains(&uid) {
                continue;
            }
            let min_adj = adj_map.get(&uid).copied().unwrap_or(9999);
            if min_adj >= 500 && min_adj < 9999 && set_uid_freeze_native(cgroup_root, uid, true) {
                kept_uids.insert(uid);
                kept.push((uid, pkg));
            }
        }
    }

    if kept.is_empty() {
        let _ = fs::remove_file(&state_file);
    } else {
        let mut out = String::new();
        for (u, p) in kept {
            out.push_str(&format!("{u}\t{p}\n"));
        }
        let tmp = format!("{state_file}.tmp");
        if fs::write(&tmp, out).is_ok() {
            let _ = fs::rename(&tmp, &state_file);
        }
    }
}

fn cmd_daemon(moddir: &str, datadir: &str, sys_root: &str, proc_root: &str) {
    unsafe {
        signal(1, handle_stop_signal);
        signal(15, handle_stop_signal);
        signal(2, handle_stop_signal);
    }
    let cgroup_root = env::var("KGX_CGROUP_ROOT").unwrap_or_else(|_| "/sys/fs/cgroup".to_string());
    let state_dir = format!("{datadir}/state");
    let _ = fs::create_dir_all(&state_dir);
    let pid_file = format!("{state_dir}/daemon.pid");

    let old_pid = read_u64_digits(&pid_file);
    let self_pid = std::process::id();
    if old_pid > 0 && old_pid != self_pid as u64 && is_pid_daemon(proc_root, old_pid) {
        return;
    }
    kill_stale_daemon_procs(proc_root, self_pid);
    let _ = fs::write(&pid_file, format!("{self_pid}\n"));

    if Path::new(&format!("{state_dir}/active_display.env")).is_file()
        && !Path::new(&format!("{state_dir}/active_session.env")).is_file()
    {
        call_kgxctl(moddir, &["display", "restore"]);
    }

    let mut active_pkg = String::new();
    let mut away_since: u64 = 0;
    let mut failed_sysfs: HashSet<String> = HashSet::new();

    while !STOP_DAEMON.load(Ordering::Relaxed) {
        let cfg = load_config(moddir, datadir);
        let hw = load_hw_profile_healed(moddir, datadir);
        let poll_active = cfg_int(&cfg, "POLL_INTERVAL_ACTIVE", 2).clamp(1, 30) as u64;
        let poll_idle = cfg_int(&cfg, "POLL_INTERVAL_IDLE", 1).clamp(1, 30) as u64;
        let awake_idle = poll_idle.min(1);
        let exit_debounce = cfg_int(&cfg, "EXIT_DEBOUNCE_SEC", 2).clamp(1, 30) as u64;
        let safe_mode = cfg_bool(&cfg, "SAFE_MODE");

        if active_pkg.is_empty() {
            let sess_env = parse_env_file(&format!("{datadir}/state/active_session.env"));
            if let Some(spkg) = sess_env.get("ACTIVE_PKG").filter(|s| !s.is_empty()) {
                active_pkg = spkg.clone();
            }
        }

        let ext_screen_off_cfg = cfg_bool(&cfg, "EXT_DISPLAY_SCREEN_OFF");
        let ext_off_state = Path::new(&format!("{datadir}/state/ext_internal_off.state")).is_file();
        let res_override_cfg = cfg_bool(&cfg, "RES_OVERRIDE_ENABLED");
        let res_env = parse_env_file(&format!("{datadir}/state/active_res.env"));
        let mut cur_res = res_env.get("ACTIVE_RES").cloned().unwrap_or_default();
        let mut cur_res_src = res_env.get("ACTIVE_RES_SOURCE").cloned().unwrap_or_default();

        let ext_connected = if ext_screen_off_cfg || ext_off_state || res_override_cfg {
            detect_external_display(sys_root, true).is_some()
        } else {
            false
        };
        if safe_mode || !ext_screen_off_cfg {
            if ext_off_state {
                call_kgxctl(moddir, &["display", "internal-power", "on"]);
            }
        } else if ext_connected && !ext_off_state {
            call_kgxctl(moddir, &["display", "internal-power", "off"]);
        } else if !ext_connected && ext_off_state {
            call_kgxctl(moddir, &["display", "internal-power", "on"]);
        }

        let scrcpy_on = if res_override_cfg && !safe_mode {
            is_scrcpy_active(proc_root)
        } else {
            false
        };
        let res_scope = cfg.get("RES_OVERRIDE_SCOPE").map(|s| s.as_str()).unwrap_or("ext_scrcpy");
        let res_preset = cfg.get("RES_OVERRIDE_PRESET").map(|s| s.as_str()).unwrap_or("1080x1920");
        let want_global_res = !safe_mode && res_override_cfg && (res_scope == "always" || ext_connected || scrcpy_on);
        if want_global_res {
            if cur_res_src != "global" || cur_res != res_preset {
                call_kgxctl(moddir, &["display", "res-sync"]);
                let refreshed = parse_env_file(&format!("{datadir}/state/active_res.env"));
                cur_res = refreshed.get("ACTIVE_RES").cloned().unwrap_or_default();
                cur_res_src = refreshed.get("ACTIVE_RES_SOURCE").cloned().unwrap_or_default();
            }
        } else if cur_res_src == "global" || (safe_mode && !cur_res.is_empty()) {
            call_kgxctl(moddir, &["display", "res-sync"]);
            let refreshed = parse_env_file(&format!("{datadir}/state/active_res.env"));
            cur_res = refreshed.get("ACTIVE_RES").cloned().unwrap_or_default();
            cur_res_src = refreshed.get("ACTIVE_RES_SOURCE").cloned().unwrap_or_default();
        }

        if safe_mode || !cfg_bool(&cfg, "AUTO_OPTIMIZE") {
            unfreeze_all_native(datadir, &cgroup_root);
            reset_game_res_fast(datadir);
            if !active_pkg.is_empty() {
                call_kgxctl(moddir, &["games", "restore"]);
                active_pkg.clear();
                away_since = 0;
                failed_sysfs.clear();
            }
            sleep_interruptible(poll_idle);
            continue;
        }

        if !ext_connected && !is_screen_awake(&hw, proc_root) {
            unfreeze_all_native(datadir, &cgroup_root);
            reset_game_res_fast(datadir);
            if !active_pkg.is_empty() {
                call_kgxctl(moddir, &["games", "restore"]);
                active_pkg.clear();
                away_since = 0;
                failed_sysfs.clear();
            }
            sleep_interruptible(8);
            continue;
        }

        let fg_pkg = detect_focused_pkg(moddir, datadir);
        let freezer_on = cfg_bool(&cfg, "FREEZER_ENABLED");
        let open_sf_pkgs = if freezer_on {
            scan_sf_list("", false).2
        } else {
            HashSet::new()
        };

        if active_pkg.is_empty()
            && !Path::new(&format!("{datadir}/state/active_session.env")).is_file()
            && cur_res_src == "game"
            && !should_optimize_pkg(moddir, datadir, &fg_pkg)
        {
            reset_game_res_fast(datadir);
            cur_res.clear();
            cur_res_src.clear();
        }

        if should_optimize_pkg(moddir, datadir, &fg_pkg) {
            if away_since != 0 {
                away_since = 0;
                if cur_res.is_empty() {
                    let wres = lookup_game_wm_res(datadir, &active_pkg);
                    apply_game_res_fast(datadir, &wres);
                }
            }
            if fg_pkg != active_pkg {
                let new_wres = lookup_game_wm_res(datadir, &fg_pkg);
                if !active_pkg.is_empty() {
                    unfreeze_all_native(datadir, &cgroup_root);
                    reset_game_res_fast(datadir);
                    call_kgxctl(moddir, &["games", "restore"]);
                }
                if !new_wres.is_empty() {
                    apply_game_res_fast(datadir, &new_wres);
                }
                failed_sysfs.clear();
                if call_kgxctl(moddir, &["games", "apply", &fg_pkg]) {
                    active_pkg = fg_pkg;
                }
            } else {
                let (batt_c, cpu_c, gpu_c) = read_temps_c(&hw);

                let prev_stage = read_trimmed(&format!("{datadir}/state/thermal_stage.state"));
                let (new_stage, _) = evaluate_thermal(&cfg, batt_c, cpu_c, gpu_c, if prev_stage.is_empty() { "NORMAL" } else { &prev_stage });
                let stage_changed = !prev_stage.is_empty() && new_stage != prev_stage;

                let (alert_hit, _) = evaluate_thermal_alert(&cfg, batt_c, cpu_c);
                let alert_action = cfg.get("THERMAL_ALERT_ACTION").map(|s| s.as_str()).unwrap_or("notify");
                let force_t2 = alert_hit && (alert_action == "step_down" || alert_action == "both");
                let emergency_bypass = alert_hit && (alert_action == "bypass" || alert_action == "both");

                let prev_tier = read_trimmed(&format!("{datadir}/state/soft_step.tier")).parse::<u8>().unwrap_or(0);
                let new_tier = evaluate_soft_step_tier(&cfg, batt_c, cpu_c, prev_tier, force_t2);
                let tier_changed = new_tier != prev_tier;
                let lock_active = cfg_bool(&cfg, "THERMAL_UNLOCK") || cfg_bool(&cfg, "SUSTAINED_SWEET_SPOT");
                let ceiling_breached = lock_active && fast_ceilings_breached(datadir, sys_root, &hw);

                let byp_active = Path::new(&format!("{datadir}/state/bypass_active.state")).is_file();
                let byp_enabled = cfg_bool(&cfg, "BYPASS_CHARGING");
                let byp_min = cfg_int(&cfg, "BYPASS_MIN_PCT", 80).clamp(20, 95) as u64;
                let batt_pct = read_battery_pct(&hw, sys_root);
                if emergency_bypass {
                    if !byp_active {
                        apply_bypass_native(datadir, sys_root, &hw, true, &mut failed_sysfs);
                    }
                } else if !byp_enabled && byp_active {
                    apply_bypass_native(datadir, sys_root, &hw, false, &mut failed_sysfs);
                } else if byp_enabled && byp_active && batt_pct < byp_min.saturating_sub(3) {
                    apply_bypass_native(datadir, sys_root, &hw, false, &mut failed_sysfs);
                } else if byp_enabled && !byp_active && batt_pct >= byp_min {
                    apply_bypass_native(datadir, sys_root, &hw, true, &mut failed_sysfs);
                }

                if stage_changed {
                    call_kgxctl(moddir, &["internal", "thermal-step"]);
                } else if tier_changed || ceiling_breached {
                    apply_ceilings_and_soft_step_native(
                        datadir,
                        sys_root,
                        &hw,
                        &cfg,
                        new_tier,
                        tier_changed,
                        &mut failed_sysfs,
                    );
                }

                if freezer_on {
                    sync_freezer_native(moddir, datadir, proc_root, &cgroup_root, &cfg, &active_pkg, &open_sf_pkgs);
                } else if Path::new(&format!("{datadir}/state/frozen_uids.tsv")).is_file() {
                    unfreeze_all_native(datadir, &cgroup_root);
                }

                let (live_fps, low1_fps, src) = read_fps_surfaceflinger_ex(datadir, &active_pkg, sys_root, Some("dm"));
                write_live_fps_cache(datadir, live_fps, low1_fps, src);
            }
            sleep_interruptible(poll_active);
        } else {
            if !active_pkg.is_empty() {
                let now = now_epoch_secs();
                if away_since == 0 {
                    away_since = now;
                }
                if freezer_on {
                    sync_freezer_native(moddir, datadir, proc_root, &cgroup_root, &cfg, &active_pkg, &open_sf_pkgs);
                }
                if now.saturating_sub(away_since) >= 1 && cur_res_src == "game" {
                    reset_game_res_fast(datadir);
                    cur_res.clear();
                    cur_res_src.clear();
                }
                if now.saturating_sub(away_since) >= exit_debounce {
                    unfreeze_all_native(datadir, &cgroup_root);
                    reset_game_res_fast(datadir);
                    call_kgxctl(moddir, &["games", "restore"]);
                    active_pkg.clear();
                    away_since = 0;
                    failed_sysfs.clear();
                }
                sleep_interruptible(1);
            } else {
                if Path::new(&format!("{datadir}/state/frozen_uids.tsv")).is_file() {
                    unfreeze_all_native(datadir, &cgroup_root);
                }
                sleep_interruptible(awake_idle);
            }
        }
    }

    unfreeze_all_native(datadir, &cgroup_root);
    reset_game_res_fast(datadir);
    if !active_pkg.is_empty() || Path::new(&format!("{datadir}/state/active_session.env")).is_file() {
        call_kgxctl_cleanup(moddir, &["games", "restore"]);
    }
    if Path::new(&format!("{datadir}/state/active_display.env")).is_file() {
        call_kgxctl_cleanup(moddir, &["display", "restore"]);
    }
    if Path::new(&format!("{datadir}/state/ext_internal_off.state")).is_file() {
        call_kgxctl_cleanup(moddir, &["display", "internal-power", "on"]);
    }
    if Path::new(&format!("{datadir}/state/active_res.env")).is_file() {
        call_kgxctl_cleanup(moddir, &["display", "res-reset"]);
    }
    let _ = fs::remove_file(&pid_file);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let moddir = env::var("KGX_MODDIR").unwrap_or_else(|_| "/data/adb/modules/ksu_ultimate_gaming_x".to_string());
    let datadir = env::var("KGX_DATA_DIR").unwrap_or_else(|_| "/data/adb/ksu_gaming_x".to_string());
    let sys_root = env::var("KGX_SYS_ROOT").unwrap_or_else(|_| "/sys".to_string());
    let proc_root = env::var("KGX_PROC_ROOT").unwrap_or_else(|_| "/proc".to_string());

    let sub = args.get(1).map(|s| s.as_str()).unwrap_or("status");
    match sub {
        "version" => println!("kgx-core v1.0.0 (rust aarch64)"),
        "status" => cmd_status(&moddir, &datadir, &sys_root, &proc_root),
        "engine" => cmd_engine_get(&moddir, &datadir),
        "profiles" => cmd_profiles_list(&moddir, &datadir, args.get(3).map(|s| s.as_str()).unwrap_or("")),
        "logs" => {
            let n = args.get(2).and_then(|s| s.parse::<usize>().ok()).unwrap_or(80);
            cmd_logs(&datadir, n);
        }
        "fps" => cmd_fps(&datadir, &sys_root, args.get(2).map(|s| s.as_str()).unwrap_or("")),
        "overlay-tick" => cmd_overlay_tick(&moddir, &datadir, &sys_root, &proc_root, args.get(2).map(|s| s.as_str()).unwrap_or("")),
        "pi-diag" => cmd_pi_diag(&datadir),
        "spoof" if args.get(2).map(|s| s.as_str()) == Some("diag") => cmd_pi_diag(&datadir),
        "pin-threads" => cmd_pin_threads(
            &sys_root,
            &proc_root,
            args.get(2).map(|s| s.as_str()).unwrap_or(""),
            args.get(3).map(|s| s.as_str()).unwrap_or("-6"),
        ),
        "trim-list" => cmd_trim_list(
            &moddir,
            &proc_root,
            args.get(2).map(|s| s.as_str()).unwrap_or(""),
            args.get(3).and_then(|s| s.parse::<usize>().ok()).unwrap_or(15).clamp(1, 50),
        ),
        "daemon" => cmd_daemon(&moddir, &datadir, &sys_root, &proc_root),
        _ => {
            eprintln!("Unsupported kgx-core subcommand: {sub}");
            std::process::exit(1);
        }
    }
}
