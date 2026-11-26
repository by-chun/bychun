package com.chun.by

import com.termux.terminal.TerminalSession

/** 持有当前终端会话，供辅助键栏向它写入按键。 */
object TerminalSessionManager {
    @Volatile
    var current: TerminalSession? = null
}
