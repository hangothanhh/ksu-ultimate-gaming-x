// SPDX-License-Identifier: GPL-3.0-or-later
package com.kgx.ultimate;

import android.content.Context;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

public final class SessionRecorder {
    private static final int MAX_RECORDINGS = 50;

    public static final class Sample {
        public long ts;
        public int fps;
        public int low1;
        public int cpuPct;
        public int cpuC;
        public int cpuMhz;
        public int gpuPct;
        public int gpuMhz;
        public int gpuC;
        public int ramUsedMb;
        public int ramTotalMb;
        public int ramPct;
        public int battC;
        public int battPct;
        public int powerMw;
        public boolean charging;
        public int softStep;
        public boolean thermalAlert;
        public String thermalAlertMsg = "";
    }

    public static final class Summary {
        public File file;
        public String pkg;
        public long startEpoch;
        public long durationSec;
        public int sampleCount;
        public int avgFps;
        public int low1Fps;
        public int minFps;
        public int maxFps;
        public int avgCpuPct;
        public int maxCpuC;
        public int avgGpuPct;
        public int maxGpuC;
        public int avgRamPct;
        public int maxBattC;
        public int avgPowerMw;
        public int maxPowerMw;
    }

    private final File dir;
    private final File outFile;
    private String pkg;
    private final long startEpoch;
    private final List<Sample> samples = new ArrayList<>();
    private BufferedWriter rawWriter;

    public SessionRecorder(Context ctx, String pkgName) {
        this.dir = new File(ctx.getFilesDir(), "recordings");
        if (!dir.exists()) {
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
        }
        this.startEpoch = System.currentTimeMillis() / 1000L;
        String cleanPkg = (pkgName == null || pkgName.trim().isEmpty()) ? "system" : pkgName.trim();
        this.pkg = cleanPkg;
        String safeFile = cleanPkg.replaceAll("[^A-Za-z0-9._-]", "_");
        this.outFile = new File(dir, "rec_" + startEpoch + "_" + safeFile + ".csv");
        try {
            rawWriter = new BufferedWriter(new FileWriter(outFile, false));
            rawWriter.write("# pkg=" + cleanPkg + ";start=" + startEpoch + ";dur=0;samples=0;avg_fps=0;low1_fps=0;min_fps=0;max_fps=0;avg_cpu=0;max_cpu_c=0;avg_gpu=0;max_gpu_c=0;avg_ram=0;max_batt_c=0;avg_power_mw=0;max_power_mw=0\n");
            rawWriter.write("ts,fps,low1,cpu_pct,cpu_c,cpu_mhz,gpu_pct,gpu_mhz,gpu_c,ram_used_mb,ram_total_mb,ram_pct,batt_c,batt_pct,power_mw\n");
            rawWriter.flush();
        } catch (Throwable ignored) {
        }
    }

    public synchronized void updatePkgIfGeneric(String p) {
        if (p == null) return;
        String t = p.trim();
        if (t.isEmpty() || "com.kgx.ultimate".equals(t)) return;
        if ("overlay".equals(pkg) || "game".equals(pkg) || "system".equals(pkg) || "com.kgx.ultimate".equals(pkg)) {
            this.pkg = t;
        }
    }

    public synchronized void record(Sample s) {
        if (s == null) return;
        samples.add(s);
        if (rawWriter != null) {
            try {
                rawWriter.write(formatCsvRow(s));
                if (samples.size() % 5 == 0) {
                    rawWriter.flush();
                }
            } catch (Throwable ignored) {
            }
        }
    }

    public synchronized long getDurationSec() {
        return Math.max(0L, (System.currentTimeMillis() / 1000L) - startEpoch);
    }

    public synchronized int getSampleCount() {
        return samples.size();
    }

    public synchronized File stop() {
        try {
            if (rawWriter != null) {
                rawWriter.flush();
                rawWriter.close();
                rawWriter = null;
            }
        } catch (Throwable ignored) {
        }

        if (samples.isEmpty()) {
            //noinspection ResultOfMethodCallIgnored
            outFile.delete();
            return null;
        }

        Summary sum = computeSummary(outFile, pkg, startEpoch, samples);
        File tmp = new File(dir, outFile.getName() + ".tmp");
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(tmp, false))) {
            bw.write(String.format(
                Locale.US,
                "# pkg=%s;start=%d;dur=%d;samples=%d;avg_fps=%d;low1_fps=%d;min_fps=%d;max_fps=%d;avg_cpu=%d;max_cpu_c=%d;avg_gpu=%d;max_gpu_c=%d;avg_ram=%d;max_batt_c=%d;avg_power_mw=%d;max_power_mw=%d\n",
                sum.pkg, sum.startEpoch, sum.durationSec, sum.sampleCount,
                sum.avgFps, sum.low1Fps, sum.minFps, sum.maxFps,
                sum.avgCpuPct, sum.maxCpuC, sum.avgGpuPct, sum.maxGpuC,
                sum.avgRamPct, sum.maxBattC, sum.avgPowerMw, sum.maxPowerMw
            ));
            bw.write("ts,fps,low1,cpu_pct,cpu_c,cpu_mhz,gpu_pct,gpu_mhz,gpu_c,ram_used_mb,ram_total_mb,ram_pct,batt_c,batt_pct,power_mw\n");
            for (Sample s : samples) {
                bw.write(formatCsvRow(s));
            }
            bw.flush();
        } catch (Throwable ignored) {
        }
        if (tmp.isFile()) {
            //noinspection ResultOfMethodCallIgnored
            outFile.delete();
            //noinspection ResultOfMethodCallIgnored
            tmp.renameTo(outFile);
        }
        pruneOld(dir);
        return outFile;
    }

    private static String formatCsvRow(Sample s) {
        return s.ts + "," + s.fps + "," + s.low1 + ","
            + s.cpuPct + "," + s.cpuC + "," + s.cpuMhz + ","
            + s.gpuPct + "," + s.gpuMhz + "," + s.gpuC + ","
            + s.ramUsedMb + "," + s.ramTotalMb + "," + s.ramPct + ","
            + s.battC + "," + s.battPct + "," + s.powerMw + "\n";
    }

    private static Summary computeSummary(File f, String pkg, long startEpoch, List<Sample> rows) {
        Summary sum = new Summary();
        sum.file = f;
        sum.pkg = pkg;
        sum.startEpoch = startEpoch;
        sum.sampleCount = rows.size();
        if (rows.isEmpty()) return sum;

        long firstTs = rows.get(0).ts;
        long lastTs = rows.get(rows.size() - 1).ts;
        sum.durationSec = Math.max(rows.size(), lastTs - firstTs + 1);

        long fpsSum = 0;
        int fpsCnt = 0;
        int minFps = Integer.MAX_VALUE;
        int maxFps = 0;
        List<Integer> validFps = new ArrayList<>();
        long cpuSum = 0;
        long gpuSum = 0;
        long ramSum = 0;
        long pwrSum = 0;
        int pwrCnt = 0;
        int maxCpuC = 0;
        int maxGpuC = 0;
        int maxBattC = 0;
        int maxPwrMw = 0;

        for (Sample s : rows) {
            if (s.fps > 0) {
                fpsSum += s.fps;
                fpsCnt++;
                if (s.fps < minFps) minFps = s.fps;
                if (s.fps > maxFps) maxFps = s.fps;
                validFps.add(s.fps);
            }
            cpuSum += s.cpuPct;
            gpuSum += s.gpuPct;
            ramSum += s.ramPct;
            if (s.powerMw > 0) {
                pwrSum += s.powerMw;
                pwrCnt++;
                if (s.powerMw > maxPwrMw) maxPwrMw = s.powerMw;
            }
            if (s.cpuC > maxCpuC) maxCpuC = s.cpuC;
            if (s.gpuC > maxGpuC) maxGpuC = s.gpuC;
            if (s.battC > maxBattC) maxBattC = s.battC;
        }

        if (fpsCnt > 0) {
            sum.avgFps = Math.round((float) fpsSum / fpsCnt);
            sum.minFps = minFps;
            sum.maxFps = maxFps;
            validFps.sort(Integer::compareTo);
            int k = Math.max(1, validFps.size() / 100);
            long lowSum = 0;
            for (int i = 0; i < k; i++) lowSum += validFps.get(i);
            sum.low1Fps = Math.round((float) lowSum / k);
        }
        sum.avgCpuPct = Math.round((float) cpuSum / rows.size());
        sum.avgGpuPct = Math.round((float) gpuSum / rows.size());
        sum.avgRamPct = Math.round((float) ramSum / rows.size());
        sum.maxCpuC = maxCpuC;
        sum.maxGpuC = maxGpuC;
        sum.maxBattC = maxBattC;
        sum.avgPowerMw = pwrCnt > 0 ? Math.round((float) pwrSum / pwrCnt) : 0;
        sum.maxPowerMw = maxPwrMw;
        return sum;
    }

    private static void pruneOld(File dir) {
        File[] files = dir.listFiles((d, n) -> n.endsWith(".csv"));
        if (files == null || files.length <= MAX_RECORDINGS) return;
        Arrays.sort(files, Comparator.comparingLong(File::lastModified));
        int del = files.length - MAX_RECORDINGS;
        for (int i = 0; i < del; i++) {
            //noinspection ResultOfMethodCallIgnored
            files[i].delete();
        }
    }

    public static int countRecordings(Context ctx) {
        File dir = new File(ctx.getFilesDir(), "recordings");
        String[] list = dir.list((d, n) -> n.endsWith(".csv"));
        return list != null ? list.length : 0;
    }

    public static List<Summary> listSummaries(Context ctx) {
        List<Summary> out = new ArrayList<>();
        File dir = new File(ctx.getFilesDir(), "recordings");
        File[] files = dir.listFiles((d, n) -> n.endsWith(".csv"));
        if (files == null) return out;
        Arrays.sort(files, (a, b) -> Long.compare(b.lastModified(), a.lastModified()));
        for (File f : files) {
            Summary s = readSummary(f);
            if (s != null) out.add(s);
        }
        return out;
    }

    private static Summary readSummary(File f) {
        try (BufferedReader br = new BufferedReader(new FileReader(f))) {
            String first = br.readLine();
            if (first != null && first.startsWith("# ")) {
                Summary s = new Summary();
                s.file = f;
                for (String part : first.substring(2).split(";")) {
                    int eq = part.indexOf('=');
                    if (eq <= 0) continue;
                    String k = part.substring(0, eq).trim();
                    String v = part.substring(eq + 1).trim();
                    switch (k) {
                        case "pkg": s.pkg = v; break;
                        case "start": s.startEpoch = parseLongSafe(v, 0L); break;
                        case "dur": s.durationSec = parseLongSafe(v, 0L); break;
                        case "samples": s.sampleCount = (int) parseLongSafe(v, 0L); break;
                        case "avg_fps": s.avgFps = (int) parseLongSafe(v, 0L); break;
                        case "low1_fps": s.low1Fps = (int) parseLongSafe(v, 0L); break;
                        case "min_fps": s.minFps = (int) parseLongSafe(v, 0L); break;
                        case "max_fps": s.maxFps = (int) parseLongSafe(v, 0L); break;
                        case "avg_cpu": s.avgCpuPct = (int) parseLongSafe(v, 0L); break;
                        case "max_cpu_c": s.maxCpuC = (int) parseLongSafe(v, 0L); break;
                        case "avg_gpu": s.avgGpuPct = (int) parseLongSafe(v, 0L); break;
                        case "max_gpu_c": s.maxGpuC = (int) parseLongSafe(v, 0L); break;
                        case "avg_ram": s.avgRamPct = (int) parseLongSafe(v, 0L); break;
                        case "max_batt_c": s.maxBattC = (int) parseLongSafe(v, 0L); break;
                        case "avg_power_mw": s.avgPowerMw = (int) parseLongSafe(v, 0L); break;
                        case "max_power_mw": s.maxPowerMw = (int) parseLongSafe(v, 0L); break;
                    }
                }
                if (s.sampleCount > 0) return s;
            }
        } catch (Throwable ignored) {
        }
        List<Sample> rows = loadSamples(f);
        if (rows.isEmpty()) return null;
        return computeSummary(f, "session", rows.get(0).ts, rows);
    }

    public static List<Sample> loadSamples(File f) {
        List<Sample> out = new ArrayList<>();
        if (f == null || !f.isFile()) return out;
        try (BufferedReader br = new BufferedReader(new FileReader(f))) {
            String line;
            while ((line = br.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#") || line.startsWith("ts,")) continue;
                String[] c = line.split(",");
                if (c.length < 14) continue;
                Sample s = new Sample();
                s.ts = parseLongSafe(c[0], 0L);
                s.fps = (int) parseLongSafe(c[1], -1L);
                s.low1 = (int) parseLongSafe(c[2], -1L);
                s.cpuPct = (int) parseLongSafe(c[3], 0L);
                s.cpuC = (int) parseLongSafe(c[4], 0L);
                s.cpuMhz = (int) parseLongSafe(c[5], 0L);
                s.gpuPct = (int) parseLongSafe(c[6], 0L);
                s.gpuMhz = (int) parseLongSafe(c[7], 0L);
                s.gpuC = (int) parseLongSafe(c[8], 0L);
                s.ramUsedMb = (int) parseLongSafe(c[9], 0L);
                s.ramTotalMb = (int) parseLongSafe(c[10], 0L);
                s.ramPct = (int) parseLongSafe(c[11], 0L);
                s.battC = (int) parseLongSafe(c[12], 0L);
                s.battPct = (int) parseLongSafe(c[13], 0L);
                s.powerMw = c.length >= 15 ? (int) parseLongSafe(c[14], 0L) : 0;
                out.add(s);
            }
        } catch (Throwable ignored) {
        }
        return out;
    }

    public static boolean deleteRecording(File f) {
        return f != null && f.isFile() && f.delete();
    }

    public static String exportToDownloads(File f) {
        if (f == null || !f.isFile()) return "";
        String dst = "/sdcard/Download/" + f.getName();
        String cmd = "cp " + RustBridge.shellQuote(f.getAbsolutePath()) + " " + RustBridge.shellQuote(dst)
            + " && chmod 0644 " + RustBridge.shellQuote(dst) + " && echo OK";
        String res = RustBridge.nativeExec(cmd);
        return (res != null && res.contains("OK")) ? dst : "";
    }

    private static long parseLongSafe(String s, long def) {
        try {
            return Long.parseLong(s.trim());
        } catch (Throwable ignored) {
            return def;
        }
    }
}
