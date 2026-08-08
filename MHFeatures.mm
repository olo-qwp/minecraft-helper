#import "MHFeatures.h"
#import "MHCommon.h"
#import "OverlayManager.h"
#import <UIKit/UIKit.h>

@implementation MHFeature
@end

@interface MHFeatureManager ()
@property (nonatomic, strong) NSArray<MHFeature *> *features;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *boundMap;
@end

@implementation MHFeatureManager

+ (instancetype)shared {
    static MHFeatureManager *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MHFeatureManager new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _boundMap = [NSMutableDictionary dictionary];
        _features = @[
            [self makeFeature:@"god"       title:@"无敌模式"   subtitle:@"拦截对玩家的伤害 (Player::hurt)"      icon:@"shield.fill"],
            [self makeFeature:@"onehit"    title:@"一击必杀"   subtitle:@"伤害×50，建议与无敌同开 (Actor::hurt)" icon:@"flame.fill"],
            [self makeFeature:@"speed"     title:@"移速增强 ×2" subtitle:@"放大 Actor::setSpeed 参数"            icon:@"hare.fill"],
            [self makeFeature:@"sprint"    title:@"自动疾跑"   subtitle:@"需要玩家对象数据"                      icon:@"figure.run"],
            [self makeFeature:@"fly"       title:@"飞行模式"   subtitle:@"需要玩家对象数据"                      icon:@"wind"],
            [self makeFeature:@"autojump"  title:@"自动跳跃"   subtitle:@"需要玩家对象数据"                      icon:@"arrow.up"],
            [self makeFeature:@"antikb"    title:@"防击退"     subtitle:@"拦截 Mob::knockback"                   icon:@"shield.lefthalf.filled"],
            [self makeFeature:@"nofall"    title:@"无坠落伤害" subtitle:@"需要伤害来源识别"                      icon:@"arrow.down.circle.fill"],
            [self makeFeature:@"autoatk"   title:@"自动攻击"   subtitle:@"Mob::attack 挂钩"                      icon:@"bolt.fill"],
            [self makeFeature:@"fullbright" title:@"全亮度"    subtitle:@"屏幕亮度拉满（直接生效）"              icon:@"sun.max.fill"],
            [self makeFeature:@"hud"       title:@"性能 HUD"   subtitle:@"悬浮窗实时 FPS / 内存（直接生效）"     icon:@"gauge"],
            [self makeFeature:@"gamespeed" title:@"计时加速"   subtitle:@"MinecraftClient::tick 挂钩"            icon:@"clock.fill"],
        ];
    }
    return self;
}

- (MHFeature *)makeFeature:(NSString *)identifier
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                      icon:(NSString *)icon {
    MHFeature *f = [MHFeature new];
    f.identifier = identifier;
    f.title = title;
    f.subtitle = subtitle;
    f.iconName = icon;
    f.enabled = NO;
    f.state = MHFeatureStateInactive;
    return f;
}

- (MHFeature *)featureWithIdentifier:(NSString *)identifier {
    for (MHFeature *f in self.features) {
        if ([f.identifier isEqualToString:identifier]) return f;
    }
    return nil;
}

- (void)setEnabled:(BOOL)enabled forIdentifier:(NSString *)identifier {
    MHFeature *f = [self featureWithIdentifier:identifier];
    if (!f) return;
    f.enabled = enabled;

    // —— 直接生效类功能 ——
    if ([identifier isEqualToString:@"fullbright"]) {
        static CGFloat prevBrightness = -1;
        if (enabled) {
            prevBrightness = UIScreen.mainScreen.brightness;
            UIScreen.mainScreen.brightness = 1.0;
        } else if (prevBrightness >= 0) {
            UIScreen.mainScreen.brightness = prevBrightness;
            prevBrightness = -1;
        }
    }
    if ([identifier isEqualToString:@"hud"]) {
        [[OverlayManager sharedInstance] setHudEnabled:enabled];
    }

    [self refreshStateFor:f];
    MHLogPrint(MHLogLevelInfo, "feature [%s] -> %s", identifier.UTF8String, enabled ? "ON" : "OFF");
}

- (void)setHookBound:(BOOL)bound forIdentifier:(NSString *)identifier {
    self.boundMap[identifier] = @(bound);
    [self refreshStateFor:[self featureWithIdentifier:identifier]];
}

- (void)refreshStates {
    for (MHFeature *f in self.features) [self refreshStateFor:f];
}

- (void)refreshStateFor:(MHFeature *)f {
    if (!f) return;
    // 直接生效类
    if ([f.identifier isEqualToString:@"fullbright"] || [f.identifier isEqualToString:@"hud"]) {
        f.state = MHFeatureStateActive;
        return;
    }
    // 数据依赖类（暂无法绑定）
    if ([f.identifier isEqualToString:@"sprint"] || [f.identifier isEqualToString:@"fly"] ||
        [f.identifier isEqualToString:@"autojump"] || [f.identifier isEqualToString:@"nofall"]) {
        f.state = MHFeatureStateInactive;
        return;
    }
    // hook 依赖类
    BOOL bound = [self.boundMap[f.identifier] boolValue];
    f.state = bound ? MHFeatureStateActive : MHFeatureStateNoSymbol;
}

- (void)onTick {
    // 每帧回调：由 MinecraftClient::tick hook 驱动。
    // 当前无玩家对象指针来源，保留为后续按符号/偏移接线的扩展点。
    static int counter = 0;
    if ((++counter % 600) == 0) {
        MHLogPrint(MHLogLevelInfo, "tick alive (%d ticks)", counter);
    }
}

@end
