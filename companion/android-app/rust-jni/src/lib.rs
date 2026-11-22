// KSU Ultimate Gaming X v1.0.0 - Standalone App Rust JNI Bridge (aarch64-linux-android)
// Pure std Rust, zero external crates. Maintains a persistent `su` root shell pipe
// for <5ms telemetry/control latency + invokes compiled ARM64 `kgx-core` directly.

use std::ffi::{CStr, CString};
use std::io::{BufRead, BufReader, Write};
use std::os::raw::c_char;
use std::os::raw::c_void;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

type JNIEnv = *const *const *const c_void;
type JClass = *mut c_void;
type JString = *mut c_void;

// Verified indices from Android NDK r29 jni.h (struct JNINativeInterface)
const IDX_NEW_STRING_UTF: usize = 167;
const IDX_GET_STRING_UTF_CHARS: usize = 169;
const IDX_RELEASE_STRING_UTF_CHARS: usize = 170;

struct PersistentSu {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

static SU_PIPE: Mutex<Option<PersistentSu>> = Mutex::new(None);
static CMD_SEQ: AtomicU64 = AtomicU64::new(1);

unsafe fn jstring_to_string(env: JNIEnv, jstr: JString) -> String {
    if env.is_null() || jstr.is_null() {
        return String::new();
    }
    let table = *env;
    let get_fn: unsafe extern "C" fn(JNIEnv, JString, *mut u8) -> *const c_char =
        std::mem::transmute(*table.add(IDX_GET_STRING_UTF_CHARS));
    let rel_fn: unsafe extern "C" fn(JNIEnv, JString, *const c_char) =
        std::mem::transmute(*table.add(IDX_RELEASE_STRING_UTF_CHARS));

    let ptr = get_fn(env, jstr, std::ptr::null_mut());
    if ptr.is_null() {
        return String::new();
    }
    let res = CStr::from_ptr(ptr).to_string_lossy().into_owned();
    rel_fn(env, jstr, ptr);
    res
}

unsafe fn string_to_jstring(env: JNIEnv, s: &str) -> JString {
    if env.is_null() {
        return std::ptr::null_mut();
    }
    let table = *env;
    let new_fn: unsafe extern "C" fn(JNIEnv, *const c_char) -> JString =
        std::mem::transmute(*table.add(IDX_NEW_STRING_UTF));

    let sanitized = s.replace('\0', "");
    let cstr = CString::new(sanitized).unwrap_or_else(|_| CString::new("").unwrap());
    new_fn(env, cstr.as_ptr())
}

fn spawn_su() -> Result<PersistentSu, String> {
    let mut child = Command::new("su")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("Failed to spawn su: {e}"))?;

    let stdin = child.stdin.take().ok_or("Missing su stdin")?;
    let stdout = child.stdout.take().ok_or("Missing su stdout")?;
    Ok(PersistentSu {
        child,
        stdin,
        stdout: BufReader::new(stdout),
    })
}

fn exec_on_pipe(cmd: &str) -> Result<String, String> {
    let mut guard = SU_PIPE.lock().map_err(|_| "SU mutex poisoned".to_string())?;

    for attempt in 0..2 {
        if guard.is_none() {
            *guard = Some(spawn_su()?);
        }

        let seq = CMD_SEQ.fetch_add(1, Ordering::Relaxed);
        let marker = format!("__KGX_END_{seq}__");
        let payload = format!("{cmd}\nprintf '\\n{marker}\\n'\n");

        let pipe = guard.as_mut().unwrap();
        let write_ok = pipe
            .stdin
            .write_all(payload.as_bytes())
            .and_then(|_| pipe.stdin.flush())
            .is_ok();

        if write_ok {
            let mut out = String::with_capacity(4096);
            let mut eof = false;
            loop {
                let mut line = String::new();
                match pipe.stdout.read_line(&mut line) {
                    Ok(0) | Err(_) => {
                        eof = true;
                        break;
                    }
                    Ok(_) => {
                        if let Some(pos) = line.find(&marker) {
                            let prefix = &line[..pos];
                            if !prefix.is_empty() {
                                out.push_str(prefix);
                            }
                            return Ok(out.trim().to_string());
                        }
                        out.push_str(&line);
                    }
                }
            }
            if !eof {
                return Ok(out.trim().to_string());
            }
        }

        if let Some(mut dead) = guard.take() {
            let _ = dead.child.kill();
            let _ = dead.child.wait();
        }
        if attempt == 1 {
            return Err("Root shell pipe broken".to_string());
        }
    }
    Err("Root execution failed".to_string())
}

#[no_mangle]
pub unsafe extern "C" fn Java_com_kgx_ultimate_RustBridge_nativeVersion(
    env: JNIEnv,
    _cls: JClass,
) -> JString {
    string_to_jstring(env, "Rust Core v1.0.0 (aarch64)")
}

#[no_mangle]
pub unsafe extern "C" fn Java_com_kgx_ultimate_RustBridge_nativeCheckRoot(
    _env: JNIEnv,
    _cls: JClass,
) -> i32 {
    match exec_on_pipe("id -u") {
        Ok(out) if out.trim() == "0" => 1,
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn Java_com_kgx_ultimate_RustBridge_nativeResetPipe(
    _env: JNIEnv,
    _cls: JClass,
) {
    if let Ok(mut guard) = SU_PIPE.lock() {
        if let Some(mut old) = guard.take() {
            let _ = old.child.kill();
            let _ = old.child.wait();
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn Java_com_kgx_ultimate_RustBridge_nativeExec(
    env: JNIEnv,
    _cls: JClass,
    jcmd: JString,
) -> JString {
    let cmd = jstring_to_string(env, jcmd);
    if cmd.trim().is_empty() {
        return string_to_jstring(env, "{\"ok\":false,\"error\":\"Empty command\"}");
    }
    match exec_on_pipe(&cmd) {
        Ok(out) if !out.is_empty() => string_to_jstring(env, &out),
        Ok(_) => string_to_jstring(env, "{\"ok\":true}"),
        Err(err) => {
            let escaped = err.replace('\\', "\\\\").replace('"', "\\\"");
            string_to_jstring(env, &format!("{{\"ok\":false,\"error\":\"{escaped}\"}}"))
        }
    }
}
