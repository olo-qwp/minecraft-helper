#pragma once
#import <UIKit/UIKit.h>

@interface OverlayManager : NSObject
+ (instancetype)sharedInstance;

// ★ UI 统一入口：延迟到 app 启动完成后调用（内部处理主线程 + 异常兜底，绝不导致闪退）
+ (void)scheduleStartWithDelay:(NSTimeInterval)delay;

- (void)start;                       // 创建悬浮球 + 菜单（主线程调用，内部有守卫）
- (void)setHudEnabled:(BOOL)enabled; // 性能 HUD 开关
- (void)refreshRow:(id)row;          // 刷新某功能行的状态显示
@end
