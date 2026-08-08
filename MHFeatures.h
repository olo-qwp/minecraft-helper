#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MHFeatureState) {
    MHFeatureStateActive    = 0,  // 已生效（hook 已绑定或直接生效）
    MHFeatureStateNoSymbol  = 1,  // 符号未命中（当前版本二进制剥离了该符号）
    MHFeatureStateInactive  = 2,  // 等待数据（需要玩家对象/伤害来源等运行时数据）
};

@interface MHFeature : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) MHFeatureState state;
@end

@interface MHFeatureManager : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<MHFeature *> *features;
- (MHFeature *)featureWithIdentifier:(NSString *)identifier;

- (void)setEnabled:(BOOL)enabled forIdentifier:(NSString *)identifier;
- (void)setHookBound:(BOOL)bound forIdentifier:(NSString *)identifier; // hook 绑定结果回写
- (void)refreshStates;
- (void)onTick; // 每帧回调（MinecraftClient::tick hook 驱动，扩展点）
@end
