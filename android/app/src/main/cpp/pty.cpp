#include <jni.h>
#include <pty.h>
#include <unistd.h>
#include <cstdlib>
#include <cstring>
#include <vector>

// 打开一个 PTY 并在其中运行 shell，返回 master fd（<0 失败）。
extern "C" JNIEXPORT jint JNICALL
Java_com_chun_by_PtyBridge_open(JNIEnv* env, jclass, jstring shell) {
    const char* sh = env->GetStringUTFChars(shell, nullptr);
    int master = -1;
    pid_t pid = forkpty(&master, nullptr, nullptr, nullptr);
    if (pid == 0) {
        execl(sh, sh, nullptr);
        _exit(127);
    }
    env->ReleaseStringUTFChars(shell, sh);
    return master;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_chun_by_PtyBridge_write(JNIEnv* env, jclass, jint fd, jbyteArray data) {
    jsize n = env->GetArrayLength(data);
    std::vector<char> buf(static_cast<size_t>(n));
    env->GetByteArrayRegion(data, 0, n, reinterpret_cast<jbyte*>(buf.data()));
    ssize_t w = write(fd, buf.data(), static_cast<size_t>(n));
    return static_cast<jint>(w);
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_chun_by_PtyBridge_read(JNIEnv* env, jclass, jint fd, jint size) {
    if (size <= 0) return nullptr;
    std::vector<char> buf(static_cast<size_t>(size));
    ssize_t r = read(fd, buf.data(), static_cast<size_t>(size));
    if (r <= 0) return nullptr;
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(r));
    env->SetByteArrayRegion(arr, 0, static_cast<jsize>(r), reinterpret_cast<const jbyte*>(buf.data()));
    return arr;
}

extern "C" JNIEXPORT void JNICALL
Java_com_chun_by_PtyBridge_close(JNIEnv*, jclass, jint fd) {
    if (fd >= 0) close(fd);
}
