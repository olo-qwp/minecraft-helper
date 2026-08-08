#import "MHSubstrate.h"
#import "MHLogger.h"
#import <dlfcn.h>

typedef void *(*MSFindSymbol_t)(const char *image, const char *name);
typedef void (*MSHookFunction_t)(void *symbol, void *replace, void **result);
typedef void (*MSHookMessageEx_t)(Class _class, SEL sel, IMP imp, IMP *result);

static void *gHandle = NULL;
static MSFindSymbol_t gMSFindSymbol = NULL;
static MSHookFunction_t gMSHookFunction = NULL;
static MSHookMessageEx_t gMSHookMessageEx = NULL;

static void MHLoadSubstrate(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
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
            if (h) { gHandle = h; break; }
        }
        if (!gHandle) {
            MHLogPrint(MHLogLevelWarn, "substrate runtime not found — hooks dormant, UI/logging still active");
            return;
        }
        gMSFindSymbol    = (MSFindSymbol_t)dlsym(gHandle, "MSFindSymbol");
        gMSHookFunction  = (MSHookFunction_t)dlsym(gHandle, "MSHookFunction");
        gMSHookMessageEx = (MSHookMessageEx_t)dlsym(gHandle, "MSHookMessageEx");
        MHLogPrint(MHLogLevelInfo, "substrate runtime loaded: %s (find=%p hook=%p msgex=%p)",
                   candidates[0], gMSFindSymbol, gMSHookFunction, gMSHookMessageEx);
    });
}

bool MHSubstrateAvailable(void) {
    MHLoadSubstrate();
    return gMSFindSymbol && gMSHookFunction;
}

void *MHFindSymbol(const char *name) {
    MHLoadSubstrate();
    if (!name) return NULL;
    if (!gMSFindSymbol) {
        MHLogPrint(MHLogLevelWarn, "MHFindSymbol(%s): no substrate runtime", name);
        return NULL;
    }
    void *p = gMSFindSymbol(NULL, name);
    if (!p) MHLogPrint(MHLogLevelInfo, "symbol MISS: %s (stripped or renamed)", name);
    return p;
}

bool MHHookFunction(void *target, void *replacement, void **original) {
    MHLoadSubstrate();
    if (!target || !replacement) {
        MHLogPrint(MHLogLevelWarn, "hook skipped: target=%p repl=%p (no symbol bound)", target, replacement);
        return false;
    }
    if (!gMSHookFunction) {
        MHLogPrint(MHLogLevelWarn, "hook skipped: no substrate runtime");
        return false;
    }
    gMSHookFunction(target, replacement, original);
    MHLogPrint(MHLogLevelInfo, "hook installed: %p -> %p (orig=%p)", target, replacement, original ? *original : NULL);
    return true;
}

bool MHHookMessageEx(Class cls, SEL sel, IMP imp, IMP *original) {
    MHLoadSubstrate();
    if (!cls || !sel || !imp) return false;
    if (!gMSHookMessageEx) return false;
    gMSHookMessageEx(cls, sel, imp, original);
    return true;
}
