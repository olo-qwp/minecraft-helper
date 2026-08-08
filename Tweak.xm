// MinecraftHelper — iOS Minecraft Bedrock 辅助 tweak
// 注入入口：%ctor
//  · %ctor 在 dyld 阶段执行（MobileLoader / iGameGod 均在 main() 之前注入）
//  · ★ 铁律：%ctor 内绝不触碰 UIKit（UIWindow/UIButton 等）——此时 UIApplication 尚不存在，
//    提前创建窗口不会显示（无UI）甚至触发崩溃（闪退）。UI 一律延迟到 app 启动完成后创建。
//  · MSFindSymbol 批量探测 10 个 Bedrock C++ mangled 名（命中记日志，为按符号 hook 铺路）
//  · 符号剥离返回 NULL 属正常（iOS MCPE 符号已剥离）——全部 hook 条件化，绝不闪退

#import "MHCommon.h"
#import "MHFeatures.h"
#import "OverlayManager.h"
#include <unistd.h>

#define MH_PROBE_COUNT 10

// ---- 探测表：10 个 Bedrock C++ mangled 名（签名基于公开反编译推测，随版本而异，探测仅诊断）----
static const char *gProbeNames[MH_PROBE_COUNT] = {
    "_ZN6Player4hurtERK17ActorDamageSourceibb",  // [0] Player::hurt(ActorDamageSource const&, int, bool, bool)
    "_ZN5Actor4hurtERK17ActorDamageSourceibb",   // [1] Actor::hurt(...)  ← 一击必杀载体
    "_ZN5Actor8setSpeedEf",                       // [2] Actor::setSpeed(float)  （Player 无 setSpeed，用基类）
    "_ZN3Mob6attackER5Actor",                     // [3] Mob::attack(Actor&)
    "_ZN15MinecraftClient4tickEv",                // [4] MinecraftClient::tick()
    "_ZN3Mob9knockbackER5Actoriffffff",           // [5] Mob::knockback(Actor&, int, float,float,float,float,float)
    "_ZN6Player12getAbilitiesEv",                 // [6] Player::getAbilities()
    "_ZN6Player5swingEv",                         // [7] Player::swing()
    "_ZN6Player11getPositionEv",                  // [8] Player::getPosition()
    "_ZN6Player13addExperienceEi",                // [9] Player::addExperience(int)
};
static void *gProbeAddr[MH_PROBE_COUNT] = {0};

// ---- 原函数指针（hook 回原用；仅符号命中后才有值） ----
static bool (*orig_PlayerHurt)(void *self, const void *src, int dmg, bool a, bool b);
static bool (*orig_ActorHurt)(void *self, const void *src, int dmg, bool a, bool b);
static void (*orig_ActorSetSpeed)(void *self, float speed);
static void (*orig_MobAttack)(void *self, void *target);
static void (*orig_MinecraftClientTick)(void *self);
static void (*orig_MobKnockback)(void *self, void *target, int a, float b, float c, float d, float e, float f);

static bool gFeatureOn(NSString *identifier) {
    return [[[MHFeatureManager shared] featureWithIdentifier:identifier] isEnabled];
}

// ---- hook 实现（全为空指针安全：orig 为 NULL 时直接返回，避免崩） ----
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
    if (gFeatureOn(@"antikb")) return; // 拦截全部击退
    if (orig_MobKnockback) orig_MobKnockback(self, target, a, b, c, d, e, f);
}

// ---- 符号探测（extern "C"，悬浮窗"重探符号"按钮可再次调用） ----
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

// ---- 条件安装 hook：仅符号命中 + substrate 可用时绑定 ----
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

// ---- 注入入口 ----
// 安全清单（%ctor 阶段只允许这些）：
//   纯 C（fopen/fprintf/dlsym/dlopen/符号探测/hook 绑定）、Foundation（NSLog/NSFileManager/NSNotificationCenter 注册）
// 禁止：UIWindow/UIButton/UIScreen 等一切 UIKit 界面操作、CADisplayLink
%ctor {
    @autoreleasepool {
        MHLogPrint(MHLogLevelInfo, "============================================");
        MHLogPrint(MHLogLevelInfo, "%s v%s injected into pid %d (stage: dyld-init)", MH_TWEAK_NAME, MH_VERSION, (int)getpid());

        // 0. 进程身份（确认 Filter 匹配：Preview 与正式版同 bundle id com.mojang.minecraftpe）
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"(unknown)";
        NSString *procName = NSProcessInfo.processInfo.processName ?: @"(unknown)";
        MHLogPrint(MHLogLevelInfo, "process: bundle=%s exec=%s", bundleID.UTF8String, procName.UTF8String);

        // 1. 批量符号探测（10 个 Bedrock C++ mangled 名）
        MHProbeSymbols();

        // 2. plist 存在性校验（rootless / rootful 双路径，确认 Filter 可被找到）
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *plistPaths = @[
            @"/var/jb/Library/MobileSubstrate/DynamicLibraries/MinecraftHelper.plist",
            @"/Library/MobileSubstrate/DynamicLibraries/MinecraftHelper.plist",
        ];
        for (NSString *p in plistPaths) {
            BOOL exists = [fm fileExistsAtPath:p];
            MHLogPrint(MHLogLevelInfo, "plist %s: %s", p.UTF8String, exists ? "FOUND" : "not present (this path)");
        }

        // 3. 条件 hook（仅符号命中 + substrate 可用）
        MHInstallHooks();

        // 4. UI 延迟启动（★ 修复无UI/闪退的核心）
        //    方案：a) UIApplicationDidFinishLaunchingNotification 发出后 +2s（游戏进主界面）
        //          b) 6s 兜底（防止通知已发出后才注入的极端场景）
        //    scheduleStartWithDelay 内部再做主线程检查 + @try/@catch 兜底
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
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                MHLogPrint(MHLogLevelInfo, "fallback timer -> schedule overlay");
                [OverlayManager scheduleStartWithDelay:0.5];
            });
        });

        MHLogPrint(MHLogLevelInfo, "%s v%s ctor complete (UI deferred to post-launch)", MH_TWEAK_NAME, MH_VERSION);
    }
}
