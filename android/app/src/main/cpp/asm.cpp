// 汇编：把一行 ARM64 汇编变成机器码（Keystone）。
#include <jni.h>
#include <string>
#include <vector>
#include <keystone/keystone.h>

extern "C" JNIEXPORT jstring JNICALL
Java_com_chun_by_NativeAsm_assemble(JNIEnv *env, jobject /*thiz*/,
                                    jstring asmText, jlong addr, jstring arch) {
    if (asmText == nullptr) return env->NewStringUTF("{\"ok\":false,\"msg\":\"no asm\"}");

    const char *text = env->GetStringUTFChars(asmText, nullptr);
    const char *archText = arch == nullptr ? "arm64" : env->GetStringUTFChars(arch, nullptr);

    ks_arch a = KS_ARCH_ARM64;
    ks_mode m = KS_MODE_LITTLE_ENDIAN;
    const std::string archStr = archText == nullptr ? "arm64" : std::string(archText);
    if (archStr == "arm") {
        a = KS_ARCH_ARM;
        m = KS_MODE_ARM;
    }

    ks_engine *ks = nullptr;
    if (ks_open(a, m, &ks) != KS_ERR_OK) {
        if (archText != nullptr) env->ReleaseStringUTFChars(arch, archText);
        env->ReleaseStringUTFChars(asmText, text);
        return env->NewStringUTF("{\"ok\":false,\"msg\":\"ks_open failed\"}");
    }

    unsigned char *code = nullptr;
    size_t size = 0, count = 0;
    ks_err err = static_cast<ks_err>(ks_asm(ks, text, static_cast<uint64_t>(addr), &code, &size, &count));

    std::string out;
    if (err != KS_ERR_OK) {
        char buf[128];
        snprintf(buf, sizeof(buf), "{\"ok\":false,\"msg\":\"%s\"}", ks_strerror(err));
        out = buf;
    } else {
        out = "{\"ok\":true,\"size\":";
        out += std::to_string(size);
        out += ",\"hex\":\"";
        char b[4];
        for (size_t i = 0; i < size; i++) {
            snprintf(b, sizeof(b), "%02x", code[i]);
            out += b;
        }
        out += "\"}";
        ks_free(code);
    }

    ks_close(ks);
    if (archText != nullptr) env->ReleaseStringUTFChars(arch, archText);
    env->ReleaseStringUTFChars(asmText, text);
    return env->NewStringUTF(out.c_str());
}
