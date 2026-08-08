#pragma once
#import <Foundation/Foundation.h>

#define MH_TWEAK_NAME "MinecraftHelper"
#define MH_VERSION    "1.1.0"

#import "MHSubstrate.h"
#import "MHLogger.h"

#ifdef __cplusplus
extern "C" {
#endif

void MHProbeSymbols(void);   // 批量 MSFindSymbol 探测（10 个 Bedrock C++ mangled 名）
void MHInstallHooks(void);   // 仅对命中符号条件安装 hook
int  MHProbeHitCount(void);  // 命中的符号数（供悬浮窗 HUD 显示）

#ifdef __cplusplus
}
#endif
