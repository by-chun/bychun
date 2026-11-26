#include <jni.h>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <vector>

static int open_mem(int pid, int flags) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/mem", pid);
    return open(path, flags);
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_chun_by_NativeMemory_readMem(JNIEnv* env, jclass, jint pid, jlong addr, jint size) {
    if (size <= 0) return nullptr;
    int fd = open_mem(pid, O_RDONLY);
    if (fd < 0) return nullptr;
    std::vector<char> buf(static_cast<size_t>(size));
    ssize_t n = pread(fd, buf.data(), static_cast<size_t>(size), static_cast<off_t>(addr));
    close(fd);
    if (n <= 0) return nullptr;
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(n));
    env->SetByteArrayRegion(arr, 0, static_cast<jsize>(n), reinterpret_cast<const jbyte*>(buf.data()));
    return arr;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_chun_by_NativeMemory_writeMem(JNIEnv* env, jclass, jint pid, jlong addr, jbyteArray data) {
    if (data == nullptr) return JNI_FALSE;
    jsize len = env->GetArrayLength(data);
    std::vector<char> buf(static_cast<size_t>(len));
    env->GetByteArrayRegion(data, 0, len, reinterpret_cast<jbyte*>(buf.data()));
    int fd = open_mem(pid, O_RDWR);
    if (fd < 0) return JNI_FALSE;
    ssize_t n = pwrite(fd, buf.data(), static_cast<size_t>(len), static_cast<off_t>(addr));
    close(fd);
    return n == len ? JNI_TRUE : JNI_FALSE;
}

// 精确 int(4 字节) 扫描：遍历可读区间搜索，上限 2000 条。
extern "C" JNIEXPORT jlongArray JNICALL
Java_com_chun_by_NativeMemory_scan(JNIEnv* env, jclass, jint pid, jint value) {
    std::vector<long> hits;
    int fd = open_mem(pid, O_RDONLY);
    if (fd < 0) return env->NewLongArray(0);

    char mapsPath[64];
    snprintf(mapsPath, sizeof(mapsPath), "/proc/%d/maps", pid);
    FILE* f = fopen(mapsPath, "r");
    if (f == nullptr) {
        close(fd);
        return env->NewLongArray(0);
    }

    unsigned char pat[4];
    memcpy(pat, &value, 4);
    const int CHUNK = 1 << 20;
    std::vector<char> buf(CHUNK);
    char line[512];

    while (fgets(line, sizeof(line), f)) {
        unsigned long start = 0, end = 0;
        char perms[8] = {0};
        if (sscanf(line, "%lx-%lx %7s", &start, &end, perms) != 3) continue;
        if (perms[0] != 'r') continue;
        unsigned long len = end - start;
        if (len == 0 || len > (64UL << 20)) continue;

        unsigned long pos = 0;
        while (pos < len && hits.size() < 2000) {
            size_t toread = static_cast<size_t>(std::min<unsigned long>(CHUNK, len - pos));
            ssize_t n = pread(fd, buf.data(), toread, static_cast<off_t>(start + pos));
            if (n <= 0) break;
            for (ssize_t i = 0; i + 4 <= n; i += 4) {
                if (memcmp(&buf[i], pat, 4) == 0) {
                    hits.push_back(static_cast<long>(start + pos + i));
                    if (hits.size() >= 2000) break;
                }
            }
            pos += static_cast<unsigned long>(n);
        }
        if (hits.size() >= 2000) break;
    }
    fclose(f);
    close(fd);

    jlongArray arr = env->NewLongArray(static_cast<jsize>(hits.size()));
    if (!hits.empty()) {
        env->SetLongArrayRegion(arr, 0, static_cast<jsize>(hits.size()), reinterpret_cast<const jlong*>(hits.data()));
    }
    return arr;
}

// 指针扫描：查找内存中值等于 target 的 8 字节指针。
extern "C" JNIEXPORT jlongArray JNICALL
Java_com_chun_by_NativeMemory_pointerScan(JNIEnv* env, jclass, jint pid, jlong target) {
    std::vector<long> hits;
    int fd = open_mem(pid, O_RDONLY);
    if (fd < 0) return env->NewLongArray(0);

    char mapsPath[64];
    snprintf(mapsPath, sizeof(mapsPath), "/proc/%d/maps", pid);
    FILE* f = fopen(mapsPath, "r");
    if (f == nullptr) {
        close(fd);
        return env->NewLongArray(0);
    }

    unsigned char pat[8];
    memcpy(pat, &target, 8);
    const int CHUNK = 1 << 20;
    std::vector<char> buf(CHUNK);
    char line[512];

    while (fgets(line, sizeof(line), f)) {
        unsigned long start = 0, end = 0;
        char perms[8] = {0};
        if (sscanf(line, "%lx-%lx %7s", &start, &end, perms) != 3) continue;
        if (perms[0] != 'r') continue;
        unsigned long len = end - start;
        if (len == 0 || len > (64UL << 20)) continue;

        unsigned long pos = 0;
        while (pos < len && hits.size() < 2000) {
            size_t toread = static_cast<size_t>(std::min<unsigned long>(CHUNK, len - pos));
            ssize_t n = pread(fd, buf.data(), toread, static_cast<off_t>(start + pos));
            if (n <= 0) break;
            for (ssize_t i = 0; i + 8 <= n; i += 8) {
                if (memcmp(&buf[i], pat, 8) == 0) {
                    hits.push_back(static_cast<long>(start + pos + i));
                    if (hits.size() >= 2000) break;
                }
            }
            pos += static_cast<unsigned long>(n);
        }
        if (hits.size() >= 2000) break;
    }
    fclose(f);
    close(fd);

    jlongArray arr = env->NewLongArray(static_cast<jsize>(hits.size()));
    if (!hits.empty()) {
        env->SetLongArrayRegion(arr, 0, static_cast<jsize>(hits.size()), reinterpret_cast<const jlong*>(hits.data()));
    }
    return arr;
}

// 指令/字节 patch（等同 writeMem）。
extern "C" JNIEXPORT jboolean JNICALL
Java_com_chun_by_NativeMemory_patchBytes(JNIEnv* env, jclass, jint pid, jlong addr, jbyteArray data) {
    if (data == nullptr) return JNI_FALSE;
    jsize len = env->GetArrayLength(data);
    std::vector<char> buf(static_cast<size_t>(len));
    env->GetByteArrayRegion(data, 0, len, reinterpret_cast<jbyte*>(buf.data()));
    int fd = open_mem(pid, O_RDWR);
    if (fd < 0) return JNI_FALSE;
    ssize_t n = pwrite(fd, buf.data(), static_cast<size_t>(len), static_cast<off_t>(addr));
    close(fd);
    return n == len ? JNI_TRUE : JNI_FALSE;
}
