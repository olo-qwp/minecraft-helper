#import "MHLogger.h"
#include <mutex>
#include <string>
#include <vector>
#include <cstdio>
#include <ctime>
#include <stdarg.h>

namespace {
class MHLoggerImpl {
public:
    static MHLoggerImpl &shared() {
        static MHLoggerImpl s;
        return s;
    }

    void log(MHLogLevel lv, const char *fmt, va_list args) {
        std::lock_guard<std::mutex> lk(m_mutex);

        char buf[1536];
        vsnprintf(buf, sizeof(buf), fmt, args);

        time_t t = time(NULL);
        struct tm tmv;
        localtime_r(&t, &tmv);
        char ts[24];
        strftime(ts, sizeof(ts), "%H:%M:%S", &tmv);
        const char *lvname = (lv == MHLogLevelError) ? "ERR" : (lv == MHLogLevelWarn) ? "WRN" : "INF";

        char line[1664];
        snprintf(line, sizeof(line), "[%s][%s] %s", ts, lvname, buf);
        std::string sline(line);

        // ring buffer（保留最近 512 行）
        m_lines.push_back(sline);
        if (m_lines.size() > 512) m_lines.erase(m_lines.begin());

        // stderr（可被系统日志捕获）
        fprintf(stderr, "%s\n", line);

        // 文件落盘（沙盒 Documents/MinecraftHelper.log）
        if (!m_file) {
            NSString *p = MHLogFilePath();
            if (p) m_file = fopen(p.UTF8String, "a");
        }
        if (m_file) {
            fprintf(m_file, "%s\n", line);
            fflush(m_file);
        }
    }

    NSString *contents() {
        std::lock_guard<std::mutex> lk(m_mutex);
        NSMutableString *s = [NSMutableString string];
        for (auto &l : m_lines) [s appendFormat:@"%s\n", l.c_str()];
        return s;
    }

    void flush() {
        std::lock_guard<std::mutex> lk(m_mutex);
        if (m_file) fflush(m_file);
    }

private:
    std::mutex m_mutex;
    std::vector<std::string> m_lines;
    FILE *m_file = NULL;
};
}

void MHLogPrint(MHLogLevel level, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    MHLoggerImpl::shared().log(level, fmt, ap);
    va_end(ap);
}

void MHLogFlush(void) {
    MHLoggerImpl::shared().flush();
}

NSString *MHLogFilePath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 多级回退：Documents → Caches → tmp（注入早期沙盒可能未就绪，任一级可用即可）
        NSArray *bases = @[
            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject],
            [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject],
            NSTemporaryDirectory(),
        ];
        for (NSString *b in bases) {
            if (!b || b.length == 0) continue;
            BOOL isDir = NO;
            BOOL ok = [[NSFileManager defaultManager] fileExistsAtPath:b isDirectory:&isDir];
            if (!ok) {
                ok = [[NSFileManager defaultManager] createDirectoryAtPath:b
                                               withIntermediateDirectories:YES
                                                                attributes:nil
                                                                     error:NULL];
            }
            if (ok && isDir) {
                path = [[b stringByAppendingPathComponent:@"MinecraftHelper.log"] copy];
                break;
            }
        }
        if (!path) path = @"/tmp/MinecraftHelper.log"; // 最终兜底
    });
    return path;
}

NSString *MHLogContents(void) {
    return MHLoggerImpl::shared().contents();
}

NSString *MHLogExportToFile(void) {
    NSString *path = MHLogFilePath();
    NSString *content = MHLogContents();
    NSError *err = nil;
    BOOL ok = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) MHLogPrint(MHLogLevelError, "log export failed: %s",
                        err ? err.localizedDescription.UTF8String : "unknown error");
    MHLogPrint(MHLogLevelInfo, "log exported -> %s (%lu bytes)", path.UTF8String,
               (unsigned long)content.length);
    return path;
}
