package com.chun.by

/**
 * Xposed / LSPosed 骨架（未启用）。
 * 说明：Xposed 模块本身是一个独立 APK，需在 Manifest 声明
 *   <meta-data android:name="xposedmodule" android:value="true"/>
 * 并实现 de.robv.android.xposed.IXposedHookLoadPackage。
 * 普通应用无法直接注入 Hook —— 本应用的职责是“生成/管理 Hook 脚本与模块工程”，
 * 注入由 LSPosed 框架完成。当前仅占位。
 */
object XposedBridge {
    fun isLsposedActive(): Boolean = false
}
