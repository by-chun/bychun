package com.chun.by

/**
 * C++ 内存工具 JNI 桥。默认未启用 NDK，loadLibrary 失败时 available=false，
 * 上层据此降级，不影响基础功能。启用步骤见 cpp/CMakeLists.txt。
 */
object NativeMemory {
    var available = false
        private set

    init {
        try {
            System.loadLibrary("memory")
            available = true
        } catch (_: Throwable) {
            available = false
        }
    }

    external fun readMem(pid: Int, addr: Long, size: Int): ByteArray?
    external fun writeMem(pid: Int, addr: Long, data: ByteArray): Boolean
    external fun scan(pid: Int, value: Int): LongArray?
    external fun pointerScan(pid: Int, target: Long): LongArray?
    external fun patchBytes(pid: Int, addr: Long, data: ByteArray): Boolean
}
