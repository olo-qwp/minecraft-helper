#pragma once
#import <Foundation/Foundation.h>

// 安全的 substrate 运行时包装：dlopen 探测 libsubstrate/libellekit/libsubstitute，
// 找不到运行时绝不崩溃 —— hooks 休眠，UI/日志照常工作（iGameGod 非越狱注入场景）。
#ifdef __cplusplus
extern "C" {
#endif

bool   MHSubstrateAvailable(void);                       // 是否加载到 hook 运行时
void  *MHFindSymbol(const char *name);                   // 安全 MSFindSymbol（NULL=未命中/剥离）
bool   MHHookFunction(void *target, void *replacement, void **original); // 安全 MSHookFunction
bool   MHHookMessageEx(Class cls, SEL sel, IMP imp, IMP *original);      // 安全 MSHookMessageEx

#ifdef __cplusplus
}
#endif
