#pragma once
#import <Foundation/Foundation.h>

// 安全的 substrate 运行时包装：dlopen 探测 libsubstrate/libellekit/libsubstitute，
// 找不到运行时绝不崩溃 —— hooks 休眠，UI/日志照常工作（iGameGod 非越狱注入场景）。
#ifdef __cplusplus
extern "C" {
#endif

// ---- 纯 C 版本（★ %ctor 等 dyld 早期阶段专用：零 ObjC，零日志，绝对安全） ----
bool   MHSubstrateAvailableNoLog(void);           // dlopen 探测运行时是否存在
void  *MHFindSymbolNoLog(const char *name);       // MSFindSymbol（NULL=未命中/剥离），不打印

// ---- 带日志版本（MSInitialize 之后 app 已启动，ObjC 安全时使用） ----
bool   MHSubstrateAvailable(void);
void  *MHFindSymbol(const char *name);            // 安全 MSFindSymbol（NULL=未命中/剥离）
bool   MHHookFunction(void *target, void *replacement, void **original); // 安全 MSHookFunction
bool   MHHookMessageEx(Class cls, SEL sel, IMP imp, IMP *original);      // 安全 MSHookMessageEx

#ifdef __cplusplus
}
#endif
