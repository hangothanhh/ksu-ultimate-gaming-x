#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Comprehensive 7-stage verification suite for KSU Ultimate Gaming X v1.0.0."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_DIR = ROOT / "module"
DIST_ZIP = ROOT / "dist" / "KSU-Ultimate-Gaming-X-v1.0.0.zip"
DIST_ZIP_SHA = ROOT / "dist" / "KSU-Ultimate-Gaming-X-v1.0.0.zip.sha256"
DIST_APK = ROOT / "dist" / "KSU-Ultimate-Gaming-X-v1.0.0.apk"
DIST_APK_SHA = ROOT / "dist" / "KSU-Ultimate-Gaming-X-v1.0.0.apk.sha256"
IS_WIN = os.name == "nt"


def find_apksigner() -> Path:
    found = shutil.which("apksigner")
    if found:
        return Path(found)
    name = "apksigner.bat" if IS_WIN else "apksigner"
    for val in (
        os.environ.get("ANDROID_SDK_ROOT"),
        os.environ.get("ANDROID_HOME"),
        r"C:\Android\sdk" if IS_WIN else None,
        str(Path.home() / "Android" / "Sdk"),
        "/usr/local/lib/android/sdk",
    ):
        if not val:
            continue
        bt = Path(val) / "build-tools"
        pref = bt / "34.0.0" / name
        if pref.is_file():
            return pref
        if bt.is_dir():
            for child in sorted(bt.iterdir(), reverse=True):
                cand = child / name
                if cand.is_file():
                    return cand
    return Path(r"C:\Android\sdk\build-tools\34.0.0\apksigner.bat" if IS_WIN else "apksigner")


APKSIGNER = find_apksigner()
SH_BIN = r"C:\Program Files\Git\bin\sh.exe" if IS_WIN and Path(r"C:\Program Files\Git\bin\sh.exe").is_file() else (shutil.which("sh") or "/bin/sh")


def to_msys(p: Path) -> str:
    s = p.resolve().as_posix()
    if IS_WIN and len(s) >= 2 and s[1] == ":":
        return f"/{s[0].lower()}{s[2:]}"
    return s


def run_sh(script_cmd: str, env_extra: dict[str, str] | None = None, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    if IS_WIN:
        env = {
            "SYSTEMROOT": os.environ.get("SYSTEMROOT", r"C:\Windows"),
            "TEMP": os.environ.get("TEMP", r"C:\Windows\Temp"),
            "TMP": os.environ.get("TMP", r"C:\Windows\Temp"),
            "PATH": "/usr/bin:/bin",
            "LC_ALL": "C",
        }
    else:
        env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
            "LC_ALL": "C",
        }
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        [SH_BIN, "-c", script_cmd],
        cwd=str(cwd or ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )


def assert_true(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


# ---------------------------------------------------------------------------
# Stage 1: Shell Syntax Check
# ---------------------------------------------------------------------------
def stage_1_shell_syntax() -> None:
    targets = sorted(MOD_DIR.rglob("*.sh")) + [
        MOD_DIR / "bin" / "kgxctl",
        MOD_DIR / "META-INF" / "com" / "google" / "android" / "update-binary",
    ]
    assert_true(len(targets) >= 18, f"Expected >= 18 shell files, found {len(targets)}")
    for f in targets:
        res = subprocess.run([SH_BIN, "-n", to_msys(f)], capture_output=True, text=True)
        assert_true(res.returncode == 0, f"Syntax check failed for {f}: {res.stderr}")
    print(f"[PASS] Stage 1: Shell syntax valid on {len(targets)} POSIX scripts.")


# ---------------------------------------------------------------------------
# Stage 2: Line Ending, POSIX Hygiene & Removed-Feature Audit
# ---------------------------------------------------------------------------
def stage_2_hygiene() -> None:
    text_files = [
        p for p in MOD_DIR.rglob("*")
        if p.is_file() and (
            p.suffix.lower() in {".sh", ".prop", ".tsv", ".json", ".conf", ".list", ".html", ".css", ".js"}
            or p.name in {"kgxctl", "update-binary", "updater-script"}
        )
    ]
    shell_files = [
        p for p in text_files
        if p.suffix.lower() == ".sh" or p.name in {"kgxctl", "update-binary"}
    ]
    for f in text_files:
        raw = f.read_bytes()
        assert_true(b"\r\n" not in raw, f"CRLF detected in {f}")
        assert_true(not raw.startswith(b"\xef\xbb\xbf"), f"UTF-8 BOM detected in {f}")
        txt_chk = raw.decode("utf-8", errors="ignore")
        assert_true("cmd netpolicy" not in txt_chk, f"Deprecated 'cmd netpolicy' found in {f}")
        if f.name != "customize.sh":
            assert_true(not re.search(r"\bNET_RESTRICT_BG\b", txt_chk), f"Deprecated NET_RESTRICT_BG found in {f}")
            assert_true(not re.search(r"\bSPOOF_MODE\b", txt_chk), f"Deprecated SPOOF_MODE found in {f}")

    for sf in shell_files:
        txt = sf.read_text(encoding="utf-8")
        for idx, line in enumerate(txt.splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith("#"):
                continue
            assert_true("[[" not in line, f"Bashism '[[' in {sf}:{idx}: {line}")
            assert_true(not re.search(r"^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\s*(\(\s*\))?\s*\{", line), f"Bashism 'function' in {sf}:{idx}")
            assert_true(not re.search(r"\bdeclare\s+", line), f"Bashism 'declare' in {sf}:{idx}")
            assert_true(not re.search(r"\bsource\s+", line), f"Bashism 'source' in {sf}:{idx}")
            assert_true(not re.search(r"tr\s+['\"]?\\0['\"]?.*<\s*[^|]*cmdline", line),
                        f"Forbidden direct /proc cmdline redirect into tr in {sf}:{idx}: {line}")

    cust = (MOD_DIR / "customize.sh").read_text(encoding="utf-8")
    assert_true("set_perm_recursive" not in cust or "webroot" not in cust.split("set_perm_recursive")[-1],
                "customize.sh must never call set_perm_recursive on webroot")
    print(f"[PASS] Stage 2: Zero CRLF/BOM/bashisms/deprecated-netpolicy across {len(text_files)} module files.")


# ---------------------------------------------------------------------------
# Stage 3: Database & Security Audit
# ---------------------------------------------------------------------------
def stage_3_databases() -> None:
    devs_json = json.loads((MOD_DIR / "data" / "devices.json").read_text(encoding="utf-8"))
    games_json = json.loads((MOD_DIR / "data" / "games.json").read_text(encoding="utf-8"))
    assert_true(len(devs_json) >= 34, f"Expected >= 34 device profiles, got {len(devs_json)}")
    assert_true(len(games_json) >= 31, f"Expected >= 31 game profiles, got {len(games_json)}")

    dev_tsv_rows = [
        ln.split("\t")
        for ln in (MOD_DIR / "data" / "devices.tsv").read_text(encoding="utf-8").splitlines()
        if ln and not ln.startswith("#")
    ]
    game_tsv_rows = [
        ln.split("\t")
        for ln in (MOD_DIR / "data" / "games.tsv").read_text(encoding="utf-8").splitlines()
        if ln and not ln.startswith("#")
    ]
    assert_true(len(dev_tsv_rows) == len(devs_json), "devices.tsv / devices.json row count mismatch")
    assert_true(len(game_tsv_rows) == len(games_json), "games.tsv / games.json row count mismatch")

    for r in dev_tsv_rows:
        assert_true(len(r) == 15, f"Expected 15 columns in devices.tsv, got {len(r)}: {r}")
    for r in game_tsv_rows:
        assert_true(len(r) == 12, f"Expected 12 columns in games.tsv, got {len(r)}: {r}")
        assert_true(r[3] in {"WHITELIST", "GAME_CAP", "OPEN"}, f"Invalid limit_type: {r[3]}")

    dev_by_id = {d["id"]: d for d in devs_json}
    for req_id in [
        "realme_14_5g", "galaxy_s26_ultra", "redmagic_11_pro", "rog_phone_9_pro",
        "xiaomi_17_ultra", "oneplus_15", "iqoo_15", "redmagic_10_pro",
        "galaxy_s25_ultra", "xiaomi_15_ultra", "oneplus_13", "iqoo_13",
        "realme_gt7_pro", "redmi_k80_pro", "redmi_k80_ultra", "vivo_x200_pro",
    ]:
        assert_true(req_id in dev_by_id, f"Missing flagship profile: {req_id}")

    assert_true(
        dev_by_id["realme_14_5g"]["model"] == "RMX5070"
        and dev_by_id["galaxy_s26_ultra"]["model"] == "SM-S948B"
        and dev_by_id["redmagic_11_pro"]["model"] == "NX809J"
        and dev_by_id["rog_phone_9_pro"]["model"] == "ASUS_AI2501_D",
        "Mismatch in new 2025-2026 flagship model codes",
    )

    dev_ids = set(dev_by_id.keys())
    for g in games_json:
        assert_true(g["preferred_adreno"] in dev_ids, f"Unknown preferred_adreno {g['preferred_adreno']}")
        assert_true(g["preferred_mali"] in dev_ids, f"Unknown preferred_mali {g['preferred_mali']}")

    by_pkg = {g["package"]: g for g in games_json}
    assert_true(by_pkg["com.dts.freefireth"]["preferred_adreno"] == "realme_14_5g", "Free Fire must prefer realme_14_5g")
    assert_true(by_pkg["com.dts.freefiremax"]["preferred_adreno"] == "realme_14_5g", "Free Fire MAX must prefer realme_14_5g")
    assert_true(by_pkg["com.garena.game.dfvn"]["preferred_adreno"] == "iqoo_15", "Delta Force VN must prefer iqoo_15")
    assert_true(by_pkg["com.miHoYo.GenshinImpact"]["limit_type"] == "GAME_CAP" and by_pkg["com.miHoYo.GenshinImpact"]["engine_max_fps"] == 60,
                "Genshin Impact must be honestly marked GAME_CAP 60")

    spoof_txt = (MOD_DIR / "lib" / "spoof.sh").read_text(encoding="utf-8")
    for bad in ["ro.serialno", "ro.boot.verifiedbootstate", "ro.debuggable", "persist.radio.imei"]:
        assert_true(bad not in spoof_txt, f"Forbidden property {bad} found in spoof.sh")
    print(f"[PASS] Stage 3: Databases ({len(devs_json)} devices, {len(games_json)} games) & security policy verified.")


# ---------------------------------------------------------------------------
# Stage 4: End-to-End Functional Mock Suite (Real POSIX sh.exe)
# ---------------------------------------------------------------------------
def create_mock_env(base: Path, variant: str = "adreno") -> dict[str, str]:
    mock_bin = base / "mock_bin"
    sys_root = base / "sys"
    proc_root = base / "proc"
    dev_root = base / "dev"
    mods_root = base / "modules"
    data_dir = base / "data"
    mod_copy = base / "module"

    for d in [mock_bin, sys_root, proc_root, dev_root, mods_root, data_dir]:
        d.mkdir(parents=True, exist_ok=True)

    for src in MOD_DIR.rglob("*"):
        rel = src.relative_to(MOD_DIR)
        dst = mod_copy / rel
        if src.is_dir():
            dst.mkdir(parents=True, exist_ok=True)
        else:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(src.read_bytes())

    if variant == "exynos":
        cpu_pols = [
            ("policy0", "400000 576000 864000 1344000 1824000", "1344000", "400000", "1344000", "1824000"),
            ("policy4", "576000 960000 1632000 2016000 2515000", "672000", "576000", "672000", "2515000"),
            ("policy7", "576000 960000 1440000 2208000 2803000", "768000", "576000", "768000", "2803000"),
        ]
    else:
        cpu_pols = [
            ("policy0", "300000 556800 902400 1305600 1708800 2265600", "902400", "300000", "2265600", "2265600"),
            ("policy7", "844800 1344000 1862400 2457600 2956800 3302400", "1344000", "844800", "3302400", "3302400"),
        ]

    for pol, freqs, cur, mn, mx, hw_mx in cpu_pols:
        pd = sys_root / "devices" / "system" / "cpu" / "cpufreq" / pol
        (pd / "schedutil").mkdir(parents=True, exist_ok=True)
        (pd / "scaling_available_frequencies").write_text(freqs + "\n", newline="\n")
        (pd / "scaling_available_governors").write_text("conservative powersave performance schedutil\n", newline="\n")
        (pd / "scaling_governor").write_text("schedutil\n", newline="\n")
        (pd / "scaling_cur_freq").write_text(cur + "\n", newline="\n")
        (pd / "scaling_min_freq").write_text(mn + "\n", newline="\n")
        (pd / "scaling_max_freq").write_text(mx + "\n", newline="\n")
        (pd / "cpuinfo_max_freq").write_text(hw_mx + "\n", newline="\n")
        (pd / "schedutil" / "up_rate_limit_us").write_text("2000\n", newline="\n")
        (pd / "schedutil" / "down_rate_limit_us").write_text("10000\n", newline="\n")

    if variant == "adreno":
        kgsl = sys_root / "class" / "kgsl" / "kgsl-3d0"
        df = kgsl / "devfreq"
        df.mkdir(parents=True, exist_ok=True)
        (kgsl / "gpu_model").write_text("Adreno750v1\n", newline="\n")
        (kgsl / "throttling").write_text("1\n", newline="\n")
        (df / "available_frequencies").write_text("220000000 350000000 500000000 680000000 903000000\n", newline="\n")
        (df / "available_governors").write_text("msm-adreno-tz simple_ondemand performance\n", newline="\n")
        (df / "governor").write_text("msm-adreno-tz\n", newline="\n")
        (df / "min_freq").write_text("220000000\n", newline="\n")
        (df / "max_freq").write_text("903000000\n", newline="\n")
        (df / "cur_freq").write_text("350000000\n", newline="\n")
    elif variant == "exynos":
        egpu = sys_root / "kernel" / "gpu"
        egpu.mkdir(parents=True, exist_ok=True)
        (egpu / "gpu_model").write_text("Samsung Xclipse 920\n", newline="\n")
        (egpu / "gpu_freq_table").write_text("303000 500000 807000 1095000 1306000\n", newline="\n")
        (egpu / "gpu_available_governor").write_text("static conservative interactive amigo\n", newline="\n")
        (egpu / "gpu_governor").write_text("conservative\n", newline="\n")
        (egpu / "gpu_min_clock").write_text("303000\n", newline="\n")
        (egpu / "gpu_max_clock").write_text("303000\n", newline="\n")
        (egpu / "gpu_siop_max_clock").write_text("1306000\n", newline="\n")
        (egpu / "gpu_ifpo_control").write_text("1\n", newline="\n")
        (egpu / "gpu_cl_boost_disable").write_text("1\n", newline="\n")
        (egpu / "gpu_clock").write_text("303000\n", newline="\n")
        (egpu / "gpu_tmu").write_text("62.0\n", newline="\n")

        df = sys_root / "class" / "devfreq" / "16e00000.sgpu"
        df.mkdir(parents=True, exist_ok=True)
        (df / "available_frequencies").write_text("1306000 1095000 807000 500000 303000\n", newline="\n")
        (df / "available_governors").write_text("sgpu_governor\n", newline="\n")
        (df / "governor").write_text("sgpu_governor\n", newline="\n")
        (df / "min_freq").write_text("303000\n", newline="\n")
        (df / "max_freq").write_text("500000\n", newline="\n")
        (df / "cur_freq").write_text("500000\n", newline="\n")

        ufc = sys_root / "devices" / "platform" / "exynos-ufcc" / "ufc"
        ufc.mkdir(parents=True, exist_ok=True)
        (ufc / "cpufreq_table").write_text("2803000 2515000 1824000 1344000 672000\n", newline="\n")
        (ufc / "cpufreq_max_limit").write_text("672000\n", newline="\n")
        (ufc / "cpufreq_min_limit").write_text("72000\n", newline="\n")

        migov_root = sys_root / "devices" / "platform" / "exynos-migov"
        for sub, fval in [("cl0", "1344000"), ("cl1", "2304000"), ("cl2", "2304000")]:
            cdir = migov_root / sub
            cdir.mkdir(parents=True, exist_ok=True)
            (cdir / f"{sub}_pm_qos_max_freq").write_text(fval + "\n", newline="\n")
        (migov_root / "gpu").mkdir(parents=True, exist_ok=True)
        (migov_root / "migov").mkdir(parents=True, exist_ok=True)
        (migov_root / "mif").mkdir(parents=True, exist_ok=True)
        (migov_root / "gpu" / "gpu_pm_qos_max_freq").write_text("949000\n", newline="\n")
        (migov_root / "mif" / "mif_pm_qos_max_freq").write_text("2028000\n", newline="\n")
        (migov_root / "migov" / "disable").write_text("0\n", newline="\n")

        mif = sys_root / "class" / "devfreq" / "17000010.devfreq_mif"
        mif.mkdir(parents=True, exist_ok=True)
        (mif / "available_frequencies").write_text("3172000 2028000 1352000 421000\n", newline="\n")
        (mif / "min_freq").write_text("421000\n", newline="\n")
        (mif / "max_freq").write_text("3172000\n", newline="\n")
    else:
        df = sys_root / "class" / "devfreq" / "13000000.mali"
        df.mkdir(parents=True, exist_ok=True)
        (df / "available_frequencies").write_text("218000000 450000000 720000000 981000000 1300000000\n", newline="\n")
        (df / "available_governors").write_text("coarse_demand simple_ondemand\n", newline="\n")
        (df / "governor").write_text("coarse_demand\n", newline="\n")
        (df / "min_freq").write_text("218000000\n", newline="\n")
        (df / "max_freq").write_text("1300000000\n", newline="\n")
        (df / "cur_freq").write_text("450000000\n", newline="\n")

    bus = sys_root / "class" / "devfreq" / "soc_qcom_cpu-llcc-ddr-bw"
    bus.mkdir(parents=True, exist_ok=True)
    (bus / "available_frequencies").write_text("1720 3180 5470 7980 12000\n", newline="\n")
    (bus / "min_freq").write_text("1720\n", newline="\n")

    blk = sys_root / "block" / "sda" / "queue"
    blk.mkdir(parents=True, exist_ok=True)
    (blk / "scheduler").write_text("none [mq-deadline] kyber\n", newline="\n")
    (blk / "read_ahead_kb").write_text("128\n", newline="\n")
    (sys_root / "block" / "zram0").mkdir(parents=True, exist_ok=True)

    batt = sys_root / "class" / "power_supply" / "battery"
    batt.mkdir(parents=True, exist_ok=True)
    (batt / "temp").write_text("380\n" if variant == "exynos" else "340\n", newline="\n")
    (batt / "batt_slate_mode").write_text("0\n", newline="\n")
    (batt / "capacity").write_text("88\n", newline="\n")
    (batt / "status").write_text("Charging\n", newline="\n")
    (batt / "current_now").write_text("-1200\n", newline="\n")
    (batt / "voltage_now").write_text("3950000\n", newline="\n")
    bl = sys_root / "class" / "backlight" / "panel"
    bl.mkdir(parents=True, exist_ok=True)
    (bl / "brightness").write_text("120\n", newline="\n")
    tz_cpu = sys_root / "class" / "thermal" / "thermal_zone0"
    tz_cpu.mkdir(parents=True, exist_ok=True)
    (tz_cpu / "type").write_text("BIG\n" if variant == "exynos" else "cpuss-0\n", newline="\n")
    (tz_cpu / "temp").write_text("63000\n" if variant == "exynos" else "46500\n", newline="\n")
    (tz_cpu / "trip_point_7_temp").write_text("125000\n", newline="\n")
    tz_gpu = sys_root / "class" / "thermal" / "thermal_zone1"
    tz_gpu.mkdir(parents=True, exist_ok=True)
    (tz_gpu / "type").write_text("G3D\n" if variant == "exynos" else "gpuss-0\n", newline="\n")
    (tz_gpu / "temp").write_text("61000\n" if variant == "exynos" else "44000\n", newline="\n")

    drm = sys_root / "class" / "drm" / "sde-crtc-0"
    drm.mkdir(parents=True, exist_ok=True)
    (drm / "measured_fps").write_text("fps: 119.8 duration:1001\n", newline="\n")

    tch = sys_root / "class" / "touch" / "touch_dev"
    tch.mkdir(parents=True, exist_ok=True)
    (tch / "bump_sample_rate").write_text("0\n", newline="\n")

    wlan = sys_root / "class" / "net" / "wlan0"
    wlan.mkdir(parents=True, exist_ok=True)
    (wlan / "operstate").write_text("up\n", newline="\n")

    uclamp = dev_root / "cpuctl" / "top-app"
    uclamp.mkdir(parents=True, exist_ok=True)
    (uclamp / "cpu.uclamp.min").write_text("0\n", newline="\n")
    (uclamp / "cpu.uclamp.max").write_text("max\n", newline="\n")
    (uclamp / "cpu.uclamp.latency_sensitive").write_text("0\n", newline="\n")
    (uclamp / "cgroup.procs").write_text("", newline="\n")
    (uclamp / "cgroup.threads").write_text("", newline="\n")
    (dev_root / "input").mkdir(parents=True, exist_ok=True)
    (dev_root / "input" / "event4").write_text("ev", newline="\n")

    (proc_root / "sys" / "vm").mkdir(parents=True, exist_ok=True)
    (proc_root / "sys" / "vm" / "swappiness").write_text("60\n", newline="\n")
    (proc_root / "sys" / "vm" / "vfs_cache_pressure").write_text("100\n", newline="\n")
    (proc_root / "pressure").mkdir(parents=True, exist_ok=True)
    (proc_root / "pressure" / "memory").write_text(
        "some avg10=12.40 avg60=6.00 avg300=2.00 total=100\nfull avg10=0.40 avg60=0.10 avg300=0.00 total=10\n",
        newline="\n",
    )
    (proc_root / "meminfo").write_text(
        "MemTotal:       12288000 kB\nMemFree:         1200000 kB\nMemAvailable:    4500000 kB\nSwapTotal:       4096000 kB\nSwapFree:        3800000 kB\n",
        newline="\n",
    )
    (proc_root / "cpuinfo").write_text("".join(f"processor\t: {i}\n" for i in range(8)), newline="\n")
    (proc_root / "stat").write_text("cpu  1200 100 600 8000 50 0 10 0 0 0\n", newline="\n")
    (proc_root / "bus" / "input").mkdir(parents=True, exist_ok=True)
    (proc_root / "bus" / "input" / "devices").write_text(
        'N: Name="fts_ts"\nH: Handlers=sysrq kbd event4 \n', newline="\n"
    )
    for pid, cmdline in [(1234, "com.tencent.ig"), (5678, "com.android.systemui"), (9999, "com.example.bgapp")]:
        pdir = proc_root / str(pid)
        pdir.mkdir(parents=True, exist_ok=True)
        (pdir / "cmdline").write_bytes(cmdline.encode() + b"\x00")
    for tid, tcomm in [(1235, "RenderThread"), (1236, "UnityMain")]:
        tdir = proc_root / "1234" / "task" / str(tid)
        tdir.mkdir(parents=True, exist_ok=True)
        (tdir / "comm").write_text(tcomm + "\n", newline="\n")

    cgroup_root = base / "cgroup"
    cgroup_root.mkdir(parents=True, exist_ok=True)
    pkgs_list = base / "packages.list"
    pkgs_list.write_text(
        "com.dts.freefireth 10236 0 /data/user/0/com.dts.freefireth default:targetSdkVersion=31 none 0 1 1 @null\n"
        "com.mock.bloat 10501 0 /data/user/0/com.mock.bloat default:targetSdkVersion=31 none 0 1 1 @null\n"
        "com.mock.dexapp 10502 0 /data/user/0/com.mock.dexapp default:targetSdkVersion=31 none 0 1 1 @null\n",
        newline="\n",
    )
    if variant == "exynos":
        for uid_val in [10501, 10502]:
            ud = cgroup_root / f"uid_{uid_val}"
            ud.mkdir(parents=True, exist_ok=True)
            (ud / "cgroup.freeze").write_text("0\n", newline="\n")
        for pid, uid_val, cmdline, adj in [
            (4001, 10501, "com.mock.bloat", 850),
            (4002, 10502, "com.mock.dexapp", 100),
        ]:
            pd = proc_root / str(pid)
            pd.mkdir(parents=True, exist_ok=True)
            (pd / "cmdline").write_bytes(cmdline.encode() + b"\x00")
            (pd / "status").write_text(f"Name:\t{cmdline}\nUid:\t{uid_val}\t{uid_val}\t{uid_val}\t{uid_val}\n", newline="\n")
            (pd / "oom_score_adj").write_text(f"{adj}\n", newline="\n")

    (mods_root / "my_spoof_mod").mkdir(parents=True, exist_ok=True)
    (mods_root / "my_spoof_mod" / "module.prop").write_text("id=my_spoof_mod\nname=Mock Spoof Conflict\n", newline="\n")
    (mods_root / "disabled_spoof").mkdir(parents=True, exist_ok=True)
    (mods_root / "disabled_spoof" / "disable").write_text("", newline="\n")

    if variant == "exynos":
        (mods_root / "rezygisk").mkdir(parents=True, exist_ok=True)
        (mods_root / "rezygisk" / "module.prop").write_text("id=rezygisk\nname=ReZygisk\n", newline="\n")
        sec_tsp = sys_root / "class" / "sec" / "tsp"
        sec_tsp.mkdir(parents=True, exist_ok=True)
        (sec_tsp / "cmd").write_text("OK\n", newline="\n")
        ext_dp = sys_root / "class" / "drm" / "card0-DP-1"
        ext_dp.mkdir(parents=True, exist_ok=True)
        (ext_dp / "status").write_text("disconnected\n", newline="\n")
        data_mod_dir = mod_copy / "data"
        data_mod_dir.mkdir(parents=True, exist_ok=True)
        if not (data_mod_dir / "kgx-display.dex").exists():
            (data_mod_dir / "kgx-display.dex").write_bytes(b"dex\n035\x00mock")

    props_db = base / "props.db"
    if variant == "exynos":
        props = {
            "ro.product.brand": "samsung",
            "ro.product.manufacturer": "samsung",
            "ro.product.model": "SM-S901B",
            "ro.product.device": "r0s",
            "ro.product.name": "r0sxeea",
            "ro.build.product": "r0s",
            "ro.build.fingerprint": "samsung/r0sxeea/r0s:12/SP1A.210812.016/S901BXXU2AVF5:user/release-keys",
            "ro.build.version.sdk": "31",
            "ro.product.cpu.abi": "arm64-v8a",
            "ro.board.platform": "universal9925",
            "ro.hardware": "s5e9925",
            "ro.soc.model": "s5e9925",
            "ro.hardware.egl": "samsung",
            "ro.serialno": "STOCK_SERIAL_EXY",
            "sys.usb.configured": "configured",
            "sys.usb.state": "mtp,adb",
            "sys.boot_completed": "1",
        }
    elif variant == "adreno":
        props = {
            "ro.product.brand": "Xiaomi",
            "ro.product.manufacturer": "Xiaomi",
            "ro.product.model": "23127PN0CG",
            "ro.product.device": "houji",
            "ro.product.name": "houji_global",
            "ro.build.product": "houji",
            "ro.build.fingerprint": "Xiaomi/houji_global/houji:14/UKQ1.230804.001/stock:user/release-keys",
            "ro.build.version.sdk": "34",
            "ro.product.cpu.abi": "arm64-v8a",
            "ro.board.platform": "pineapple",
            "ro.hardware": "qcom",
            "ro.hardware.egl": "adreno",
            "ro.serialno": "STOCK_SERIAL_12345",
            "sys.boot_completed": "1",
        }
    else:
        props = {
            "ro.product.brand": "Redmi",
            "ro.product.manufacturer": "Xiaomi",
            "ro.product.model": "23049PCD8G",
            "ro.product.device": "corot",
            "ro.product.name": "corot_global",
            "ro.build.product": "corot",
            "ro.build.fingerprint": "Xiaomi/corot_global/corot:14/UP1A.230905.011/stock:user/release-keys",
            "ro.build.version.sdk": "34",
            "ro.product.cpu.abi": "arm64-v8a",
            "ro.board.platform": "mt6989",
            "ro.hardware": "mt6989",
            "ro.hardware.egl": "mali",
            "ro.serialno": "STOCK_SERIAL_MTK",
            "sys.boot_completed": "1",
        }
    props_db.write_text("\n".join(f"{k}={v}" for k, v in props.items()) + "\n", newline="\n")

    settings_db = base / "settings.db"
    settings_db.write_text("", newline="\n")
    cmd_log = base / "cmd.log"
    am_log = base / "am.log"
    pm_log = base / "pm.log"
    pm_dis_db = base / "pm_disabled.txt"
    pm_dis_db.write_text("", newline="\n")
    app_log = base / "app_process.log"
    wm_log = base / "wm.log"
    sf_list_file = base / "sf_list.txt"
    sf_list_file.write_text(
        "com.dts.freefireth/com.dts.freefireth.FFMainActivity#0\n"
        "com.mock.dexapp/com.mock.dexapp.PopupWindow#0\n",
        newline="\n",
    )
    sf_disp_file = base / "sf_disp.txt"
    sf_disp_file.write_text("", newline="\n")
    disp_modes_file = base / "display_modes.txt"
    disp_modes_file.write_text(
        "supportedModes=[{id=1, width=1440, height=3200, fps=120.0}, {id=2, width=1440, height=3200, fps=90.0}, {id=3, width=1440, height=3200, fps=60.0}]\n"
        if variant == "adreno"
        else "supportedModes=[{id=1, width=1220, height=2712, fps=144.0}, {id=2, width=1220, height=2712, fps=120.0}, {id=3, width=1220, height=2712, fps=60.0}]\n",
        newline="\n",
    )

    m_props = to_msys(props_db)
    m_settings = to_msys(settings_db)
    m_cmdlog = to_msys(cmd_log)
    m_amlog = to_msys(am_log)
    m_pmlog = to_msys(pm_log)
    m_pmdis = to_msys(pm_dis_db)
    m_applog = to_msys(app_log)
    m_wmlog = to_msys(wm_log)
    m_sflist = to_msys(sf_list_file)
    m_sfdisp = to_msys(sf_disp_file)
    m_disp = to_msys(disp_modes_file)

    mocks = {
        "getprop": f'#!/bin/sh\nawk -F "=" -v k="$1" \'$1==k{{sub(/^[^=]*=/,""); print; exit}}\' "{m_props}"\n',
        "resetprop": f'#!/bin/sh\n'
                     f'if [ "$1" = "--delete" ]; then awk -F "=" -v k="$2" \'$1!=k\' "{m_props}" > "{m_props}.t" && mv "{m_props}.t" "{m_props}"; exit 0; fi\n'
                     f'[ "$1" = "-n" ] && shift\n'
                     f'awk -F "=" -v k="$1" -v v="$2" \'BEGIN{{f=0}} $1==k{{print k"="v; f=1; next}} {{print}} END{{if(!f) print k"="v}}\' "{m_props}" > "{m_props}.t" && mv "{m_props}.t" "{m_props}"\n',
        "settings": f'#!/bin/sh\n'
                    f'op="$1"; ns="$2"; key="$3"; val="$4"\n'
                    f'if [ "$op" = "get" ]; then out="$(awk -F "=" -v k="$ns.$key" \'$1==k{{print $2; exit}}\' "{m_settings}")"; printf "%s\\n" "${{out:-null}}"; exit 0; fi\n'
                    f'if [ "$op" = "put" ]; then awk -F "=" -v k="$ns.$key" -v v="$val" \'BEGIN{{f=0}} $1==k{{print k"="v; f=1; next}} {{print}} END{{if(!f) print k"="v}}\' "{m_settings}" > "{m_settings}.t" && mv "{m_settings}.t" "{m_settings}"; exit 0; fi\n'
                    f'if [ "$op" = "delete" ]; then awk -F "=" -v k="$ns.$key" \'$1!=k\' "{m_settings}" > "{m_settings}.t" && mv "{m_settings}.t" "{m_settings}"; exit 0; fi\n',
        "dumpsys": f'#!/bin/sh\n'
                   f'case "$1" in\n'
                   f'  display) cat "{m_disp}" ;;\n'
                   f'  activity) printf "  topResumedActivity=ActivityRecord{{abc u0 com.tencent.ig/com.epicgames.ue4.SplashActivity t1}}\\n" ;;\n'
                   f'  connectivity) printf "  NetworkAgentInfo{{WIFI VALIDATED}}\\n" ;;\n'
                   f'  power) printf "  mWakefulness=Awake\\n" ;;\n'
                   f'  SurfaceFlinger) if [ "$2" = "--list" ]; then cat "{m_sflist}" 2>/dev/null || true; else cat "{m_sfdisp}" 2>/dev/null || true; fi ;;\n'
                   f'esac\n',
        "wm": f'#!/bin/sh\n'
              f'if [ "$1" = "size" ] && [ -z "$2" ]; then\n'
              f'  printf "Physical size: 1080x2340\\n"\n'
              f'elif [ "$1" = "density" ] && [ -z "$2" ]; then\n'
              f'  printf "Physical density: 480\\n"\n'
              f'else\n'
              f'  printf "%s\\n" "$*" >> "{m_wmlog}"\n'
              f'fi\n',
        "cmd": f'#!/bin/sh\n'
               f'printf "%s\\n" "$*" >> "{m_cmdlog}"\n'
               f'exit 0\n',
        "pm": f'#!/bin/sh\n'
              f'if [ "$1" = "clear" ]; then\n'
              f'  printf "clear %s\\n" "$2" >> "{m_pmlog}"; exit 0\n'
              f'elif [ "$1" = "path" ] && [ "$2" = "com.samsung.android.game.gos" ]; then\n'
              f'  printf "package:/system/app/GOS/GOS.apk\\n"; exit 0\n'
              f'elif [ "$1" = "disable-user" ]; then\n'
              f'  shift; while [ "$1" = "--user" ] && [ $# -ge 2 ]; do shift 2; done\n'
              f'  printf "disable %s\\n" "$1" >> "{m_pmlog}"\n'
              f'  grep -qx "package:$1" "{m_pmdis}" 2>/dev/null || printf "package:%s\\n" "$1" >> "{m_pmdis}"\n'
              f'  exit 0\n'
              f'elif [ "$1" = "enable" ]; then\n'
              f'  printf "enable %s\\n" "$2" >> "{m_pmlog}"\n'
              f'  awk -v t="package:$2" \'$0!=t\' "{m_pmdis}" > "{m_pmdis}.t" && mv "{m_pmdis}.t" "{m_pmdis}"\n'
              f'  exit 0\n'
              f'elif [ "$1" = "list" ] && [ "$2" = "packages" ] && [ "$3" = "-d" ]; then\n'
              f'  cat "{m_pmdis}" 2>/dev/null || true; exit 0\n'
              f'fi\n'
              f'printf "package:com.tencent.ig uid:10234\\npackage:com.miHoYo.GenshinImpact uid:10235\\npackage:com.dts.freefireth uid:10236\\npackage:com.example.bgapp uid:10299\\n"\n',
        "am": f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{m_amlog}"\nexit 0\n',
        "app_process": f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{m_applog}"\nexit 0\n',
        "ping": '#!/bin/sh\n'
                'printf "4 packets transmitted, 4 received, 0% packet loss, time 3003ms\\nrtt min/avg/max/mdev = 14.120/16.450/20.110/2.150 ms\\n"\n',
        "renice": '#!/bin/sh\nexit 0\n',
        "pidof": '#!/bin/sh\n[ "$1" = "com.tencent.ig" ] && printf "1234\\n"\n[ "$1" = "com.dts.freefireth" ] && printf "1234\\n"\n',
        "getevent": '#!/bin/sh\n'
                    't=100.000000\n'
                    'for i in 1 2 3 4 5 6 7 8 9 10; do\n'
                    '  awk -v v="$t" \'BEGIN{printf "[%10.6f] 0000 0000 00000000\\n", v}\'\n'
                    '  t="$(awk -v v="$t" \'BEGIN{printf "%.6f", v + 0.004167}\')"\n'
                    'done\n',
        "timeout": '#!/bin/sh\nshift\n"$@"\n',
    }
    for name, body in mocks.items():
        p = mock_bin / name
        p.write_text(body, newline="\n")
        p.chmod(0o755)

    return {
        "PATH": f"{to_msys(mock_bin)}:" + ("/usr/bin:/bin" if IS_WIN else "/usr/local/bin:/usr/bin:/bin"),
        "KGX_MODDIR": to_msys(mod_copy),
        "KGX_DATA_DIR": to_msys(data_dir),
        "KGX_SYS_ROOT": to_msys(sys_root),
        "KGX_PROC_ROOT": to_msys(proc_root),
        "KGX_DEV_ROOT": to_msys(dev_root),
        "KGX_CGROUP_ROOT": to_msys(cgroup_root),
        "KGX_PKGS_LIST": to_msys(pkgs_list),
        "KGX_MODULES_ROOT": to_msys(mods_root),
        "KGX_RESETPROP_BIN": to_msys(mock_bin / "resetprop"),
        "KGX_DISABLE_RUST_CORE": "1",
    }


def stage_4_functional_e2e() -> None:
    # --- Part A: Adreno 8 Gen 3 Mock E2E ---
    with tempfile.TemporaryDirectory(prefix="kgx_e2e_adr_") as tmp:
        base = Path(tmp)
        env = create_mock_env(base, "adreno")
        kgxctl = to_msys(base / "module" / "bin" / "kgxctl")

        hw = json.loads(run_sh(f'sh "{kgxctl}" hw', env).stdout)
        assert_true(hw["gpu_vendor"] == "adreno" and hw["hw_tier"] == 3 and hw["display_max_hz"] == 120, f"Bad Adreno HW: {hw}")

        m = json.loads(run_sh(f'sh "{kgxctl}" profiles match com.tencent.ig', env).stdout)
        assert_true(m["recommended_id"] == "rog_phone_9_pro" and m["compat"] == "OPTIMAL", f"Expected rog_phone_9_pro, got {m}")

        # 5-Factor FPS cap on Genshin
        src_libs = (
            f'. "{env["KGX_MODDIR"]}/lib/common.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/hw_detect.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/matcher.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/fps.sh"\n'
            f'fps_analyze_json com.miHoYo.GenshinImpact 120 NORMAL 1\n'
        )
        fa_gen = json.loads(run_sh(src_libs, env).stdout)
        assert_true(fa_gen["effective_fps"] == 60 and fa_gen["primary_limiter"] == "GAME_LIMIT", f"Genshin FPS cap wrong: {fa_gen}")

        # Security blocklist + sysfs guard
        sec_test = (
            f'. "{env["KGX_MODDIR"]}/lib/common.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/hw_detect.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/matcher.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/spoof.sh"\n'
            f'spoof_set_prop_safe "$KGX_RESETPROP_BIN" ro.serialno HACKED && echo FAIL_SEC || echo PASS_SEC\n'
            f'spoof_set_prop_safe "$KGX_RESETPROP_BIN" ro.build.fingerprint HACKED/FP && echo FAIL_FP || echo PASS_FP\n'
            f'sysfs_safe_write "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/policy0/scaling_min_freq" 9999999 "$KGX_SYS_ROOT/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies" && echo FAIL_FREQ || echo PASS_FREQ\n'
            f'sysfs_safe_write "$KGX_SYS_ROOT/class/kgsl/kgsl-3d0/throttling" 0 && echo FAIL_THM || echo PASS_THM\n'
        )
        res = run_sh(sec_test, env)
        assert_true("PASS_SEC" in res.stdout and "PASS_FP" in res.stdout and "PASS_FREQ" in res.stdout and "PASS_THM" in res.stdout,
                    f"Safety guards failed: {res.stdout}")

        # Whole-System Persistent Spoof + Play Integrity legacy fingerprint cleanup
        # Simulate polluted ro.build.fingerprint from legacy v2.x before applying v3.0.0 spoof
        run_sh(f'sh "{kgxctl}" hw', env)
        run_sh(f'. "{env["KGX_MODDIR"]}/lib/common.sh"; . "{env["KGX_MODDIR"]}/lib/spoof.sh"; spoof_capture_original', env)
        run_sh(f'"{env["KGX_RESETPROP_BIN"]}" -n ro.build.fingerprint polluted/fp:15', env)

        ap_glob = json.loads(run_sh(f'sh "{kgxctl}" spoof apply-global galaxy_s26_ultra', env).stdout)
        assert_true(ap_glob["ok"] is True and ap_glob["model"] == "SM-S948B" and ap_glob["system_prop_written"] is True, f"apply-global failed: {ap_glob}")
        props_glob = (base / "props.db").read_text(encoding="utf-8")
        assert_true("ro.product.model=SM-S948B" in props_glob, f"Global model not applied: {props_glob}")
        assert_true("ro.product.marketname=Samsung Galaxy S26 Ultra" in props_glob, f"Marketname missing: {props_glob}")
        assert_true("ro.build.fingerprint=Xiaomi/houji_global/houji:14/UKQ1.230804.001/stock:user/release-keys" in props_glob,
                    f"Polluted fingerprint was not reverted to stock: {props_glob}")
        assert_true("ro.serialno=STOCK_SERIAL_12345" in props_glob, "ro.serialno altered!")

        sys_prop_txt = (base / "module" / "system.prop").read_text(encoding="utf-8")
        assert_true("ro.product.model=SM-S948B" in sys_prop_txt, "system.prop missing SM-S948B")
        assert_true("ro.build.fingerprint=" not in sys_prop_txt and "ro.product.vendor." not in sys_prop_txt and "ro.product.odm." not in sys_prop_txt,
                    f"Play Integrity risk: vendor/odm/fp found in system.prop: {sys_prop_txt}")

        # Apply game & check RAM/touch/cmd.log (NO cmd netpolicy and NO blunt am kill-all!)
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" games apply com.tencent.ig', env).stdout)["ok"] is True, "games apply failed")
        am_txt = (base / "am.log").read_text(encoding="utf-8")
        assert_true("kill-all" not in am_txt, f"Blunt am kill-all must never run during gaming session: {am_txt}")
        assert_true("com.example.bgapp" in am_txt and "com.android.systemui" not in am_txt and "com.tencent.ig" not in am_txt, f"RAM trim mismatch: {am_txt}")
        assert_true("netpolicy" not in (base / "cmd.log").read_text(encoding="utf-8"), "Forbidden netpolicy command executed!")

        # games restore preserves whole-system spoof, spoof restore reverts completely
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" games restore', env).stdout)["ok"] is True, "games restore failed")
        assert_true("ro.product.model=SM-S948B" in (base / "props.db").read_text(encoding="utf-8"), "games restore undid whole-system spoof")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" spoof restore', env).stdout)["ok"] is True, "spoof restore failed")
        assert_true("ro.product.model=23127PN0CG" in (base / "props.db").read_text(encoding="utf-8"), "spoof restore failed to revert model")
        assert_true(not (base / "module" / "system.prop").exists(), "spoof restore did not delete system.prop")

        # PLAY_INTEGRITY_SHIELD + SPOOF_EXCLUDE_SETTINGS + Spoof Denylist
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set PLAY_INTEGRITY_SHIELD 0', env).stdout)["ok"] is True, "Set PI Shield 0 failed")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine get', env).stdout)["PLAY_INTEGRITY_SHIELD"] == 0, "PI Shield get wrong")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set PLAY_INTEGRITY_SHIELD 1', env).stdout)["ok"] is True, "Set PI Shield 1 failed")

        eng0 = json.loads(run_sh(f'sh "{kgxctl}" engine get', env).stdout)
        assert_true(eng0.get("SPOOF_EXCLUDE_SETTINGS") == 1, f"SPOOF_EXCLUDE_SETTINGS default wrong: {eng0}")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set SPOOF_EXCLUDE_SETTINGS 0', env).stdout)["ok"] is True, "Set SPOOF_EXCLUDE_SETTINGS 0 failed")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set SPOOF_EXCLUDE_SETTINGS 1', env).stdout)["ok"] is True, "Set SPOOF_EXCLUDE_SETTINGS 1 failed")

        dl0 = json.loads(run_sh(f'sh "{kgxctl}" spoof denylist', env).stdout)
        assert_true(dl0["exclude_settings"] is True and dl0["count"] == 0, f"Initial denylist wrong: {dl0}")
        apps_j = json.loads(run_sh(f'sh "{kgxctl}" spoof apps', env).stdout)
        assert_true(apps_j["ok"] is True and "com.dts.freefireth" in apps_j["user_packages"], f"spoof apps failed: {apps_j}")
        dl_b64 = base64.b64encode(b"ru.andr7e.deviceinfohw\ncom.example.bank\n").decode()
        dl1 = json.loads(run_sh(f'sh "{kgxctl}" spoof denylist-set-b64 {dl_b64}', env).stdout)
        assert_true(dl1["count"] == 2 and "ru.andr7e.deviceinfohw" in dl1["packages"] and "com.example.bank" in dl1["packages"], f"denylist-set-b64 failed: {dl1}")
        dl2 = json.loads(run_sh(f'sh "{kgxctl}" spoof denylist-remove com.example.bank', env).stdout)
        assert_true(dl2["count"] == 1 and "com.example.bank" not in dl2["packages"], f"denylist-remove failed: {dl2}")
        dl3 = json.loads(run_sh(f'sh "{kgxctl}" spoof denylist-add com.example.bank', env).stdout)
        assert_true(dl3["count"] == 2 and "com.example.bank" in dl3["packages"], f"denylist-add failed: {dl3}")
        st_dl = json.loads(run_sh(f'sh "{kgxctl}" status', env).stdout)
        assert_true(st_dl["spoof"]["exclude_settings"] is True and st_dl["spoof"]["denylist_count"] == 2, f"status spoof denylist mismatch: {st_dl['spoof']}")

        for cmd in ["games list", "games scan", "profiles list com.tencent.ig", "profiles conflicts", "engine get", "touch measure", "net test 1.1.1.1", "logs 20"]:
            res = run_sh(f'sh "{kgxctl}" {cmd}', env)
            assert_true(res.returncode == 0, f"kgxctl {cmd} failed: {res.stderr}")
            parsed = json.loads(res.stdout)
            if cmd == "profiles conflicts":
                assert_true(parsed["conflict_count"] == 1 and parsed["conflicts"][0]["id"] == "my_spoof_mod", f"Conflict check wrong: {parsed}")
            if cmd == "touch measure":
                assert_true(parsed["hz"] == 240, f"Touch hz wrong: {parsed}")

        # Diagnostic report with PII/secret redaction check
        eng_log = base / "data" / "logs" / "engine.log"
        eng_log.parent.mkdir(parents=True, exist_ok=True)
        with eng_log.open("a", encoding="utf-8", newline="\n") as lf:
            lf.write(
                "[2026-11-22 12:00:00] [WARN] [test] serial=R5CT999FAKE MAC=AA:BB:CC:DD:EE:FF "
                "ghp_1234567890abcdef token=tok123 password=supersecret imei=123456789012345 "
                "864201020304050 user@example.com ip=192.168.1.42 ping=1.1.1.1\n"
            )
        diag_res = run_sh(f'sh "{kgxctl}" diag', env)
        assert_true(diag_res.returncode == 0 and "(v1.0.0)" in diag_res.stdout and "adreno" in diag_res.stdout,
                    f"kgxctl diag output invalid: {diag_res.stdout}")
        for leak in ["R5CT999FAKE", "AA:BB:CC:DD:EE:FF", "ghp_1234567890abcdef", "tok123", "supersecret", "123456789012345", "864201020304050", "user@example.com", "192.168.1.42"]:
            assert_true(leak not in diag_res.stdout, f"Sensitive leak '{leak}' in kgxctl diag:\n{diag_res.stdout}")
        for marker in ["[REDACTED_SECRET]", "[REDACTED_MAC]", "[REDACTED_ID]", "[REDACTED_EMAIL]", "[REDACTED_IP]", "1.1.1.1"]:
            assert_true(marker in diag_res.stdout, f"Missing expected marker '{marker}' in kgxctl diag:\n{diag_res.stdout}")
        assert_true(run_sh(f'sh "{kgxctl}" diag /tmp/bad_diag.txt', env).returncode != 0, "diag path guard failed")
        diag_out = json.loads(run_sh(f'sh "{kgxctl}" diag "{env["KGX_DATA_DIR"]}/logs/diag_out.txt"', env).stdout)
        assert_true(diag_out.get("ok") is True and (base / "data" / "logs" / "diag_out.txt").is_file(), f"diag file export failed: {diag_out}")

        # Custom profile, game upsert & backup roundtrip
        g_b64 = base64.b64encode(b"com.custom.game\t1\tauto\t90\thigh_performance\t90\tesports\t1").decode()
        p_b64 = base64.b64encode(b"my_custom\tMy Phone\tsnapdragon\tadreno\t3\t144\t16\tasus\tasus\tCUSTOM_M1\tC1\tC1_WW\t-\tTest").decode()
        for c in [f"games set-b64 {g_b64}", f"profiles create-b64 {p_b64}", "backup create pre_test"]:
            assert_true(json.loads(run_sh(f'sh "{kgxctl}" {c}', env).stdout)["ok"] is True, f"{c} failed")
        blist = json.loads(run_sh(f'sh "{kgxctl}" backup list', env).stdout)
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" backup restore {blist["backups"][0]["name"]}', env).stdout)["ok"] is True, "backup restore failed")

        # customize.sh legacy v2 config migration + set_perm arg check
        (base / "data" / "config" / "global.conf").write_text(
            "SPOOF_ENABLED=1\nSPOOF_MODE=zygisk\nSPOOF_MINIMAL_MODE=0\nNET_RESTRICT_BG=1\nGLOBAL_SPOOF_PROFILE=rog_phone_9_pro\n",
            newline="\n",
        )
        cust = to_msys(base / "module" / "customize.sh")
        cust_cmd = (
            'set_perm() { [ -e "$1" ] || { echo "BAD_SET_PERM:$*" >&2; return 1; }; chmod "$4" "$1"; }\n'
            f'ARCH=arm64 API=34 KSU=true MODPATH="{env["KGX_MODDIR"]}" . "{cust}"\n'
        )
        res_arm = run_sh(cust_cmd, env)
        assert_true(res_arm.returncode == 0 and "BAD_SET_PERM" not in res_arm.stderr, f"customize.sh failed: {res_arm.stdout} {res_arm.stderr}")
        mig_conf = (base / "data" / "config" / "global.conf").read_text(encoding="utf-8")
        assert_true("SPOOF_MODE=" not in mig_conf and "SPOOF_MINIMAL_MODE=" not in mig_conf and "NET_RESTRICT_BG=" not in mig_conf, f"Migration failed: {mig_conf}")
        assert_true("PLAY_INTEGRITY_SHIELD=1" in mig_conf and "SPOOF_EXCLUDE_SETTINGS=1" in mig_conf and "GLOBAL_SPOOF_PROFILE=rog_phone_9_pro" in mig_conf, f"Migration missing keys: {mig_conf}")

        # Bootloop guard
        pfs = to_msys(base / "module" / "post-fs-data.sh")
        run_sh(f'sh "{pfs}"', env)
        run_sh(f'sh "{pfs}"', env)
        assert_true("SAFE_MODE=1" in (base / "data" / "config" / "global.conf").read_text(encoding="utf-8"), "Bootloop guard failed")
        assert_true(not (base / "module" / "system.prop").exists(), "Bootloop guard did not remove system.prop")

        # Uninstall wipe
        res_un = run_sh(f'sh "{to_msys(base / "module" / "uninstall.sh")}"', env)
        assert_true(res_un.returncode == 0 and not (base / "data").exists(), "uninstall.sh failed")

    # --- Part B: Mali Mock Verification ---
    print("  -> Stage 4A (Adreno) passed; running Stage 4B (Mali)...", flush=True)
    with tempfile.TemporaryDirectory(prefix="kgx_e2e_mali_") as tmp:
        base = Path(tmp)
        env = create_mock_env(base, "mali")
        kgxctl = to_msys(base / "module" / "bin" / "kgxctl")
        hw = json.loads(run_sh(f'sh "{kgxctl}" hw', env).stdout)
        assert_true(hw["gpu_vendor"] == "mali" and hw["display_max_hz"] == 144, f"Mali HW wrong: {hw}")
        m = json.loads(run_sh(f'sh "{kgxctl}" profiles match com.tencent.ig', env).stdout)
        assert_true(m["recommended_id"] == "redmi_k80_ultra", f"Expected redmi_k80_ultra on Mali, got {m}")

    # --- Part C: Exynos 2200 Sustained Anti-Lag Thermal Engine ---
    print("  -> Stage 4B (Mali) passed; running Stage 4C (Exynos Xclipse Sustained Anti-Lag)...", flush=True)
    with tempfile.TemporaryDirectory(prefix="kgx_e2e_exy_") as tmp:
        base = Path(tmp)
        env = create_mock_env(base, "exynos")
        kgxctl = to_msys(base / "module" / "bin" / "kgxctl")

        hw = json.loads(run_sh(f'sh "{kgxctl}" hw', env).stdout)
        assert_true(hw["gpu_vendor"] == "xclipse" and hw["soc_vendor"] == "exynos", f"Exynos HW detect wrong: {hw}")

        assert_true(json.loads(run_sh(f'sh "{kgxctl}" spoof apply-global realme_14_5g', env).stdout)["ok"] is True, "Exynos apply-global failed")
        run_sh(f'sh "{kgxctl}" engine set THERMAL_UNLOCK 1', env)
        run_sh(f'sh "{kgxctl}" engine set MAX_CLOCK_LOCK 1', env)
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" games apply com.dts.freefireth', env).stdout)["ok"] is True, "Exynos apply failed")

        st = json.loads(run_sh(f'sh "{kgxctl}" status', env).stdout)
        assert_true(st["module_version"] == "v1.0.0" and st["thermal"]["stage"] == "UNLOCKED" and st["spoof"]["play_integrity_shield_active"] is True, f"Exynos status wrong: {st}")
        assert_true("gpu_max_mhz" in st["cpu_gpu"] and int(st["cpu_gpu"]["gpu_max_mhz"]) == 1306, f"Missing gpu_max_mhz telemetry: {st['cpu_gpu']}")
        assert_true("cpu_pct" in st["cpu_gpu"] and "gpu_pct" in st["cpu_gpu"], f"Missing cpu_pct/gpu_pct telemetry: {st['cpu_gpu']}")
        assert_true("ext_display" in st and st["ext_display"]["connected"] is False, f"Unexpected ext_display initial state: {st}")
        assert_true(st["power"]["bypass_supported"] is True and st["power"]["battery_pct"] == 88, f"Power telemetry wrong: {st['power']}")
        rgms = json.loads(run_sh(f'sh "{kgxctl}" spoof refresh-gms', env).stdout)
        assert_true(rgms.get("ok") is True and rgms.get("refreshed") is True, f"spoof refresh-gms failed: {rgms}")
        diag = json.loads(run_sh(f'sh "{kgxctl}" spoof diag', env).stdout)
        assert_true(diag.get("ok") is True and diag.get("fingerprint_stock") is True, f"spoof diag failed: {diag}")

        # Feature #3: Render-thread pinning check (1235 RenderThread / 1236 UnityMain)
        cg_threads = (base / "dev" / "cpuctl" / "top-app" / "cgroup.threads").read_text(encoding="utf-8").strip()
        assert_true(cg_threads in {"1235", "1236"}, f"Render-thread TID not pinned to top-app/cgroup.threads: {cg_threads!r}")

        # Feature #1: Bypass Charging apply (>= 80%), hysteresis drop (< 77%), & restore
        batt_slate = base / "sys" / "class" / "power_supply" / "battery" / "batt_slate_mode"
        batt_cap = base / "sys" / "class" / "power_supply" / "battery" / "capacity"
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set BYPASS_CHARGING 1', env).stdout)["ok"] is True, "Enable bypass failed")
        assert_true(batt_slate.read_text().strip() == "1", f"Bypass charging did not activate at 88%: {batt_slate.read_text()}")
        batt_cap.write_text("74\n", newline="\n")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" internal thermal-step', env).stdout)["ok"] is True, "thermal-step failed")
        assert_true(batt_slate.read_text().strip() == "0", "Bypass charging did not disable below hysteresis floor (74% < 77%)")
        batt_cap.write_text("88\n", newline="\n")
        run_sh(f'sh "{kgxctl}" engine set BYPASS_CHARGING 0', env)

        ufcc_max = base / "sys" / "devices" / "platform" / "exynos-ufcc" / "ufc" / "cpufreq_max_limit"
        p7_gov = base / "sys" / "devices" / "system" / "cpu" / "cpufreq" / "policy7" / "scaling_governor"
        p7_min = base / "sys" / "devices" / "system" / "cpu" / "cpufreq" / "policy7" / "scaling_min_freq"
        p7_max = base / "sys" / "devices" / "system" / "cpu" / "cpufreq" / "policy7" / "scaling_max_freq"
        g_min = base / "sys" / "kernel" / "gpu" / "gpu_min_clock"
        g_max = base / "sys" / "kernel" / "gpu" / "gpu_max_clock"

        assert_true(ufcc_max.read_text().strip() == "-1", "UFCC max limit not unlocked")
        assert_true(p7_gov.read_text().strip() == "schedutil", f"Must use responsive schedutil (not performance stove): {p7_gov.read_text()}")
        assert_true(p7_max.read_text().strip() == "2803000" and g_max.read_text().strip() == "1306000", "Max ceilings not 100% unlocked")
        assert_true(int(p7_min.read_text().strip()) < 2803000 and int(g_min.read_text().strip()) < 1306000,
                    "Stove prevention: idle min floor must remain below 100% peak")
        assert_true(stat.S_IMODE(ufcc_max.stat().st_mode) == 0o444, "UFCC ceiling not read-only 0444 locked")
        assert_true("global.restricted_device_performance=0,0" in (base / "settings.db").read_text(encoding="utf-8"),
                    "Samsung restricted_device_performance not cleared")

        # Anti-SError regression guard: gpu_ifpo_control must NEVER be touched or writable
        ifpo_node = base / "sys" / "kernel" / "gpu" / "gpu_ifpo_control"
        assert_true(ifpo_node.read_text(encoding="utf-8").strip() == "1",
                    f"gpu_ifpo_control was modified during game apply: {ifpo_node.read_text()!r}")
        ifpo_blk = run_sh(
            f'. "{env["KGX_MODDIR"]}/lib/common.sh"\n'
            f'sysfs_safe_write "$KGX_SYS_ROOT/kernel/gpu/gpu_ifpo_control" 0 && echo FAIL_IFPO || echo PASS_IFPO\n',
            env,
        )
        assert_true("PASS_IFPO" in ifpo_blk.stdout and ifpo_node.read_text(encoding="utf-8").strip() == "1",
                    f"sysfs_safe_write failed to block gpu_ifpo_control write: {ifpo_blk.stdout} {ifpo_node.read_text()!r}")

        # Simulate Samsung SDHMS dropping screen to 60Hz & silicon getting hot (82C CPU, 44C battery)
        (base / "sys" / "class" / "thermal" / "thermal_zone0" / "temp").write_text("82000\n", newline="\n")
        (base / "sys" / "class" / "power_supply" / "battery" / "temp").write_text("440\n", newline="\n")
        run_sh('settings put system min_refresh_rate 60', env)
        mon_test = (
            f'. "{env["KGX_MODDIR"]}/lib/common.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/hw_detect.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/matcher.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/fps.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/cpu_gpu.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/display.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/thermal.sh"\n'
            f'kgx_load_config\n'
            f'thermal_monitor_step com.dts.freefireth extreme_gaming 120 1234\n'
        )
        assert_true(run_sh(mon_test, env).returncode == 0, "thermal_monitor_step failed on hot transition")
        assert_true((base / "data" / "state" / "thermal_stage.state").read_text().strip() == "UNLOCKED_COOL",
                    "Failed to enter Anti-TMU UNLOCKED_COOL state")
        assert_true(p7_max.read_text().strip() == "2803000" and g_max.read_text().strip() == "1306000",
                    "UNLOCKED_COOL must keep MAX ceilings 100% unlocked!")
        assert_true(int(p7_min.read_text().strip()) <= 960000 and int(g_min.read_text().strip()) <= 500000,
                    f"UNLOCKED_COOL must relax idle min floors: p7={p7_min.read_text()} g={g_min.read_text()}")
        assert_true("system.min_refresh_rate=120" in (base / "settings.db").read_text(encoding="utf-8"),
                    "display_defend_hz failed to restore 120Hz after external drop to 60Hz")

        # Feature #3: Simulate stuck 'static' GPU governor (root/kernel-forced despite 0444 lock) and verify restore recovers dynamic governor
        gpu_gov_path = base / "sys" / "kernel" / "gpu" / "gpu_governor"
        os.chmod(gpu_gov_path, 0o644)
        gpu_gov_path.write_text("static\n", newline="\n")
        os.chmod(gpu_gov_path, 0o444)

        # Clean Exynos restore
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" games restore', env).stdout)["ok"] is True, "Exynos restore failed")
        assert_true(os.access(ufcc_max, os.W_OK) and ufcc_max.read_text().strip() == "672000", "UFCC not restored cleanly")
        assert_true(g_max.read_text().strip() == "303000", "GPU max clock not restored")
        assert_true(os.access(gpu_gov_path, os.W_OK) and gpu_gov_path.read_text().strip() in {"interactive", "amigo", "conservative"},
                    f"GPU governor remained stuck: {gpu_gov_path.read_text()}")
        assert_true("restricted_device_performance" not in (base / "settings.db").read_text(encoding="utf-8"),
                    "restricted_device_performance not deleted/restored cleanly")

        # Feature #2 (Sustained Sweet-Spot) & Feature #4/#10 (Per-game downscale pre-apply + wm_res + anti-PlatformCompat crash guard)
        (base / "wm.log").write_text("", newline="\n")
        ds_b64 = base64.b64encode(b"com.dts.freefireth\t1\tauto\t120\textreme_gaming\t120\tesports\t1\t0.85\t720x1280").decode()
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" games set-b64 {ds_b64}', env).stdout)["ok"] is True, "games set-b64 downscale failed")
        assert_true("game downscale 0.85 com.dts.freefireth" in (base / "cmd.log").read_text(encoding="utf-8"),
                    "Pre-apply downscale 0.85 not executed on games set-b64")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set THERMAL_UNLOCK 0', env).stdout)["ok"] is True, "Set THERMAL_UNLOCK 0 failed")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set MAX_CLOCK_LOCK 0', env).stdout)["ok"] is True, "Set MAX_CLOCK_LOCK 0 failed")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set SUSTAINED_SWEET_SPOT 1', env).stdout)["ok"] is True, "Set SUSTAINED_SWEET_SPOT 1 failed")
        (base / "sys" / "class" / "thermal" / "thermal_zone0" / "temp").write_text("60000\n", newline="\n")
        (base / "sys" / "class" / "power_supply" / "battery" / "temp").write_text("360\n", newline="\n")
        cmd_pre_apply = len((base / "cmd.log").read_text(encoding="utf-8"))
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" games apply com.dts.freefireth', env).stdout)["ok"] is True, "Sweet-Spot games apply failed")
        cmd_apply_delta = (base / "cmd.log").read_text(encoding="utf-8")[cmd_pre_apply:]
        assert_true("game downscale" not in cmd_apply_delta and "game mode" not in cmd_apply_delta,
                    f"fps_apply must NEVER mutate PlatformCompat/GameManager while PID is running: {cmd_apply_delta}")
        assert_true(int(p7_max.read_text().strip()) < 2803000 and int(g_max.read_text().strip()) < 1306000,
                    f"Sweet-Spot did not cap peaks below 100%: p7={p7_max.read_text()} g={g_max.read_text()}")
        st_sw = json.loads(run_sh(f'sh "{kgxctl}" status', env).stdout)
        assert_true(st_sw["thermal"]["stage"] == "SWEET_SPOT" and st_sw["sustained_sweet_spot"] is True, f"Sweet-Spot status wrong: {st_sw}")
        assert_true("--downscale 0.85" in (base / "cmd.log").read_text(encoding="utf-8"), "Downscale 0.85 not passed to cmd game set")
        assert_true("size 720x1280" in (base / "wm.log").read_text(encoding="utf-8") and (base / "data" / "state" / "active_res.env").is_file(),
                    "Per-game wm_res 720x1280 not applied cleanly")
        cmd_pre_restore = len((base / "cmd.log").read_text(encoding="utf-8"))
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" games restore', env).stdout)["ok"] is True, "Sweet-Spot restore failed")
        cmd_restore_delta = (base / "cmd.log").read_text(encoding="utf-8")[cmd_pre_restore:]
        assert_true("game downscale" not in cmd_restore_delta and "game mode" not in cmd_restore_delta,
                    f"Normal games restore must NOT mutate PlatformCompat/GameManager (kills minimized game): {cmd_restore_delta}")
        assert_true("size reset" in (base / "wm.log").read_text(encoding="utf-8") and not (base / "data" / "state" / "active_res.env").exists(),
                    "Per-game wm_res not reset cleanly on games restore")

        # Feature #3 (v3.3): Samsung GOS Neutralizer apply + restore
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set GOS_NEUTRALIZE 1', env).stdout)["ok"] is True, "Enable GOS_NEUTRALIZE failed")
        assert_true("disable com.samsung.android.game.gos" in (base / "pm.log").read_text(encoding="utf-8"), "GOS disable-user not executed")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set GOS_NEUTRALIZE 0', env).stdout)["ok"] is True, "Disable GOS_NEUTRALIZE failed")
        assert_true("enable com.samsung.android.game.gos" in (base / "pm.log").read_text(encoding="utf-8"), "GOS enable restore not executed")

        # v3.3 -> v3.4.0 Overlay-tick power/clock/alert telemetry (#1 & #18)
        ov = json.loads(run_sh(f'sh "{kgxctl}" overlay-tick', env).stdout)
        assert_true(
            ov.get("ok") is True and "cpu_pct" in ov and "gpu_pct" in ov and "ram_pct" in ov
            and int(ov.get("power_mw", 0)) == 4740 and "cpu_mhz" in ov and "gpu_mhz" in ov and "thermal_alert" in ov,
            f"overlay-tick invalid: {ov}",
        )

        # v3.3 External Display Auto-Screen-Off + Hard Safety Guards
        dp_status = base / "sys" / "class" / "drm" / "card0-DP-1" / "status"
        ext_state = base / "data" / "state" / "ext_internal_off.state"
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set EXT_DISPLAY_SCREEN_OFF 1', env).stdout)["ok"] is True, "Enable EXT_DISPLAY_SCREEN_OFF failed")
        refused = json.loads(run_sh(f'sh "{kgxctl}" display internal-power off', env).stdout)
        assert_true(refused.get("ok") is False and not ext_state.exists(), f"Safety guard failed to refuse internal off without external display: {refused}")

        dp_status.write_text("connected\n", newline="\n")
        sync_on = json.loads(run_sh(f'sh "{kgxctl}" display ext-sync', env).stdout)
        assert_true(sync_on["connected"] is True and sync_on["internal_screen_off"] is True and ext_state.is_file(), f"External display did not trigger internal screen off: {sync_on}")
        assert_true("DisplayPowerCtrl off" in (base / "app_process.log").read_text(encoding="utf-8"), "DisplayPowerCtrl off not invoked")

        dp_status.write_text("disconnected\n", newline="\n")
        sync_off = json.loads(run_sh(f'sh "{kgxctl}" display ext-sync', env).stdout)
        assert_true(sync_off["connected"] is False and sync_off["internal_screen_off"] is False and not ext_state.exists(), f"Disconnect did not restore internal screen: {sync_off}")
        assert_true("DisplayPowerCtrl on" in (base / "app_process.log").read_text(encoding="utf-8"), "DisplayPowerCtrl on not invoked on unplug")

        # Feature #5: Zero spurious Write failed + 0444 ceiling recovery test
        run_sh(f'sh "{kgxctl}" engine set SUSTAINED_SWEET_SPOT 0', env)
        run_sh(f'sh "{kgxctl}" engine set THERMAL_UNLOCK 1', env)
        run_sh(f'sh "{kgxctl}" games apply com.dts.freefireth', env)
        perm_bkp_txt = (base / "data" / "state" / "sysfs_perm_backup.tsv").read_text(encoding="utf-8")
        assert_true("\t444\n" not in perm_bkp_txt and "\t0444\n" not in perm_bkp_txt, f"0444 leaked into perm backup: {perm_bkp_txt}")
        os.chmod(p7_max, 0o644)
        p7_max.write_text("1440000\n", newline="\n")
        os.chmod(p7_max, 0o444)
        run_sh(f'sh "{kgxctl}" internal thermal-step', env)
        os.chmod(p7_max, 0o644)
        assert_true(p7_max.read_text().strip() == "2803000", f"thermal_defend_unlock_fast did not recover 0444 locked p7_max: {p7_max.read_text()}")
        eng_log_txt = (base / "data" / "logs" / "engine.log").read_text(encoding="utf-8")
        assert_true("Write failed for" not in eng_log_txt or "cpufreq_max_limit" not in eng_log_txt, f"Unexpected Write failed spam in engine.log: {eng_log_txt}")

        # Feature #6: Progressive Soft Thermal Step-Down (SOFT_THERMAL_STEP=1) + #18 Alert
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set SOFT_THERMAL_STEP 1', env).stdout)["ok"] is True, "Enable SOFT_THERMAL_STEP failed")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set THERMAL_ALERT_BATT_C 42', env).stdout)["ok"] is True, "Set THERMAL_ALERT_BATT_C failed")
        (base / "sys" / "class" / "power_supply" / "battery" / "temp").write_text("440\n", newline="\n")
        run_sh(f'sh "{kgxctl}" internal thermal-step', env)
        st_step = json.loads(run_sh(f'sh "{kgxctl}" status', env).stdout)
        os.chmod(p7_max, 0o644)
        assert_true(st_step["thermal"]["soft_step_tier"] == 2 and st_step["thermal"]["alert"] is True, f"Soft step or alert missing: {st_step['thermal']}")
        assert_true(int(p7_max.read_text().strip()) < 2803000, f"Soft step tier 2 did not lower policy7 cap: {p7_max.read_text()}")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set SOFT_THERMAL_STEP 0', env).stdout)["ok"] is True, "Disable SOFT_THERMAL_STEP failed")
        run_sh(f'sh "{kgxctl}" games restore', env)

        # Feature #10: System-wide Resolution Override (ext_scrcpy + always + wm reset safety)
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set RES_OVERRIDE_ENABLED 1', env).stdout)["ok"] is True, "Enable RES_OVERRIDE_ENABLED failed")
        assert_true(not (base / "data" / "state" / "active_res.env").exists(), "ext_scrcpy should not trigger wm size when disconnected")
        dp_status.write_text("connected\n", newline="\n")
        rs_on = json.loads(run_sh(f'sh "{kgxctl}" display res-sync', env).stdout)
        assert_true(rs_on["active"] is True and rs_on["current_res"] == "1080x1920", f"External DP did not trigger res override: {rs_on}")
        assert_true("size 1080x1920" in (base / "wm.log").read_text(encoding="utf-8"), "wm size 1080x1920 not logged")
        dp_status.write_text("disconnected\n", newline="\n")
        rs_off = json.loads(run_sh(f'sh "{kgxctl}" display res-sync', env).stdout)
        assert_true(rs_off["active"] is False and "size reset" in (base / "wm.log").read_text(encoding="utf-8"), f"Disconnect did not reset wm size: {rs_off}")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set RES_OVERRIDE_SCOPE always', env).stdout)["ok"] is True, "Set RES_OVERRIDE_SCOPE always failed")
        rs_all = json.loads(run_sh(f'sh "{kgxctl}" display res-status', env).stdout)
        assert_true(rs_all["active"] is True and rs_all["source"] == "global", f"Always scope failed: {rs_all}")

        # Feature #14: View & DeX-Safe cgroup v2 App Freezer
        frz_b64 = base64.b64encode(b"com.mock.bloat\ncom.mock.dexapp\ncom.android.systemui\n").decode()
        fz_set = json.loads(run_sh(f'sh "{kgxctl}" freezer set-b64 {frz_b64}', env).stdout)
        assert_true("com.android.systemui" not in fz_set["targets"] and len(fz_set["targets"]) == 2, f"Protected pkg not filtered from freezer: {fz_set}")
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" engine set FREEZER_ENABLED 1', env).stdout)["ok"] is True, "Enable FREEZER_ENABLED failed")
        fz_sync1 = json.loads(run_sh(f'sh "{kgxctl}" freezer sync com.dts.freefireth', env).stdout)
        fnode_bloat = base / "cgroup" / "uid_10501" / "cgroup.freeze"
        fnode_dex = base / "cgroup" / "uid_10502" / "cgroup.freeze"
        assert_true(fnode_bloat.read_text().strip() == "1", f"Idle bloat UID not frozen: {fz_sync1}")
        assert_true(fnode_dex.read_text().strip() == "0", f"Open View/DeX UID must NOT be frozen: {fz_sync1}")
        # User opens bloat app in Pop-up View / DeX -> oom_score_adj drops to 100 -> must auto-unfreeze immediately
        (base / "proc" / "4001" / "oom_score_adj").write_text("100\n", newline="\n")
        fz_sync2 = json.loads(run_sh(f'sh "{kgxctl}" freezer sync com.dts.freefireth', env).stdout)
        assert_true(fnode_bloat.read_text().strip() == "0" and fz_sync2["frozen_count"] == 0, f"Low-adj opened app did not auto-unfreeze: {fz_sync2}")
        (base / "proc" / "4001" / "oom_score_adj").write_text("850\n", newline="\n")
        run_sh(f'sh "{kgxctl}" freezer sync com.dts.freefireth', env)
        assert_true(fnode_bloat.read_text().strip() == "1", "Re-freeze before safemode failed")

        # S22 60Hz/120Hz LTPO Isolation, SurfaceFlinger Fallback, Never-Downgrade, SamHelper 120.1 & Boot Recovery Tests
        disp_modes_p = base / "display_modes.txt"
        sf_disp_p = base / "sf_disp.txt"
        hw_prof_p = base / "data" / "state" / "hw_profile.env"
        orig_disp_p = base / "data" / "state" / "orig_display.env"
        act_disp_p = base / "data" / "state" / "active_display.env"

        # 1) External HDMI 75Hz isolation (primary type INTERNAL + external type EXTERNAL)
        s22_disp_txt = (
            'DisplayDeviceInfo{"Internal": uniqueId="local:0", 1080 x 2340, supportedModes ['
            '{id=1, width=1080, height=2340, fps=120.00001}, {id=2, width=1080, height=2340, fps=96.0}, '
            '{id=3, width=1080, height=2340, fps=60.0}, {id=4, width=1080, height=2340, fps=48.0}, '
            '{id=5, width=1080, height=2340, fps=30.0}, {id=7, width=1080, height=2340, fps=10.0}], '
            'type INTERNAL, FLAG_DEFAULT_DISPLAY}\n'
            'DisplayDeviceInfo{"HDMI": uniqueId="local:1", 1920 x 1080, supportedModes ['
            '{id=8, width=1920, height=1080, fps=75.0}, {id=9, width=1920, height=1080, fps=60.0}, '
            '{id=10, width=1920, height=1080, fps=50.0}, {id=11, width=1920, height=1080, fps=70.0}], '
            'type EXTERNAL}\n'
        )
        disp_modes_p.write_text(s22_disp_txt, newline="\n")
        hw_ext = json.loads(run_sh(f'sh "{kgxctl}" hw', env).stdout)
        assert_true(hw_ext["display_max_hz"] == 120 and hw_ext["display_supported_hz"] == "30 48 60 96 120",
                    f"External HDMI Hz polluted primary display profile: {hw_ext}")

        # 2) SurfaceFlinger fallback when dumpsys display is empty + never-downgrade when both empty
        disp_modes_p.write_text("", newline="\n")
        sf_disp_p.write_text(
            "Display 4630946477092241537 (HWC display 0): port=129\n"
            "  Refresh rates:\n"
            "    {id=6, hwcId=14, fps=10.00, width=1080, height=2340 group=0}\n"
            "    {id=4, hwcId=10, fps=30.00, width=1080, height=2340 group=0}\n"
            "    {id=3, hwcId=8, fps=48.00, width=1080, height=2340 group=0}\n"
            "    {id=2, hwcId=5, fps=60.00, width=1080, height=2340 group=0}\n"
            "    {id=1, hwcId=4, fps=96.00, width=1080, height=2340 group=0}\n"
            "    {id=0, hwcId=3, fps=120.00, width=1080, height=2340 group=0}\n"
            "  Supports Frame Rate Override: true\n",
            newline="\n",
        )
        hw_sf = json.loads(run_sh(f'sh "{kgxctl}" hw', env).stdout)
        assert_true(hw_sf["display_max_hz"] == 120 and hw_sf["display_supported_hz"] == "30 48 60 96 120",
                    f"SurfaceFlinger fallback failed: {hw_sf}")

        sf_disp_p.write_text("", newline="\n")
        hw_nd = json.loads(run_sh(f'sh "{kgxctl}" hw', env).stdout)
        assert_true(hw_nd["display_max_hz"] == 120 and "DISPLAY_MAX_HZ='120'" in hw_prof_p.read_text(encoding="utf-8"),
                    f"hw_detect_all downgraded >60Hz profile to 60 on empty dumpsys: {hw_nd}")

        # 3) hw_load() self-heal when hw_profile.env was poisoned to 60Hz
        disp_modes_p.write_text(s22_disp_txt, newline="\n")
        hw_txt_poisoned = re.sub(r"DISPLAY_SUPPORTED_HZ='[^']*'", "DISPLAY_SUPPORTED_HZ='60'", hw_prof_p.read_text(encoding="utf-8"))
        hw_txt_poisoned = re.sub(r"DISPLAY_MAX_HZ='[^']*'", "DISPLAY_MAX_HZ='60'", hw_txt_poisoned)
        hw_prof_p.write_text(hw_txt_poisoned, newline="\n")
        heal_res = run_sh(
            f'. "{env["KGX_MODDIR"]}/lib/common.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/hw_detect.sh"\n'
            f'hw_load\n'
            f'printf "MEM_MAX=%s\\n" "$DISPLAY_MAX_HZ"\n',
            env,
        )
        assert_true("MEM_MAX=120" in heal_res.stdout and "DISPLAY_MAX_HZ='120'" in hw_prof_p.read_text(encoding="utf-8"),
                    f"hw_load failed to self-heal poisoned 60Hz hw_profile.env: {heal_res.stdout}")

        # 4) SamHelper 120.1 trap + missing ORIG_SEC_RRM + seamless refresh_rate_mode=1 on One UI 4.1
        act_disp_p.unlink(missing_ok=True)
        orig_disp_p.write_text(
            "ORIG_SYS_PEAK='120.1'\nORIG_SYS_MIN='120.1'\nORIG_SYS_USER='null'\nORIG_SEC_USER='null'\n",
            newline="\n",
        )
        run_sh('settings put system refresh_rate_mode 1; settings put secure refresh_rate_mode 0', env)
        run_sh(
            f'. "{env["KGX_MODDIR"]}/lib/common.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/hw_detect.sh"\n'
            f'. "{env["KGX_MODDIR"]}/lib/display.sh"\n'
            f'display_apply 120 explicit\n',
            env,
        )
        sdb = (base / "settings.db").read_text(encoding="utf-8")
        assert_true("secure.refresh_rate_mode=1" in sdb and "system.refresh_rate_mode=1" in sdb and "system.peak_refresh_rate=120" in sdb and "system.min_refresh_rate=120" in sdb,
                    f"display_apply 120 did not force seamless 120Hz: {sdb}")

        assert_true(json.loads(run_sh(f'sh "{kgxctl}" display restore', env).stdout)["ok"] is True, "display restore failed")
        sdb_rest = (base / "settings.db").read_text(encoding="utf-8")
        orig_mig = orig_disp_p.read_text(encoding="utf-8")
        assert_true("system.peak_refresh_rate=120.0" in sdb_rest and "system.min_refresh_rate=120.0" in sdb_rest and "120.1" not in sdb_rest,
                    f"SamHelper 120.1 leaked on restore: {sdb_rest}")
        assert_true("ORIG_SYS_PEAK='120.0'" in orig_mig and "ORIG_SEC_RRM='1'" in orig_mig,
                    f"orig_display.env migration failed: {orig_mig}")

        # 5) Interrupted session recovery (active_display.env + 60/60 -> kgxctl display recover)
        act_disp_p.write_text("ACTIVE_DISPLAY_HZ=60\n", newline="\n")
        run_sh('settings put system min_refresh_rate 60; settings put system peak_refresh_rate 60', env)
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" display recover', env).stdout)["ok"] is True, "display recover failed")
        sdb_rec = (base / "settings.db").read_text(encoding="utf-8")
        assert_true("system.peak_refresh_rate=120.0" in sdb_rec and "system.min_refresh_rate=120.0" in sdb_rec and not act_disp_p.exists(),
                    f"display recover left 60Hz stuck or kept active_display.env: {sdb_rec}")

        # Safe Mode auto-rollback for GOS, External Display internal screen-off, Resolution Override & Freezer
        dp_status.write_text("connected\n", newline="\n")
        run_sh(f'sh "{kgxctl}" engine set GOS_NEUTRALIZE 1', env)
        run_sh(f'sh "{kgxctl}" display ext-sync', env)
        assert_true(ext_state.is_file(), "Setup ext_state before safemode failed")
        cmd_pre_len = len((base / "cmd.log").read_text(encoding="utf-8"))
        assert_true(json.loads(run_sh(f'sh "{kgxctl}" safemode on', env).stdout)["safe_mode"] is True, "safemode on failed")
        assert_true(not ext_state.exists(), "safemode on did not restore internal display power")
        assert_true((base / "pm_disabled.txt").read_text(encoding="utf-8").strip() == "", "safemode on did not re-enable GOS")
        assert_true(not (base / "data" / "state" / "active_res.env").exists(), "safemode on did not reset wm resolution override")
        assert_true(fnode_bloat.read_text().strip() == "0", "safemode on did not unfreeze all apps")
        cmd_post = (base / "cmd.log").read_text(encoding="utf-8")[cmd_pre_len:]
        assert_true("downscale disable com.dts.freefireth" in cmd_post, f"safemode on did not disable Android 12 downscale: {cmd_post}")

    print("[PASS] Stage 4: End-to-End POSIX functional mock suite passed (Adreno + Mali + Exynos Sweet-Spot/Bypass/GOS/ExtDisplay/Overlay/Res/Freezer/SoftStep/Alert).")


# ---------------------------------------------------------------------------
# Stage 5: No-WebUI Removal & Standalone Rust Companion App API Audit
# ---------------------------------------------------------------------------
def stage_5_no_webui_and_companion_audit() -> None:
    assert_true(not (MOD_DIR / "webroot").exists(), "module/webroot must NOT exist in v3.3.0 (WebUI removed)!")

    java_dir = ROOT / "companion" / "android-app" / "java" / "com" / "kgx" / "ultimate"
    java_files = sorted(java_dir.glob("*.java"))
    assert_true(len(java_files) >= 10, f"Expected >= 10 Java sources in companion app v3.3.0, found {len(java_files)}")

    kgxctl_txt = (MOD_DIR / "bin" / "kgxctl").read_text(encoding="utf-8")
    valid_top = {
        "status", "hw", "games", "profiles", "spoof", "engine",
        "touch", "net", "backup", "logs", "safemode", "daemon", "system", "rollback",
        "display", "overlay-tick", "freezer", "diag",
    }
    called_cmds: set[str] = set()
    for p in java_files:
        txt = p.read_text(encoding="utf-8")
        assert_true(txt.count("{") == txt.count("}"), f"Unbalanced braces in {p.name}")
        assert_true(
            not re.search(r"\bNET_RESTRICT_BG\b|\bSPOOF_MODE\b|\bSPOOF_MINIMAL_MODE\b", txt),
            f"Deprecated control found in {p.name}",
        )
        assert_true("PI_EXTRA_PKGS" not in txt, f"Excluded #7 banking spoof config found in {p.name}")
        called_cmds.update(re.findall(r'(?:RustBridge\.call|runAction)\(\s*"([^"]+)"', txt))

    manifest = (ROOT / "companion" / "android-app" / "AndroidManifest.xml").read_text(encoding="utf-8")
    for perm_or_svc in [
        "SYSTEM_ALERT_WINDOW",
        "FOREGROUND_SERVICE_SPECIAL_USE",
        "BIND_QUICK_SETTINGS_TILE",
        "QUERY_ALL_PACKAGES",
        "KgxOverlayService",
        "KgxModeTileService",
        "KgxBypassTileService",
        "KgxOverlayTileService",
    ]:
        assert_true(perm_or_svc in manifest, f"Missing v3.3.0 manifest entry: {perm_or_svc}")

    main_java = (java_dir / "MainActivity.java").read_text(encoding="utf-8")
    assert_true(len(called_cmds) >= 10, f"Expected companion app to wire core commands, got {called_cmds}")
    for cmd in called_cmds:
        assert_true(cmd in valid_top and f"{cmd})" in kgxctl_txt, f"Companion app calls unknown kgxctl command: {cmd}")

    assert_true("refresh-gms)" in kgxctl_txt and '"refresh-gms"' in main_java, "spoof refresh-gms not wired")
    assert_true("denylist-set-b64)" in kgxctl_txt and '"denylist-set-b64"' in main_java, "spoof denylist not wired")
    assert_true("diag)" in kgxctl_txt and '"diag"' in main_java, "spoof diag not wired")
    assert_true("soft-reboot)" in kgxctl_txt and '"soft-reboot"' in main_java, "system soft-reboot not wired")
    assert_true("display)" in kgxctl_txt and '"display"' in main_java, "display command not wired")
    for req in [
        "DashboardHolder", "updateDashboardInPlace", "showAddAppDialog", "showSpoofDenylistPickerDialog",
        "SPOOF_EXCLUDE_SETTINGS", "SUSTAINED_SWEET_SPOT", "BYPASS_CHARGING", "downscale",
        "GOS_NEUTRALIZE", "EXT_DISPLAY_SCREEN_OFF", "SessionRecorder", "TelemetryChartView",
        "SOFT_THERMAL_STEP", "RES_OVERRIDE_ENABLED", "FREEZER_ENABLED", "THERMAL_ALERT_ENABLED",
        "METRIC_POWER",
    ]:
        assert_true(req in main_java, f"Missing v3.4.0 feature symbol '{req}' in MainActivity.java")
    ov_java = (java_dir / "KgxOverlayService.java").read_text(encoding="utf-8")
    assert_true("ACTION_TOGGLE_LOCK" in ov_java and "FLAG_NOT_TOUCHABLE" in ov_java, "Missing click-through lock in KgxOverlayService.java")

    print(f"[PASS] Stage 5: WebUI removal, excluded #7 check & Companion App ({len(java_files)} Java files) API aligned.")


# ---------------------------------------------------------------------------
# Stage 6: Module ZIP Integrity, ELF Binaries & Checksum Audit
# ---------------------------------------------------------------------------
def stage_6_zip_audit() -> None:
    assert_true(DIST_ZIP.is_file(), f"ZIP not found: {DIST_ZIP}")
    assert_true(DIST_ZIP_SHA.is_file(), f"SHA256 file not found: {DIST_ZIP_SHA}")

    expected_sha = DIST_ZIP_SHA.read_text(encoding="utf-8").split()[0]
    actual_sha = hashlib.sha256(DIST_ZIP.read_bytes()).hexdigest()
    assert_true(expected_sha == actual_sha, "ZIP SHA256 checksum mismatch!")

    with zipfile.ZipFile(DIST_ZIP, "r") as zf:
        bad = zf.testzip()
        assert_true(bad is None, f"ZIP CRC failure on: {bad}")
        names = set(zf.namelist())
        assert_true("system.prop" not in names, "system.prop must NOT be pre-baked in ZIP!")
        assert_true(not any(n.startswith("webroot/") or n == "webroot" for n in names), "ZIP must NOT contain webroot/!")
        for req in [
            "module.prop", "customize.sh", "post-fs-data.sh", "service.sh",
            "uninstall.sh", "action.sh", "bin/kgxctl", "bin/kgx-core", "bin/gaming_daemon.sh",
            "lib/power.sh", "lib/gos.sh", "lib/freezer.sh", "data/kgx-display.dex",
            "META-INF/com/google/android/update-binary",
            "data/devices.tsv", "data/games.tsv", "zygisk/arm64-v8a.so",
            "LICENSE", "NOTICE",
        ]:
            assert_true(req in names, f"Missing required ZIP root entry: {req}")

        dex = zf.read("data/kgx-display.dex")
        assert_true(dex.startswith(b"dex\n"), "data/kgx-display.dex is not a valid Android DEX")

        # Verify Zygisk Play Integrity Shield SO
        elf_z = zf.read("zygisk/arm64-v8a.so")
        assert_true(elf_z[:4] == b"\x7fELF" and struct.unpack("<H", elf_z[18:20])[0] == 183, "zygisk/arm64-v8a.so invalid AArch64 ELF")
        assert_true(b"libc++_shared.so" not in elf_z, "zygisk/arm64-v8a.so must NOT dynamically depend on libc++_shared.so!")
        assert_true(
            b"zygisk_module_entry" in elf_z
            and b"zygisk_companion_entry" in elf_z
            and b"com.google.android.gms." in elf_z
            and b"com.android.vending" in elf_z
            and b"com.android.settings" in elf_z
            and b"spoof_denylist.list" in elf_z
            and b"android/os/SystemProperties" in elf_z
            and b"__system_property_read_callback" in elf_z,
            "Missing Zygisk/PI-Shield symbols in zygisk/arm64-v8a.so",
        )

        # Verify Rust ARM64 kgx-core binary
        elf_r = zf.read("bin/kgx-core")
        assert_true(elf_r[:4] == b"\x7fELF" and struct.unpack("<H", elf_r[18:20])[0] == 183, "bin/kgx-core invalid AArch64 ELF")
        for sym in [b"kgx-core v1.0.0", b"power_mw", b"soft_step", b"cgroup.freeze", b"SurfaceFlinger", b"sf_ready", b"sf_flip", b"1013", b"pi-diag", b"overlay-tick", b"daemon"]:
            assert_true(sym in elf_r, f"bin/kgx-core missing {sym!r}")

        for zi in zf.infolist():
            if zi.filename.endswith("/"):
                continue
            mode = stat.S_IMODE(zi.external_attr >> 16)
            if zi.filename.endswith(".sh") or zi.filename in {"bin/kgxctl", "bin/kgx-core", "META-INF/com/google/android/update-binary"}:
                assert_true(mode == 0o755, f"Expected 0755 on {zi.filename}, got {oct(mode)}")
                if zi.filename != "bin/kgx-core":
                    assert_true(b"\r\n" not in zf.read(zi.filename), f"CRLF inside zipped {zi.filename}")
            else:
                assert_true(mode == 0o644, f"Expected 0644 on {zi.filename}, got {oct(mode)}")

    print(f"[PASS] Stage 6: Module ZIP, Rust ELF (kgx-core), Display DEX, Zygisk ELF & SHA256 verified ({DIST_ZIP.name}).")


# ---------------------------------------------------------------------------
# Stage 7: Standalone Signed Rust Companion APK Audit
# ---------------------------------------------------------------------------
def stage_7_apk_audit() -> None:
    assert_true(DIST_APK.is_file(), f"APK not found: {DIST_APK}")
    assert_true(DIST_APK_SHA.is_file(), f"APK SHA256 file not found: {DIST_APK_SHA}")

    expected_sha = DIST_APK_SHA.read_text(encoding="utf-8").split()[0]
    actual_sha = hashlib.sha256(DIST_APK.read_bytes()).hexdigest()
    assert_true(expected_sha == actual_sha, "APK SHA256 checksum mismatch!")

    with zipfile.ZipFile(DIST_APK, "r") as zf:
        bad = zf.testzip()
        assert_true(bad is None, f"APK ZIP CRC failure on: {bad}")
        names = set(zf.namelist())
        for req in ["AndroidManifest.xml", "resources.arsc", "classes.dex", "lib/arm64-v8a/libkgx_rust.so", "assets/LICENSE", "assets/NOTICE"]:
            assert_true(req in names, f"Missing required APK entry: {req}")
        assert_true(zf.getinfo("resources.arsc").compress_type == zipfile.ZIP_STORED, "resources.arsc must be STORED")
        assert_true(zf.getinfo("lib/arm64-v8a/libkgx_rust.so").compress_type == zipfile.ZIP_STORED, "libkgx_rust.so must be STORED")

        so = zf.read("lib/arm64-v8a/libkgx_rust.so")
        assert_true(so[:4] == b"\x7fELF" and struct.unpack("<H", so[18:20])[0] == 183, "libkgx_rust.so invalid AArch64 ELF")
        assert_true(b"Java_com_kgx_ultimate_RustBridge_nativeExec" in so, "Missing JNI symbol nativeExec in libkgx_rust.so")
        assert_true(b"Java_com_kgx_ultimate_RustBridge_nativeCheckRoot" in so, "Missing JNI symbol nativeCheckRoot in libkgx_rust.so")
        assert_true(b"Rust Core v1.0.0" in so, "Missing v1.0.0 string in libkgx_rust.so")

    assert_true(APKSIGNER.is_file(), f"apksigner not found for Stage 7 verification: {APKSIGNER}")
    res = subprocess.run([str(APKSIGNER), "verify", str(DIST_APK)], capture_output=True, text=True)
    assert_true(res.returncode == 0, f"apksigner verify failed: {res.stdout}\n{res.stderr}")

    print(f"[PASS] Stage 7: Signed Rust Companion APK, JNI ARM64 ELF & SHA256 verified ({DIST_APK.name}).")


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify KSU Ultimate Gaming X v1.0.0")
    parser.add_argument("--skip-apk", action="store_true", help="Skip Stage 7 signed APK check (for headless CI)")
    args = parser.parse_args()

    stages = [
        stage_1_shell_syntax,
        stage_2_hygiene,
        stage_3_databases,
        stage_4_functional_e2e,
        stage_5_no_webui_and_companion_audit,
        stage_6_zip_audit,
    ]
    if not args.skip_apk:
        stages.append(stage_7_apk_audit)
    for fn in stages:
        fn()
    if args.skip_apk:
        print("\nALL 6 VERIFICATION STAGES PASSED SUCCESSFULLY (--skip-apk).")
    else:
        print("\nALL 7 VERIFICATION STAGES PASSED SUCCESSFULLY.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"\n[FAIL] {exc}", file=sys.stderr)
        sys.exit(1)
