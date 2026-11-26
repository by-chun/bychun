package com.chun.by

/** PTY 真交互终端 JNI 桥（需 NDK 编 libpty.so，未启用时 available=false）。 */
object PtyBridge {
    var available = false
        private set

    init {
        try {
            System.loadLibrary("pty")
            available = true
        } catch (_: Throwable) {
            available = false
        }
    }

    external fun open(shell: String): Int
    external fun write(fd: Int, data: ByteArray): Int
    external fun read(fd: Int, size: Int): ByteArray?
    external fun close(fd: Int)
}
