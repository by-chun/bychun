// 反汇编：给一段机器码 + 起始虚拟地址，返回指令列表（JSON）。支持 arm64 / arm。
#include <jni.h>
#include <cstdio>
#include <string>
#include <sstream>
#include <vector>
#include <capstone/capstone.h>

extern "C" JNIEXPORT jstring JNICALL
Java_com_chun_by_NativeDisasm_disasm(JNIEnv *env, jobject /*thiz*/,
                                     jbyteArray code, jlong startAddr, jint count,
                                     jlong offset, jstring arch) {
    (void) offset;
    if (code == nullptr) return env->NewStringUTF("{\"ok\":false,\"msg\":\"no code\"}");

    jsize len = env->GetArrayLength(code);
    jbyte *buf = env->GetByteArrayElements(code, nullptr);
    auto *bytes = reinterpret_cast<uint8_t *>(buf);

    const char *a = arch == nullptr ? "arm64" : env->GetStringUTFChars(arch, nullptr);
    std::string archStr = a == nullptr ? "arm64" : std::string(a);

    cs_arch ca = CS_ARCH_ARM64;
    cs_mode cm = CS_MODE_ARM;
    if (archStr == "arm") {
        ca = CS_ARCH_ARM;
        cm = CS_MODE_ARM;
    }

    csh handle;
    if (cs_open(ca, cm, &handle) != CS_ERR_OK) {
        env->ReleaseByteArrayElements(code, buf, JNI_ABORT);
        return env->NewStringUTF("{\"ok\":false,\"msg\":\"cs_open failed\"}");
    }
    cs_option(handle, CS_OPT_DETAIL, CS_OPT_OFF);

    cs_insn *insn = nullptr;
    size_t n = cs_disasm(handle, bytes, static_cast<size_t>(len),
                         static_cast<uint64_t>(startAddr), static_cast<size_t>(count), &insn);

    std::ostringstream os;
    os << "{\"ok\":true,\"arch\":\"" << archStr << "\",\"items\":[";
    for (size_t i = 0; i < n; i++) {
        if (i) os << ",";
        os << "{\"addr\":\"" << std::hex << insn[i].address << "\",";
        os << "\"mnemonic\":\"" << insn[i].mnemonic << "\",";
        os << "\"opStr\":\"" << insn[i].op_str << "\",";
        os << "\"bytes\":\"";
        for (int b = 0; b < insn[i].size; b++) {
            char tmp[4];
            snprintf(tmp, sizeof(tmp), "%02x", insn[i].bytes[b]);
            os << tmp;
        }
        os << "\",\"size\":" << std::dec << insn[i].size << "}";
    }
    os << "]}";

    if (n > 0) cs_free(insn, n);
    cs_close(&handle);
    if (a != nullptr) env->ReleaseStringUTFChars(arch, a);
    env->ReleaseByteArrayElements(code, buf, JNI_ABORT);
    return env->NewStringUTF(os.str().c_str());
}
