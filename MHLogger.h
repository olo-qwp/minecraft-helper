#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(int, MHLogLevel) {
    MHLogLevelInfo  = 0,
    MHLogLevelWarn  = 1,
    MHLogLevelError = 2,
};

// C++ 日志收集器：ring buffer + 文件落盘（沙盒 Documents/MinecraftHelper.log）
#ifdef __cplusplus
extern "C" {
#endif

void     MHLogPrint(MHLogLevel level, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
void     MHLogFlush(void);
NSString *MHLogFilePath(void);   // 日志文件路径
NSString *MHLogContents(void);   // 当前 ring buffer 内容（UI 展示用）
NSString *MHLogExportToFile(void); // 全量写盘并返回路径（导出/分享用）

#ifdef __cplusplus
}
#endif
