package com.chun.by

/** Keystone 汇编桥。 */
object NativeAsm {
    private var loaded = false

    val available: Boolean
        get() = try {
            if (!loaded) {
                System.loadLibrary("asm")
                loaded = true
            }
            true
        } catch (e: Throwable) {
            false
        }

    /** arch: "arm64"（默认）或 "arm" */
    external fun assemble(asmText: String, addr: Long, arch: String): String
}
