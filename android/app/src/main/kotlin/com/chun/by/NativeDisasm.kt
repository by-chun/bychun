package com.chun.by

/** Capstone 反汇编桥。 */
object NativeDisasm {
    private var loaded = false

    val available: Boolean
        get() = try {
            if (!loaded) {
                System.loadLibrary("disasm")
                loaded = true
            }
            true
        } catch (e: Throwable) {
            false
        }

    /**
     * @param code 待反汇编的机器码
     * @param startAddr 这段代码在目标里的虚拟地址
     * @param count 最多反汇编条数
     * @param offset 保留
     */
    external fun disasm(code: ByteArray, startAddr: Long, count: Int, offset: Long, arch: String): String
}
