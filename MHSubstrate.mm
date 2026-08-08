#import "MHSubstrate.h"
#import "MHLogger.h"
#import <dlfcn.h>
#include <stdio.h>

typedef void *(*MSFindSymbol_t)(const char *image, const char *name);
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static void *gHandle = NULL;
static const char *gHandlePath = "unknown";
static MSFindSymbol_t gMSFindSymbol = NULL;
static MSHookFunction_t gMSHookFunction = NULL;
static MSHookMessageEx_t gMSHookMessageEx = NULL;

// 纯 C 加载（无日志）：%ctor 早期安全。返回是否成功。
static bool MHLoadSubstrateNoLog(void) {
    if (gHandle) return true;
    static bool tried = false;
    if (tried) return (gHandle != NULL);
    tried = true;

    const char *candidates[] = {
        "/var/jb/usr/lib/libsubstrate.dylib",   // rootless
        "/usr/lib/libsubstrate.dylib",          // rootful
        "/var/jb/usr/lib/libellekit.dylib",     // rootless ellekit
        "/usr/lib/libellekit.dylib",            // rootful ellekit
        "/var/jb/usr/lib/libsubstitute.dylib",  // rootless substitute
        "/usr/lib/libsubstitute.dylib",         // rootful substitute
        "libsubstrate.dylib",
        "libellekit.dylib",
        "libsubstitute.dylib",
    };
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        void *h = dlopen(candidates[i], RTLD_NOW | RTLD_GLOBAL);
        if (h) {
            gHandle = h;
            gHandlePath = candidates[i];
            gMSFindSymbol    = (MSFindSymbol_t)dlsym(gHandle, "MSFindSymbol");
            gMSHookFunction  = (MSHookFunction_t)dlsym(gHandle, "MSHookFunction");
            gMSHookMessageEx = (MSHookMessageEx_t)dlsym(gHandle, "MSHookMessageEx");
            return true;
        }
    }
    return false;
}

// ---- 纯 C 接口（零日志） ----
bool MHSubstrateAvailableNoLog(void) {
    return MHLoadSubstrateNoLog() && gMSFindSymbol && gMSHookFunction;
}

void *MHFindSymbolNoLog(const char *name) {
    if (!name) return NULL;
    if (!MHLoadSubstrateNoLog() || !gMSFindSymbol) return NULL;
    return gMSFindSymbol(NULL, name);
}

// ---- 带日志接口（MSInitialize 之后使用） ----
bool MHSubstrateAvailable(void) {
    bool ok = MHSubstrateAvailableNoLog();
    if (ok) {
        MHLogPrint(MHLogLevelInfo, "substrate runtime available: %s", gHandlePath);
    } else {
        MHLogPrint(MHLogLevelWarn, "substrate runtime not found — hooks dormant, UI/logging still active");
    }
    return ok;
}

void *MHFindSymbol(const char *name) {
    if (!name) return NULL;
    if (!MHLoadSubstrateNoLog()) {
        MHLogPrint(MHLogLevelWarn, "MHFindSymbol(%s): no substrate runtime", name);
        return NULL;
    }
    void *p = gMSFindSymbol ? gMSFindSymbol(NULL, name) : NULL;
    if (!p) MHLogPrint(MHLogLevelInfo, "symbol MISS: %s (stripped or renamed)", name);
    return p;
}

bool MHHookFunction(void *target, void *replacement, void **original) {
    if (!target || !replacement) {
        MHLogPrint(MHLogLevelWarn, "hook skipped: target=%p repl=%p (no symbol bound)", target, replacement);
        return false;
    }
    if (!MHLoadSubstrateNoLog() || !gMSHookFunction) {
        MHLogPrint(MHLogLevelWarn, "hook skipped: no substrate runtime");
        return false;
    }
    gMSHookFunction(target, replacement, original);
    MHLogPrint(MHLogLevelInfo, "hook installed: %p -> %p (orig=%p)", target, replacement, original ? *original : NULL);
    return true;
}

bool MHHookMessageEx(Class cls, SEL sel, IMP imp, IMP *original) {
    if (!cls || !sel || !imp) return false;
    if (!MHLoadSubstrateNoLog() || !gMSHookMessageEx) return false;
    gMSHookMessageEx(cls, sel, imp, original);
    return true;
}
