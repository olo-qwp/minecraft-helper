#pragma once
#import <UIKit/UIKit.h>

@interface OverlayManager : NSObject
+ (instancetype)sharedInstance;
- (void)start;                       // 创建悬浮球 + 菜单（主线程调用）
- (void)setHudEnabled:(BOOL)enabled; // 性能 HUD 开关
- (void)refreshRow:(id)row;          // 刷新某功能行的状态显示
@end
