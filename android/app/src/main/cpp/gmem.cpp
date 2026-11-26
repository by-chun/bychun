// gmem：以 root 身份读写/扫描目标进程内存的小工具。
// 用法（由 App 通过 su -c 调用）：
//   gmem regions <pid>
//   gmem read <pid> <addr> <size>
//   gmem write <pid> <addr> <hex>
//   gmem scan <pid> <type> <value> [max] [region]   (type: i32/i64/f32/f64/bytes; region: all/ca/jh/cd/s)
//   gmem threads <pid>
// 输出：单行 JSON（方便 Dart 侧解析）

#include <algorithm>

int bpMain(int argc, char **argv);

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <unistd.h>
#include <vector>
#include <dirent.h>
#include <sys/stat.h>

static std::string hex(uint64_t v) {
    char b[32];
    snprintf(b, sizeof(b), "0x%llx", (unsigned long long)v);
    return b;
}

static bool read_mem(int fd, uint64_t addr, void *buf, size_t size) {
    return pread(fd, buf, size, (off_t)addr) == (ssize_t)size;
}

static std::vector<std::pair<uint64_t, uint64_t>> rw_regions(int pid, const std::string &region) {
    std::vector<std::pair<uint64_t, uint64_t>> out;
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/maps", pid);
    FILE *f = fopen(path, "r");
    if (!f) return out;
    char line[512];
    while (fgets(line, sizeof(line), f)) {
        uint64_t s = 0, e = 0;
        char perms[8] = {0};
        if (sscanf(line, "%llx-%llx %7s", (unsigned long long *)&s, (unsigned long long *)&e, perms) != 3) continue;
        if (!strstr(perms, "rw")) continue;
        std::string pn;
        const char *slash = strchr(line, '/');
        const char *br = strchr(line, '[');
        const char *st = nullptr;
        if (slash && br) st = (slash < br) ? slash : br;
        else if (slash) st = slash;
        else if (br) st = br;
        if (st) { pn = st; if (!pn.empty() && pn.back() == '\n') pn.pop_back(); }

        bool ok = false;
        if (region.empty() || region == "all" || region == "a") ok = true;
        else if (region == "ca" || region == "anon") ok = pn.empty() || pn.find("[anon") != std::string::npos;
        else if (region == "jh" || region == "java") ok = pn.find("dalvik") != std::string::npos || pn.find("ashmem") != std::string::npos;
        else if (region == "s" || region == "stack") ok = pn.find("[stack") != std::string::npos;
        else if (region == "cd" || region == "data") ok = !pn.empty() && pn[0] == '/';
        else ok = true;
        if (ok) out.emplace_back(s, e);
    }
    fclose(f);
    return out;
}


int main(int argc, char **argv) {
    if (argc >= 2 && std::string(argv[1]).rfind("bp", 0) == 0) {
        return bpMain(argc, argv);
    }
    if (argc < 3) {
        printf("{\"ok\":false,\"msg\":\"usage\"}\n");
        return 1;
    }
    std::string cmd = argv[1];
    int pid = atoi(argv[2]);

    char mempath[64];
    snprintf(mempath, sizeof(mempath), "/proc/%d/mem", pid);

    if (cmd == "regions") {
        char path[64];
        snprintf(path, sizeof(path), "/proc/%d/maps", pid);
        FILE *f = fopen(path, "r");
        if (!f) { printf("{\"ok\":false,\"msg\":\"no maps (need root)\"}\n"); return 2; }
        printf("{\"ok\":true,\"regions\":[");
        char line[512];
        bool first = true;
        while (fgets(line, sizeof(line), f)) {
            size_t n = strlen(line);
            if (n && line[n - 1] == '\n') line[n - 1] = 0;
            if (!first) printf(",");
            printf("\"%s\"", line);
            first = false;
        }
        fclose(f);
        printf("]}\n");
        return 0;
    }

    if (cmd == "threads") {
        char path[64];
        snprintf(path, sizeof(path), "/proc/%d/task", pid);
        DIR *d = opendir(path);
        if (!d) { printf("{\"ok\":false,\"msg\":\"no task (need root)\"}\n"); return 2; }
        printf("{\"ok\":true,\"threads\":[");
        bool first = true;
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            if (!first) printf(",");
            printf("\"%s\"", e->d_name);
            first = false;
        }
        closedir(d);
        printf("]}\n");
        return 0;
    }

    int fd = open(mempath, O_RDWR);
    if (fd < 0) fd = open(mempath, O_RDONLY);
    if (fd < 0) {
        printf("{\"ok\":false,\"msg\":\"open mem failed (need root)\"}\n");
        return 2;
    }

    if (cmd == "read" && argc >= 5) {
        uint64_t addr = strtoull(argv[3], nullptr, 16);
        size_t size = (size_t)strtoul(argv[4], nullptr, 10);
        if (size == 0 || size > 4096) size = 4;
        std::vector<uint8_t> buf(size);
        if (!read_mem(fd, addr, buf.data(), size)) {
            printf("{\"ok\":false,\"msg\":\"read failed\"}\n");
            close(fd);
            return 3;
        }
        printf("{\"ok\":true,\"addr\":\"%s\",\"hex\":\"", hex(addr).c_str());
        for (auto b : buf) printf("%02x", b);
        printf("\"}\n");
        close(fd);
        return 0;
    }

    if (cmd == "write" && argc >= 5) {
        std::string h = argv[4];
        std::vector<uint8_t> bytes;
        for (size_t i = 0; i + 1 < h.size(); i += 2) {
            bytes.push_back((uint8_t)strtoul(h.substr(i, 2).c_str(), nullptr, 16));
        }
        uint64_t addr = strtoull(argv[3], nullptr, 16);
        bool ok = pwrite(fd, bytes.data(), bytes.size(), (off_t)addr) == (ssize_t)bytes.size();
        printf("{\"ok\":%s,\"msg\":\"%s\"}\n", ok ? "true" : "false", ok ? "written" : "write failed");
        close(fd);
        return ok ? 0 : 3;
    }

    if (cmd == "scan" && argc >= 5) {
        std::string type = argv[3];
        size_t max_hits = argc >= 6 ? (size_t)strtoul(argv[5], nullptr, 10) : 200;

        int32_t i32v = 0; int64_t i64v = 0; float f32v = 0; double f64v = 0;
        std::vector<uint8_t> bytes;
        size_t val_size = 0;
        if (type == "i32") { i32v = (int32_t)strtol(argv[4], nullptr, 0); val_size = 4; }
        else if (type == "i64") { i64v = (int64_t)strtoll(argv[4], nullptr, 0); val_size = 8; }
        else if (type == "f32") { f32v = strtof(argv[4], nullptr); val_size = 4; }
        else if (type == "f64") { f64v = strtod(argv[4], nullptr); val_size = 8; }
        else if (type == "bytes") {
            std::string h = argv[4];
            for (size_t i = 0; i + 1 < h.size(); i += 2) bytes.push_back((uint8_t)strtoul(h.substr(i, 2).c_str(), nullptr, 16));
            val_size = bytes.size();
            if (val_size == 0) { printf("{\"ok\":false,\"msg\":\"empty bytes\"}\n"); close(fd); return 3; }
        } else {
            printf("{\"ok\":false,\"msg\":\"bad type (i32/i64/f32/f64/bytes)\"}\n"); close(fd); return 3;
        }

        size_t stride = (type == "bytes") ? 1 : (val_size == 8 ? 8 : 4);
        std::string region = argc >= 7 ? argv[6] : "all";
        auto regions = rw_regions(pid, region);
        std::vector<uint64_t> hits;
        std::vector<uint8_t> chunk(1024 * 1024);
        for (auto &r : regions) {
            uint64_t s = r.first;
            uint64_t e = r.second;
            if (e <= s || e - s > (uint64_t)512 * 1024 * 1024) continue; // 跳过异常大段
            for (uint64_t cur = s; cur + val_size <= e && hits.size() < max_hits; cur += chunk.size()) {
                size_t want = (size_t)std::min<uint64_t>(chunk.size(), e - cur);
                ssize_t got = pread(fd, chunk.data(), want, (off_t)cur);
                if (got <= 0) break;
                for (ssize_t i = 0; i + (ssize_t)val_size <= got && hits.size() < max_hits; i += (ssize_t)stride) {
                    bool match = false;
                    if (type == "i32") { int32_t v; memcpy(&v, chunk.data() + i, 4); match = (v == i32v); }
                    else if (type == "i64") { int64_t v; memcpy(&v, chunk.data() + i, 8); match = (v == i64v); }
                    else if (type == "f32") { float v; memcpy(&v, chunk.data() + i, 4); match = (v == f32v); }
                    else if (type == "f64") { double v; memcpy(&v, chunk.data() + i, 8); match = (v == f64v); }
                    else if (type == "bytes") { match = (memcmp(chunk.data() + i, bytes.data(), val_size) == 0); }
                    if (match) {
                        hits.push_back(cur + (uint64_t)i);
                        if (hits.size() >= max_hits) break;
                    }
                }
            }
            if (hits.size() >= max_hits) break;
        }
        printf("{\"ok\":true,\"count\":%zu,\"hits\":[", hits.size());
        for (size_t i = 0; i < hits.size(); i++) {
            if (i) printf(",");
            printf("\"%s\"", hex(hits[i]).c_str());
        }
        printf("]}\n");
        close(fd);
        return 0;
    }

    printf("{\"ok\":false,\"msg\":\"unknown command\"}\n");
    close(fd);
    return 1;
}
