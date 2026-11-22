/*
 * KSU Ultimate Gaming X v1.0.0 - Stock-Identity Shield (Zygisk API v4)
 *
 * Isolates Google Play Services (GMS / DroidGuard), Play Store (Vending), GSF,
 * Google Wallet, Android/OEM Settings apps, and user-selected Spoof Denylist apps
 * back to the phone's genuine stock properties recorded in
 * /data/adb/ksu_gaming_x/state/orig_props.tsv using an exact per-property lookup table.
 *
 * Only replaces properties whose current value matches our active spoofed value, so
 * it never conflicts with PlayIntegrityFix / TrickyStore and never alters verified boot,
 * serial, IMEI, or attestation keys. All games and non-excluded apps unload immediately.
 */

#include <android/log.h>
#include <dlfcn.h>
#include <errno.h>
#include <jni.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/system_properties.h>
#include <sys/types.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>

#include "zygisk.hpp"

#define LOG_TAG "KGX_PIShield"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {

constexpr const char* kGlobalConfPath = "/data/adb/ksu_gaming_x/config/global.conf";
constexpr const char* kDenylistPath = "/data/adb/ksu_gaming_x/config/spoof_denylist.list";
constexpr const char* kOrigPropsPath = "/data/adb/ksu_gaming_x/state/orig_props.tsv";
constexpr const char* kActiveSpoofPath = "/data/adb/ksu_gaming_x/state/active_spoof.env";
constexpr const char* kSystemPropPath = "/data/adb/modules/ksu_ultimate_gaming_x/system.prop";
constexpr size_t kMaxPropEntries = 24;

struct PropEntry {
    char key[48]{};
    char orig[96]{};
    char spoof[96]{};
};

struct ShieldPayload {
    bool active = false;
    char scope[16]{};
    char pkg[128]{};
    uint32_t count = 0;
    PropEntry entries[kMaxPropEntries]{};
    char buildOrigBrand[64]{};
    char buildSpoofBrand[64]{};
    char buildOrigMfg[64]{};
    char buildSpoofMfg[64]{};
    char buildOrigModel[64]{};
    char buildSpoofModel[64]{};
    char buildOrigDevice[64]{};
    char buildSpoofDevice[64]{};
    char buildOrigProduct[64]{};
    char buildSpoofProduct[64]{};
};

struct ShieldConfig {
    bool safeMode = false;
    bool spoofEnabled = true;
    bool piShieldEnabled = true;
    bool excludeSettings = true;
};

ShieldPayload g_shield{};
pthread_mutex_t g_companionLock = PTHREAD_MUTEX_INITIALIZER;

using PropGetFn = int (*)(const char*, char*);
using PropReadFn = int (*)(const prop_info*, char*, char*);
using PropCallbackFn = void (*)(void*, const char*, const char*, uint32_t);
using PropReadCbFn = void (*)(const prop_info*, PropCallbackFn, void*);
using JniSysPropGet1Fn = jstring (*)(JNIEnv*, jclass, jstring);
using JniSysPropGet2Fn = jstring (*)(JNIEnv*, jclass, jstring, jstring);

PropGetFn g_orig_prop_get = nullptr;
PropReadFn g_orig_prop_read = nullptr;
PropReadCbFn g_orig_prop_read_cb = nullptr;
JniSysPropGet1Fn g_orig_jni_get1 = nullptr;
JniSysPropGet2Fn g_orig_jni_get2 = nullptr;

void safeCopy(char* dst, size_t dstLen, const std::string& src) {
    if (dstLen == 0) return;
    std::snprintf(dst, dstLen, "%s", src.c_str());
}

std::string stripQuotes(std::string s) {
    if (!s.empty() && s.back() == '\r') s.pop_back();
    if (s.size() >= 2 && s.front() == '\'' && s.back() == '\'') {
        return s.substr(1, s.size() - 2);
    }
    return s;
}

bool readExact(int fd, void* buf, size_t len) {
    auto* p = static_cast<uint8_t*>(buf);
    size_t got = 0;
    while (got < len) {
        ssize_t n = read(fd, p + got, len - got);
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        if (n == 0) return false;
        got += static_cast<size_t>(n);
    }
    return true;
}

bool writeExact(int fd, const void* buf, size_t len) {
    const auto* p = static_cast<const uint8_t*>(buf);
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = write(fd, p + sent, len - sent);
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        if (n == 0) return false;
        sent += static_cast<size_t>(n);
    }
    return true;
}

std::string trimLine(std::string s) {
    if (!s.empty() && s.back() == '\r') s.pop_back();
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

bool isTargetGooglePkg(const std::string& basePkg) {
    return basePkg == "com.google.android.gms" ||
           basePkg.rfind("com.google.android.gms.", 0) == 0 ||
           basePkg == "com.android.vending" ||
           basePkg.rfind("com.android.vending.", 0) == 0 ||
           basePkg == "com.google.android.gsf" ||
           basePkg.rfind("com.google.android.gsf.", 0) == 0 ||
           basePkg == "com.google.android.apps.walletnfcrel";
}

bool isSettingsPkg(const std::string& basePkg) {
    return basePkg == "com.android.settings" ||
           basePkg.rfind("com.android.settings.", 0) == 0 ||
           basePkg.rfind("com.samsung.android.app.settings.", 0) == 0 ||
           basePkg.rfind("com.samsung.android.settings.", 0) == 0 ||
           basePkg == "com.miui.settings" ||
           basePkg == "com.oplus.settings" ||
           basePkg == "com.coloros.settings";
}

bool isSecuritySensitiveProp(const char* name) {
    if (!name || name[0] == '\0') return true;
    return std::strncmp(name, "ro.serialno", 11) == 0 ||
           std::strncmp(name, "ro.boot.", 8) == 0 ||
           std::strncmp(name, "ro.crypto.", 10) == 0 ||
           std::strcmp(name, "ro.debuggable") == 0 ||
           std::strcmp(name, "ro.secure") == 0 ||
           std::strcmp(name, "ro.adb.secure") == 0;
}

ShieldConfig loadShieldConfig() {
    static ShieldConfig cached{};
    static time_t lastMtime = 0;
    static off_t lastSize = -1;

    struct stat st{};
    if (stat(kGlobalConfPath, &st) != 0) {
        return ShieldConfig{};
    }
    if (st.st_mtime != lastMtime || st.st_size != lastSize) {
        ShieldConfig next{};
        std::ifstream cfg(kGlobalConfPath);
        if (cfg.is_open()) {
            std::string line;
            while (std::getline(cfg, line)) {
                line = trimLine(line);
                if (line.empty() || line[0] == '#') continue;
                if (line == "SAFE_MODE=1") next.safeMode = true;
                else if (line == "SAFE_MODE=0") next.safeMode = false;
                else if (line == "SPOOF_ENABLED=0") next.spoofEnabled = false;
                else if (line == "SPOOF_ENABLED=1") next.spoofEnabled = true;
                else if (line == "PLAY_INTEGRITY_SHIELD=0") next.piShieldEnabled = false;
                else if (line == "PLAY_INTEGRITY_SHIELD=1") next.piShieldEnabled = true;
                else if (line == "SPOOF_EXCLUDE_SETTINGS=0") next.excludeSettings = false;
                else if (line == "SPOOF_EXCLUDE_SETTINGS=1") next.excludeSettings = true;
            }
        }
        cached = next;
        lastMtime = st.st_mtime;
        lastSize = st.st_size;
    }
    return cached;
}

bool isInUserDenylist(const std::string& basePkg) {
    static std::unordered_set<std::string> cachedSet;
    static time_t lastMtime = 0;
    static off_t lastSize = -1;

    struct stat st{};
    if (stat(kDenylistPath, &st) != 0) {
        cachedSet.clear();
        lastMtime = 0;
        lastSize = -1;
        return false;
    }
    if (st.st_mtime != lastMtime || st.st_size != lastSize) {
        std::unordered_set<std::string> nextSet;
        std::ifstream ifs(kDenylistPath);
        if (ifs.is_open()) {
            std::string line;
            while (std::getline(ifs, line)) {
                line = trimLine(line);
                if (line.empty() || line[0] == '#') continue;
                nextSet.insert(line);
            }
        }
        cachedSet.swap(nextSet);
        lastMtime = st.st_mtime;
        lastSize = st.st_size;
    }
    return cachedSet.find(basePkg) != cachedSet.end();
}

std::unordered_map<std::string, std::string> loadOrigMap() {
    std::unordered_map<std::string, std::string> m;
    std::ifstream ifs(kOrigPropsPath);
    if (!ifs.is_open()) return m;
    std::string line;
    while (std::getline(ifs, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        auto tab = line.find('\t');
        if (tab == std::string::npos) continue;
        m[line.substr(0, tab)] = line.substr(tab + 1);
    }
    return m;
}

std::unordered_map<std::string, std::string> loadSpoofMap() {
    std::unordered_map<std::string, std::string> m;
    std::ifstream sp(kSystemPropPath);
    if (sp.is_open()) {
        std::string line;
        while (std::getline(sp, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty() || line[0] == '#') continue;
            auto eq = line.find('=');
            if (eq == std::string::npos) continue;
            m[line.substr(0, eq)] = line.substr(eq + 1);
        }
    }
    if (!m.empty()) return m;

    std::ifstream env(kActiveSpoofPath);
    if (env.is_open()) {
        std::string line;
        std::string br, mf, md, dv, pr, lb;
        while (std::getline(env, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            auto eq = line.find('=');
            if (eq == std::string::npos) continue;
            std::string k = line.substr(0, eq);
            std::string v = stripQuotes(line.substr(eq + 1));
            if (k == "SPOOF_BRAND") br = v;
            else if (k == "SPOOF_MANUFACTURER") mf = v;
            else if (k == "SPOOF_MODEL") md = v;
            else if (k == "SPOOF_DEVICE") dv = v;
            else if (k == "SPOOF_PRODUCT") pr = v;
            else if (k == "SPOOF_LABEL") lb = v;
        }
        if (!br.empty()) {
            m["ro.product.brand"] = br; m["ro.product.system.brand"] = br; m["ro.product.product.brand"] = br;
        }
        if (!mf.empty()) {
            m["ro.product.manufacturer"] = mf; m["ro.product.system.manufacturer"] = mf; m["ro.product.product.manufacturer"] = mf;
        }
        if (!md.empty()) {
            m["ro.product.model"] = md; m["ro.product.system.model"] = md; m["ro.product.product.model"] = md;
        }
        if (!dv.empty()) {
            m["ro.product.device"] = dv; m["ro.product.system.device"] = dv; m["ro.product.product.device"] = dv;
        }
        if (!pr.empty()) {
            m["ro.product.name"] = pr; m["ro.build.product"] = pr; m["ro.product.system.name"] = pr; m["ro.product.product.name"] = pr;
        }
        if (!lb.empty()) {
            m["ro.product.marketname"] = lb; m["ro.vendor.oplus.market.name"] = lb;
        }
    }
    return m;
}

bool resolveStockValueIfSpoofed(const char* name, const char* currentVal, const char** outReplacement) {
    if (!g_shield.active || isSecuritySensitiveProp(name)) return false;

    for (uint32_t i = 0; i < g_shield.count && i < kMaxPropEntries; ++i) {
        const PropEntry& e = g_shield.entries[i];
        if (std::strcmp(name, e.key) == 0) {
            if (e.spoof[0] == '\0') return false;
            if (!currentVal || std::strcmp(currentVal, e.spoof) != 0) return false;
            *outReplacement = e.orig;
            return true;
        }
    }
    return false;
}

int hooked_prop_get(const char* name, char* value) {
    if (!g_orig_prop_get) {
        g_orig_prop_get = reinterpret_cast<PropGetFn>(dlsym(RTLD_DEFAULT, "__system_property_get"));
    }
    int len = g_orig_prop_get ? g_orig_prop_get(name, value) : 0;
    if (!g_shield.active || !value) return len;

    const char* replacement = nullptr;
    if (resolveStockValueIfSpoofed(name, value, &replacement)) {
        if (replacement && replacement[0] != '\0') {
            std::snprintf(value, PROP_VALUE_MAX, "%s", replacement);
            return static_cast<int>(std::strlen(value));
        }
        value[0] = '\0';
        return 0;
    }
    return len;
}

int hooked_prop_read(const prop_info* pi, char* name, char* value) {
    if (!g_orig_prop_read) {
        g_orig_prop_read = reinterpret_cast<PropReadFn>(dlsym(RTLD_DEFAULT, "__system_property_read"));
    }
    int len = g_orig_prop_read ? g_orig_prop_read(pi, name, value) : 0;
    if (!g_shield.active || !name || !value) return len;

    const char* replacement = nullptr;
    if (resolveStockValueIfSpoofed(name, value, &replacement)) {
        if (replacement && replacement[0] != '\0') {
            std::snprintf(value, PROP_VALUE_MAX, "%s", replacement);
            return static_cast<int>(std::strlen(value));
        }
        value[0] = '\0';
        return 0;
    }
    return len;
}

struct ReadCbCtx {
    PropCallbackFn user_cb;
    void* user_cookie;
};

void intercept_prop_cb(void* cookie, const char* name, const char* value, uint32_t serial) {
    auto* ctx = static_cast<ReadCbCtx*>(cookie);
    const char* replacement = nullptr;
    if (resolveStockValueIfSpoofed(name, value, &replacement)) {
        ctx->user_cb(ctx->user_cookie, name, replacement ? replacement : "", serial);
        return;
    }
    ctx->user_cb(ctx->user_cookie, name, value, serial);
}

void hooked_prop_read_cb(const prop_info* pi, PropCallbackFn cb, void* cookie) {
    if (!g_orig_prop_read_cb) {
        g_orig_prop_read_cb = reinterpret_cast<PropReadCbFn>(dlsym(RTLD_DEFAULT, "__system_property_read_callback"));
    }
    if (!g_orig_prop_read_cb) return;
    if (!cb || !g_shield.active) {
        g_orig_prop_read_cb(pi, cb, cookie);
        return;
    }
    ReadCbCtx ctx{cb, cookie};
    g_orig_prop_read_cb(pi, intercept_prop_cb, &ctx);
}

jstring maybeReplaceJniProp(JNIEnv* env, jstring jkey, jstring res, jstring fallback) {
    if (!g_shield.active || !jkey || !res) return res;

    const char* keyStr = env->GetStringUTFChars(jkey, nullptr);
    const char* valStr = env->GetStringUTFChars(res, nullptr);
    const char* replacement = nullptr;
    bool replaced = false;
    if (keyStr && valStr) {
        replaced = resolveStockValueIfSpoofed(keyStr, valStr, &replacement);
    }
    if (keyStr) env->ReleaseStringUTFChars(jkey, keyStr);
    if (valStr) env->ReleaseStringUTFChars(res, valStr);

    if (!replaced) return res;
    env->DeleteLocalRef(res);
    if (replacement && replacement[0] != '\0') {
        jstring out = env->NewStringUTF(replacement);
        if (env->ExceptionCheck()) env->ExceptionClear();
        return out;
    }
    if (fallback) return fallback;
    jstring empty = env->NewStringUTF("");
    if (env->ExceptionCheck()) env->ExceptionClear();
    return empty;
}

jstring hooked_jni_get1(JNIEnv* env, jclass cls, jstring jkey) {
    jstring res = g_orig_jni_get1 ? g_orig_jni_get1(env, cls, jkey) : nullptr;
    return maybeReplaceJniProp(env, jkey, res, nullptr);
}

jstring hooked_jni_get2(JNIEnv* env, jclass cls, jstring jkey, jstring jdef) {
    jstring res = g_orig_jni_get2 ? g_orig_jni_get2(env, cls, jkey, jdef) : jdef;
    return maybeReplaceJniProp(env, jkey, res, jdef);
}

int registerJniSysPropsHooks(zygisk::Api* api, JNIEnv* env) {
    JNINativeMethod methods[] = {
        {"native_get", "(Ljava/lang/String;)Ljava/lang/String;", reinterpret_cast<void*>(hooked_jni_get1)},
        {"native_get", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", reinterpret_cast<void*>(hooked_jni_get2)},
    };
    api->hookJniNativeMethods(env, "android/os/SystemProperties", methods, 2);
    if (env->ExceptionCheck()) env->ExceptionClear();

    int hooked = 0;
    if (methods[0].fnPtr && methods[0].fnPtr != reinterpret_cast<void*>(hooked_jni_get1)) {
        g_orig_jni_get1 = reinterpret_cast<JniSysPropGet1Fn>(methods[0].fnPtr);
        hooked++;
    }
    if (methods[1].fnPtr && methods[1].fnPtr != reinterpret_cast<void*>(hooked_jni_get2)) {
        g_orig_jni_get2 = reinterpret_cast<JniSysPropGet2Fn>(methods[1].fnPtr);
        hooked++;
    }
    return hooked;
}

void restoreBuildFieldIfSpoofed(JNIEnv* env, jclass buildCls, const char* fieldName,
                                const char* spoofExpected, const char* origReal) {
    if (!spoofExpected || spoofExpected[0] == '\0' || !origReal || origReal[0] == '\0') return;
    if (std::strcmp(spoofExpected, origReal) == 0) return;

    jfieldID fid = env->GetStaticFieldID(buildCls, fieldName, "Ljava/lang/String;");
    if (env->ExceptionCheck()) { env->ExceptionClear(); return; }
    if (!fid) return;

    auto curObj = static_cast<jstring>(env->GetStaticObjectField(buildCls, fid));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return; }
    if (!curObj) return;

    const char* curStr = env->GetStringUTFChars(curObj, nullptr);
    bool matchesSpoof = curStr && (std::strcmp(curStr, spoofExpected) == 0);
    if (curStr) env->ReleaseStringUTFChars(curObj, curStr);
    env->DeleteLocalRef(curObj);

    if (!matchesSpoof) return;

    jstring jval = env->NewStringUTF(origReal);
    if (!jval) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        return;
    }
    env->SetStaticObjectField(buildCls, fid, jval);
    if (env->ExceptionCheck()) env->ExceptionClear();
    env->DeleteLocalRef(jval);
}

bool containsAny(const std::string& s, const char* const* needles, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        if (s.find(needles[i]) != std::string::npos) return true;
    }
    return false;
}

void registerPltHooksForGms(zygisk::Api* api) {
    static constexpr const char* kTargetLibs[] = {
        "/libandroid_runtime.so",
        "/libbase.so",
        "/libbinder.so",
        "/libcutils.so",
        "/libutils.so",
        "/libart.so",
        "/data/app/",
        "droidguard",
        "conscrypt",
        "gms",
        "vending",
    };

    std::ifstream maps("/proc/self/maps");
    if (!maps.is_open()) return;

    std::unordered_set<uint64_t> seen;
    std::string line;
    while (std::getline(maps, line)) {
        std::istringstream iss(line);
        std::string addr, perms, offset, devStr, path;
        unsigned long long inode = 0;
        if (!(iss >> addr >> perms >> offset >> devStr >> inode)) continue;
        std::getline(iss >> std::ws, path);
        if (inode == 0 || path.empty()) continue;
        if (perms.find('x') == std::string::npos) continue;
        if (path.size() < 3 || path.compare(path.size() - 3, 3, ".so") != 0) continue;
        if (path.find("/libc.so") != std::string::npos ||
            path.find("/linker") != std::string::npos ||
            path.find("arm64-v8a.so") != std::string::npos) {
            continue;
        }
        if (!containsAny(path, kTargetLibs, sizeof(kTargetLibs) / sizeof(kTargetLibs[0]))) continue;

        unsigned int maj = 0, min = 0;
        if (std::sscanf(devStr.c_str(), "%x:%x", &maj, &min) != 2) continue;
        dev_t dev = static_cast<dev_t>(((maj & 0xff) << 8) | (min & 0xff) | ((maj & ~0xffULL) << 12) | ((min & ~0xffULL) << 20));

        struct stat st{};
        if (stat(path.c_str(), &st) == 0) {
            dev = st.st_dev;
            inode = st.st_ino;
        }

        uint64_t key = (static_cast<uint64_t>(dev) << 32) ^ static_cast<uint64_t>(inode);
        if (!seen.insert(key).second) continue;

        api->pltHookRegister(dev, static_cast<ino_t>(inode), "__system_property_get",
                             reinterpret_cast<void*>(hooked_prop_get),
                             reinterpret_cast<void**>(&g_orig_prop_get));
        api->pltHookRegister(dev, static_cast<ino_t>(inode), "__system_property_read",
                             reinterpret_cast<void*>(hooked_prop_read),
                             reinterpret_cast<void**>(&g_orig_prop_read));
        api->pltHookRegister(dev, static_cast<ino_t>(inode), "__system_property_read_callback",
                             reinterpret_cast<void*>(hooked_prop_read_cb),
                             reinterpret_cast<void**>(&g_orig_prop_read_cb));
    }
    api->pltHookCommit();
}

void companionHandler(int clientFd) {
    uint32_t pkgLen = 0;
    ShieldPayload reply{};

    if (!readExact(clientFd, &pkgLen, sizeof(pkgLen)) || pkgLen == 0 || pkgLen >= sizeof(reply.pkg)) {
        writeExact(clientFd, &reply, sizeof(reply));
        return;
    }

    std::string procName(pkgLen, '\0');
    if (!readExact(clientFd, procName.data(), pkgLen)) {
        writeExact(clientFd, &reply, sizeof(reply));
        return;
    }

    std::string basePkg = procName;
    auto colon = basePkg.find(':');
    if (colon != std::string::npos) basePkg.resize(colon);

    pthread_mutex_lock(&g_companionLock);
    ShieldConfig cfg = loadShieldConfig();
    const char* scope = nullptr;
    if (!cfg.safeMode && cfg.spoofEnabled) {
        if (isTargetGooglePkg(basePkg) && cfg.piShieldEnabled) {
            scope = "pi";
        } else if (isSettingsPkg(basePkg) && cfg.excludeSettings) {
            scope = "settings";
        } else if (isInUserDenylist(basePkg)) {
            scope = "denylist";
        }
    }

    if (scope != nullptr) {
        auto orig = loadOrigMap();
        auto spoof = loadSpoofMap();
        if (!orig.empty() && !spoof.empty() && orig["ro.product.model"] != spoof["ro.product.model"]) {
            reply.active = true;
            safeCopy(reply.scope, sizeof(reply.scope), scope);
            safeCopy(reply.pkg, sizeof(reply.pkg), procName);

            for (const auto& kv : spoof) {
                if (reply.count >= kMaxPropEntries) break;
                if (isSecuritySensitiveProp(kv.first.c_str())) continue;
                auto it = orig.find(kv.first);
                std::string origVal = (it != orig.end()) ? it->second : "";
                if (origVal == kv.second) continue;
                PropEntry& ent = reply.entries[reply.count++];
                safeCopy(ent.key, sizeof(ent.key), kv.first);
                safeCopy(ent.orig, sizeof(ent.orig), origVal);
                safeCopy(ent.spoof, sizeof(ent.spoof), kv.second);
            }

            safeCopy(reply.buildOrigBrand, sizeof(reply.buildOrigBrand), orig["ro.product.brand"]);
            safeCopy(reply.buildSpoofBrand, sizeof(reply.buildSpoofBrand), spoof["ro.product.brand"]);
            safeCopy(reply.buildOrigMfg, sizeof(reply.buildOrigMfg), orig["ro.product.manufacturer"]);
            safeCopy(reply.buildSpoofMfg, sizeof(reply.buildSpoofMfg), spoof["ro.product.manufacturer"]);
            safeCopy(reply.buildOrigModel, sizeof(reply.buildOrigModel), orig["ro.product.model"]);
            safeCopy(reply.buildSpoofModel, sizeof(reply.buildSpoofModel), spoof["ro.product.model"]);
            safeCopy(reply.buildOrigDevice, sizeof(reply.buildOrigDevice), orig["ro.product.device"]);
            safeCopy(reply.buildSpoofDevice, sizeof(reply.buildSpoofDevice), spoof["ro.product.device"]);
            safeCopy(reply.buildOrigProduct, sizeof(reply.buildOrigProduct), orig["ro.product.name"]);
            safeCopy(reply.buildSpoofProduct, sizeof(reply.buildSpoofProduct), spoof["ro.product.name"]);
        }
    }
    pthread_mutex_unlock(&g_companionLock);

    writeExact(clientFd, &reply, sizeof(reply));
}

class KgxPlayIntegrityShield : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api* api, JNIEnv* env) override {
        api_ = api;
        env_ = env;
    }

    void preServerSpecialize(zygisk::ServerSpecializeArgs* /*args*/) override {
        api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
        if (!args || !args->nice_name) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        const char* rawPkg = env_->GetStringUTFChars(args->nice_name, nullptr);
        if (!rawPkg) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        std::string procName(rawPkg);
        env_->ReleaseStringUTFChars(args->nice_name, rawPkg);

        int fd = api_->connectCompanion();
        if (fd < 0) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        uint32_t len = static_cast<uint32_t>(procName.size());
        ShieldPayload payload{};
        if (!writeExact(fd, &len, sizeof(len)) ||
            !writeExact(fd, procName.data(), len) ||
            !readExact(fd, &payload, sizeof(payload))) {
            payload.active = false;
        }
        close(fd);

        if (!payload.active || payload.count == 0) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        payload_ = payload;
    }

    void postAppSpecialize(const zygisk::AppSpecializeArgs* /*args*/) override {
        if (!payload_.active) return;

        g_shield = payload_;

        jclass buildCls = env_->FindClass("android/os/Build");
        if (buildCls) {
            restoreBuildFieldIfSpoofed(env_, buildCls, "BRAND", payload_.buildSpoofBrand, payload_.buildOrigBrand);
            restoreBuildFieldIfSpoofed(env_, buildCls, "MANUFACTURER", payload_.buildSpoofMfg, payload_.buildOrigMfg);
            restoreBuildFieldIfSpoofed(env_, buildCls, "MODEL", payload_.buildSpoofModel, payload_.buildOrigModel);
            restoreBuildFieldIfSpoofed(env_, buildCls, "DEVICE", payload_.buildSpoofDevice, payload_.buildOrigDevice);
            restoreBuildFieldIfSpoofed(env_, buildCls, "PRODUCT", payload_.buildSpoofProduct, payload_.buildOrigProduct);
            env_->DeleteLocalRef(buildCls);
        }

        registerPltHooksForGms(api_);
        int jniHooked = registerJniSysPropsHooks(api_, env_);
        LOGI("Shield active in %s (%u props, jni=%d, scope=%s): %s -> stock %s (%s)",
             payload_.pkg, payload_.count, jniHooked,
             payload_.scope[0] ? payload_.scope : "pi",
             payload_.buildSpoofModel, payload_.buildOrigModel, payload_.buildOrigDevice);
    }

private:
    zygisk::Api* api_ = nullptr;
    JNIEnv* env_ = nullptr;
    ShieldPayload payload_{};
};

}  // namespace

REGISTER_ZYGISK_MODULE(KgxPlayIntegrityShield)
REGISTER_ZYGISK_COMPANION(companionHandler)
