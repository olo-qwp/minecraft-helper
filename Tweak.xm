// MinecraftHelper — iOS Minecraft Bedrock 辅助 tweak
// 注入入口：%ctor  +  MSInitialize（MobileLoader 约定）
//
// ★★★ v1.2.0 防闪退架构（修复 iGameGod 注入即闪退）★★★
//  iGameGod 非越狱注入 = DYLD_INSERT_LIBRARIES 机制，dylib constructor 在 main() 之前执行，
//  此时 app 的 ObjC 依赖（Foundation/UIKit）可能尚未完成加载/初始化。
//  ★ %ctor 必须纯 C：任何 ObjC 消息（NSBundle/NSProcessInfo/NSFileManager/类初始化）都会触发
//    类初始化，依赖 Foundation 内部状态 → 构造期崩溃 = 秒退。
//  ★ 全部 ObjC 初始化移到 MSInitialize()（MobileSubstrate 约定，app 完全启动后调用；
//    iGameGod 兼容此约定）+ dispatch_after 兜底。
//  符号剥离返回 NULL 属正常（iOS MCPE 符号已剥离）——hook 全部条件化，绝不闪退。

#import "MHCommon.h"
#import "MHFeatures.h"
#import "OverlayManager.h"
#include <unistd.h>
#include <stdarg.h>

#define MH_PROBE_COUNT 10

// ================= 纯 C 早期日志（ctor 阶段安全） =================
#define MH_EARLY_BUF_MAX 64
static char gEarlyBuf[MH_EARLY_BUF_MAX][256];
static int  gEarlyCount = 0;

// ctor 阶段专用：fprintf(stderr) + 内存缓冲，MSInitialize 后 flush 进正式日志
static void MHEarlyLog(const char *fmt, ...) {
    char line[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    fprintf(stderr, "[MH-early] %s\n", line);
    if (gEarlyCount < MH_EARLY_BUF_MAX) {
        snprintf(gEarlyBuf[gEarlyCount], 256, "%s", line);
        gEarlyCount++;
    }
}

static void MHEarlyFlush(void) {
    for (int i = 0; i < gEarlyCount; i++) {
        MHLogPrint(MHLogLevelInfo, "(early) %s", gEarlyBuf[i]);
    }
    gEarlyCount = 0;
}

// ================= 探测表：10 个 Bedrock C++ mangled 名 =================
static const char *gProbeNames[MH_PROBE_COUNT] = {
    "_ZN6Player4hurtERK17ActorDamageSourceibb",  // [0] Player::hurt(ActorDamageSource const&, int, bool, bool)
    "_ZN5Actor4hurtERK17ActorDamageSourceibb",   // [1] Actor::hurt(...)  ← 一击必杀载体
    "_ZN5Actor8setSpeedEf",                       // [2] Actor::setSpeed(float)
    "_ZN3Mob6attackER5Actor",                     // [3] Mob::attack(Actor&)
    "_ZN15MinecraftClient4tickEv",                // [4] MinecraftClient::tick()
    "_ZN3Mob9knockbackER5Actoriffffff",           // [5] Mob::knockback(Actor&, int, float,...)
    "_ZN6Player12getAbilitiesEv",                 // [6] Player::getAbilities()
    "_ZN6Player5swingEv",                         // [7] Player::swing()
    "_ZN6Player11getPositionEv",                  // [8] Player::getPosition()
    "_ZN6Player13addExperienceEi",                // [9] Player::addExperience(int)
};
static void *gProbeAddr[MH_PROBE_COUNT] = {0};
static int gProbeDone = 0;

// ================= hook 原型与实现（纯 C 函数指针，空指针安全） =================
static bool (*orig_PlayerHurt)(void *self, const void *src, int dmg, bool a, bool b);
static bool (*orig_ActorHurt)(void *self, const void *src, int dmg, bool a, bool b);
static void (*orig_ActorSetSpeed)(void *self, float speed);
static void (*orig_MobAttack)(void *self, void *target);
static void (*orig_MinecraftClientTick)(void *self);
static void (*orig_MobKnockback)(void *self, void *target, int a, float b, float c, float d, float e, float f);

static bool gFeatureOn(NSString *identifier) {
    return [[[MHFeatureManager shared] featureWithIdentifier:identifier] isEnabled];
}

static bool hook_PlayerHurt(void *self, const void *src, int dmg, bool a, bool b) {
    if (gFeatureOn(@"god")) {
        MHLogPrint(MHLogLevelInfo, "god: blocked damage %d", dmg);
        return false;
    }
    return orig_PlayerHurt ? orig_PlayerHurt(self, src, dmg, a, b) : false;
}

static bool hook_ActorHurt(void *self, const void *src, int dmg, bool a, bool b) {
    if (gFeatureOn(@"onehit") && !gFeatureOn(@"god")) {
        dmg = dmg * 50 + 1;
    }
    return orig_ActorHurt ? orig_ActorHurt(self, src, dmg, a, b) : false;
}

static void hook_ActorSetSpeed(void *self, float speed) {
    if (gFeatureOn(@"speed")) speed *= 2.0f;
    if (orig_ActorSetSpeed) orig_ActorSetSpeed(self, speed);
}

static void hook_MobAttack(void *self, void *target) {
    if (gFeatureOn(@"autoatk")) {
        MHLogPrint(MHLogLevelInfo, "autoatk: attack intercepted");
    }
    if (orig_MobAttack) orig_MobAttack(self, target);
}

static void hook_MinecraftClientTick(void *self) {
    if (orig_MinecraftClientTick) orig_MinecraftClientTick(self);
    [[MHFeatureManager shared] onTick];
}

static void hook_MobKnockback(void *self, void *target, int a, float b, float c, float d, float e, float f) {
    if (gFeatureOn(@"antikb")) return;
    if (orig_MobKnockback) orig_MobKnockback(self, target, a, b, c, d, e, f);
}

// ================= 符号探测 / hook 安装（对外接口） =================
void MHProbeSymbols(void) {
    MHLogPrint(MHLogLevelInfo, "---- symbol probe: %d Bedrock C++ mangled names ----", MH_PROBE_COUNT);
    int hit = 0;
    for (int i = 0; i < MH_PROBE_COUNT; i++) {
        void *p = MHFindSymbol(gProbeNames[i]);
        gProbeAddr[i] = p;
        if (p) {
            hit++;
            MHLogPrint(MHLogLevelInfo, "probe[%02d] HIT  %s => %p", i, gProbeNames[i], p);
        } else {
            MHLogPrint(MHLogLevelInfo, "probe[%02d] MISS %s (stripped)", i, gProbeNames[i]);
        }
    }
    MHLogPrint(MHLogLevelInfo, "probe done: %d/%d symbols hit", hit, MH_PROBE_COUNT);
}

int MHProbeHitCount(void) {
    int n = 0;
    for (int i = 0; i < MH_PROBE_COUNT; i++) if (gProbeAddr[i]) n++;
    return n;
}

void MHInstallHooks(void) {
    MHFeatureManager *m = [MHFeatureManager shared];
    [m setHookBound:MHHookFunction(gProbeAddr[0], (void *)&hook_PlayerHurt,     (void **)&orig_PlayerHurt)      forIdentifier:@"god"];
    [m setHookBound:MHHookFunction(gProbeAddr[1], (void *)&hook_ActorHurt,       (void **)&orig_ActorHurt)        forIdentifier:@"onehit"];
    [m setHookBound:MHHookFunction(gProbeAddr[2], (void *)&hook_ActorSetSpeed,   (void **)&orig_ActorSetSpeed)    forIdentifier:@"speed"];
    [m setHookBound:MHHookFunction(gProbeAddr[3], (void *)&hook_MobAttack,       (void **)&orig_MobAttack)        forIdentifier:@"autoatk"];
    [m setHookBound:MHHookFunction(gProbeAddr[4], (void *)&hook_MinecraftClientTick, (void **)&orig_MinecraftClientTick) forIdentifier:@"gamespeed"];
    [m setHookBound:MHHookFunction(gProbeAddr[5], (void *)&hook_MobKnockback,    (void **)&orig_MobKnockback)     forIdentifier:@"antikb"];
    [m refreshStates];
}

// ================= 纯 C 符号探测（ctor 阶段安全，无 ObjC） =================
static void MHProbeSymbolsPureC(void) {
    MHEarlyLog("---- symbol probe: %d names (pure C) ----", MH_PROBE_COUNT);
    int hit = 0;
    for (int i = 0; i < MH_PROBE_COUNT; i++) {
        void *p = MHFindSymbolNoLog(gProbeNames[i]);   // 纯 C dlopen/dlsym，无 ObjC
        gProbeAddr[i] = p;
        if (p) { hit++; MHEarlyLog("probe[%02d] HIT  %s => %p", i, gProbeNames[i], p); }
        else   { MHEarlyLog("probe[%02d] MISS %s (stripped)", i, gProbeNames[i]); }
    }
    MHEarlyLog("probe done: %d/%d symbols hit", hit, MH_PROBE_COUNT);
    gProbeDone = 1;
}

// ================= 后启动初始化（ObjC 安全区） =================
// 由 MSInitialize 调用（MobileLoader/iGameGod 约定，app 完全启动后）
static void MHRunPostLaunchInit(void) {
    static bool gRan = false;
    if (gRan) return;   // 幂等：MSInitialize 与兜底 timer 双保险，只初始化一次
    gRan = true;
    @autoreleasepool {
        MHLogPrint(MHLogLevelInfo, "============================================");
        MHLogPrint(MHLogLevelInfo, "%s v%s post-launch init (pid %d)", MH_TWEAK_NAME, MH_VERSION, (int)getpid());

        // 早期日志并入正式日志
        MHEarlyFlush();

        // 进程身份（确认 Filter 匹配：Preview 与正式版同 bundle id）
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"(unknown)";
        NSString *procName = NSProcessInfo.processInfo.processName ?: @"(unknown)";
        MHLogPrint(MHLogLevelInfo, "process: bundle=%s exec=%s", bundleID.UTF8String, procName.UTF8String);

        // plist 存在性校验（rootless / rootful 双路径）
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *plistPaths = @[
            @"/var/jb/Library/MobileSubstrate/DynamicLibraries/MinecraftHelper.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/MinecraftHelper.plist",
        ];
        for (NSString *p in plistPaths) {
            BOOL exists = [fm fileExistsAtPath:p];
            MHLogPrint(MHLogLevelInfo, "plist %s: %s", p.UTF8String, exists ? "FOUND" : "not present (this path)");
        }

        // 条件 hook（仅符号命中 + substrate 可用；iGameGod 无 substrate 则全部休眠）
        MHInstallHooks();

        // UI 延迟创建（app 完全启动后再等 2 秒，UIKit 必然就绪；三重保险）
        static dispatch_once_t uiOnce;
        dispatch_once(&uiOnce, ^{
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidFinishLaunchingNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                            MHLogPrint(MHLogLevelInfo, "app finished launching -> schedule overlay");
                            [OverlayManager scheduleStartWithDelay:2.0];
                        }];
            // 兜底：即使通知已发出过，6 秒后也强制拉起
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                MHLogPrint(MHLogLevelInfo, "fallback timer -> schedule overlay");
                [OverlayManager scheduleStartWithDelay:0.5];
            });
        });

        MHLogPrint(MHLogLevelInfo, "%s v%s post-launch init complete", MH_TWEAK_NAME, MH_VERSION);
    }
}

// ================= 导出 MSInitialize（MobileLoader/iGameGod 约定） =================
// 越狱 MobileLoader：app 完全启动后、main runloop 运行中调用
// iGameGod：兼容 substrate 约定，同样在启动后调用
// 注意：MSInitialize 是 C 链接，无参数，MobileSubstrate 用 dlsym("MSInitialize") 找到它
extern "C" void MSInitialize(void) {
    MHRunPostLaunchInit();
}

// ================= %ctor：纯 C 安全区（零 ObjC） =================
%ctor {
    MHEarlyLog("============================================");
    MHEarlyLog("%s v%s injected (pid %d, dyld stage, pure-C ctor)", MH_TWEAK_NAME, MH_VERSION, (int)getpid());

    // 1. substrate 运行时探测（dlopen/dlsym 纯 C 无日志；iGameGod 无 substrate → 安全跳过）
    bool sub = MHSubstrateAvailableNoLog();

    // 2. 符号探测（纯 C，仅诊断；命中才有后续 hook）
    MHProbeSymbolsPureC();

    // 3. 兜底定时器：若注入器不调用 MSInitialize（部分注入器不兼容该约定），
    //    8 秒后仍会自动拉起完整初始化（libdispatch 纯 C API，main queue 排队安全）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MHEarlyLog("ctor fallback timer fired -> post-launch init");
        MHRunPostLaunchInit();
    });

    MHEarlyLog("ctor complete (substrate=%s, all ObjC deferred to post-launch)", sub ? "yes" : "no");
}
