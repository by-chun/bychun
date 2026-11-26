// 硬件执行断点（perf_event_open + HW_BREAKPOINT_X）。
// 以 daemon 模式常驻：读断点表 → 为每个地址开 perf event → poll 命中 → 记日志。
//
// 用法：
//   gmem bp <pid> <bpfile> <logfile>      常驻监听（前台，由 App 后台起）
//   gmem bp-add <bpfile> <addr>           增加断点（写入 bpfile）
//   gmem bp-del <bpfile> <addr>           删除断点
//   gmem bp-list <bpfile>                 列出断点
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <map>
#include <string>
#include <vector>

#include <fcntl.h>
#include <linux/hw_breakpoint.h>
#include <linux/perf_event.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace {

struct BpEvent {
    int fd = -1;
    void *map = nullptr;
    size_t mapLen = 0;
    uint64_t tail = 0;
};

int perfOpenBreakpoint(pid_t pid, uint64_t addr) {
    struct perf_event_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.type = PERF_TYPE_BREAKPOINT;
    attr.size = sizeof(attr);
    attr.bp_type = HW_BREAKPOINT_X;   // 执行断点
    attr.bp_addr = addr;
    attr.bp_len = HW_BREAKPOINT_LEN_4; // ARM64 指令 4 字节
    attr.sample_period = 1;
    attr.sample_type = PERF_SAMPLE_IP | PERF_SAMPLE_TID | PERF_SAMPLE_TIME;
    attr.disabled = 1;
    attr.exclude_kernel = 1;
    attr.exclude_hv = 1;
    return static_cast<int>(syscall(__NR_perf_event_open, &attr, pid, -1, -1, 0));
}

std::vector<uint64_t> readBpFile(const char *path) {
    std::vector<uint64_t> out;
    FILE *f = fopen(path, "r");
    if (!f) return out;
    char line[128];
    while (fgets(line, sizeof(line), f)) {
        char *end = nullptr;
        uint64_t v = strtoull(line, &end, 16);
        if (end != line) out.push_back(v);
    }
    fclose(f);
    return out;
}

void logLine(const char *logPath, const char *fmt, ...) {
    FILE *f = fopen(logPath, "a");
    if (!f) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

// 解析 ring buffer，把命中写入日志
int drain(BpEvent &e, uint64_t addr, const char *logPath) {
    if (e.map == nullptr) return 0;
    auto *meta = reinterpret_cast<struct perf_event_mmap_page *>(e.map);
    uint64_t head = meta->data_head;
    __sync_synchronize();
    uint64_t dataSize = e.mapLen - meta->data_offset;
    char *data = static_cast<char *>(e.map) + meta->data_offset;
    int hits = 0;

    while (e.tail < head) {
        struct perf_event_header hdr;
        uint64_t off = e.tail % dataSize;
        if (off + sizeof(hdr) > dataSize) break;
        memcpy(&hdr, data + off, sizeof(hdr));
        if (hdr.size == 0 || off + hdr.size > dataSize) break;

        if (hdr.type == PERF_RECORD_SAMPLE) {
            uint64_t ip = 0;
            uint32_t pid = 0, tid = 0;
            uint64_t t = 0;
            size_t p = off + sizeof(hdr);
            // sample_type 顺序：IP, TID(pid,tid), TIME
            memcpy(&ip, data + p, 8); p += 8;
            memcpy(&pid, data + p, 4); p += 4;
            memcpy(&tid, data + p, 4); p += 4;
            memcpy(&t, data + p, 8);
            logLine(logPath, "{\"addr\":\"0x%llx\",\"ip\":\"0x%llx\",\"pid\":%u,\"tid\":%u,\"t\":%llu}",
                    (unsigned long long)addr, (unsigned long long)ip, pid, tid, (unsigned long long)t);
            hits++;
        }
        e.tail += hdr.size;
    }
    meta->data_tail = e.tail;
    return hits;
}

}  // namespace

int bpMain(int argc, char **argv) {
    if (argc < 3) {
        printf("{\"ok\":false,\"msg\":\"usage: bp <pid> <bpfile> <logfile>\"}\n");
        return 1;
    }
    std::string cmd = argv[1];

    if (cmd == "bp-add" || cmd == "bp-del" || cmd == "bp-list") {
        const char *file = argv[2];
        if (cmd == "bp-list") {
            auto list = readBpFile(file);
            printf("{\"ok\":true,\"items\":[");
            for (size_t i = 0; i < list.size(); i++) {
                if (i) printf(",");
                printf("\"0x%llx\"", (unsigned long long)list[i]);
            }
            printf("]}\n");
            return 0;
        }
        if (argc < 4) { printf("{\"ok\":false,\"msg\":\"need addr\"}\n"); return 1; }
        uint64_t addr = strtoull(argv[3], nullptr, 16);
        auto list = readBpFile(file);
        std::vector<uint64_t> next;
        for (auto v : list) if (v != addr) next.push_back(v);
        if (cmd == "bp-add") next.push_back(addr);
        FILE *f = fopen(file, "w");
        if (!f) { printf("{\"ok\":false,\"msg\":\"write failed\"}\n"); return 2; }
        for (auto v : next) fprintf(f, "%llx\n", (unsigned long long)v);
        fclose(f);
        printf("{\"ok\":true,\"count\":%zu}\n", next.size());
        return 0;
    }

    // daemon 模式：bp <pid> <bpfile> <logfile>
    if (argc < 4) {
        printf("{\"ok\":false,\"msg\":\"usage: bp <pid> <bpfile> <logfile>\"}\n");
        return 1;
    }
    pid_t pid = static_cast<pid_t>(atoi(argv[2]));
    const char *bpFile = argv[3];
    const char *logFile = argc >= 5 ? argv[4] : "/data/local/tmp/rowan/bp.log";
    printf("{\"ok\":true,\"msg\":\"daemon started pid=%d\"}\n", pid);
    fflush(stdout);

    std::map<uint64_t, BpEvent> events;
    long pageSize = sysconf(_SC_PAGESIZE);

    for (;;) {
        // 同步断点表
        auto wanted = readBpFile(bpFile);
        for (auto it = events.begin(); it != events.end();) {
            bool still = false;
            for (auto a : wanted) if (a == it->first) { still = true; break; }
            if (!still) {
                if (it->second.map) munmap(it->second.map, it->second.mapLen);
                if (it->second.fd >= 0) close(it->second.fd);
                it = events.erase(it);
            } else {
                ++it;
            }
        }
        for (auto a : wanted) {
            if (events.count(a)) continue;
            int fd = perfOpenBreakpoint(pid, a);
            if (fd < 0) {
                logLine(logFile, "{\"error\":\"perf_open failed addr=0x%llx errno=%d\"}",
                        (unsigned long long)a, errno);
                continue;
            }
            size_t len = pageSize * 9;
            void *m = mmap(nullptr, len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
            if (m == MAP_FAILED) {
                close(fd);
                continue;
            }
            ioctl(fd, PERF_EVENT_IOC_RESET, 0);
            ioctl(fd, PERF_EVENT_IOC_ENABLE, 0);
            events[a] = BpEvent{fd, m, len, 0};
        }

        if (events.empty()) {
            usleep(400 * 1000);
            continue;
        }

        std::vector<struct pollfd> pfds;
        std::vector<uint64_t> addrs;
        for (auto &kv : events) {
            pfds.push_back({kv.second.fd, POLLIN, 0});
            addrs.push_back(kv.first);
        }
        int r = poll(pfds.data(), pfds.size(), 400);
        if (r > 0) {
            for (size_t i = 0; i < pfds.size(); i++) {
                if (pfds[i].revents & POLLIN) {
                    drain(events[addrs[i]], addrs[i], logFile);
                }
            }
        }
    }
    return 0;
}
