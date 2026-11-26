# 原生能力接入说明

本项目已包含可直接编译运行的：Flutter UI、Dart↔Kotlin 桥、终端执行、悬浮窗 Service、C++ 内存骨架。
以下为需要额外资源/依赖/root 的模块，按需启用，不影响当前 APK 构建。

## 1. PRoot + Alpine 容器（已写启动骨架 ProotLauncher.kt）
需要你自己放入两个文件（应用私有目录 `filesDir`）：
- `filesDir/proot`：aarch64 静态编译的 proot 二进制（chmod 755）
- `filesDir/alpine/`：Alpine rootfs 根目录（含 `bin/sh`）

放入后 `ProotLauncher.isReady()` 为 true，此时终端/`prootExec` 走容器；否则回退 `/system/bin/sh`。
首次可让应用把 assets 里的 rootfs 解压到 `filesDir/alpine`（自行加解压逻辑）。

## 2. C++ 内存工具（已写 native_memory.cpp / CMakeLists.txt / NativeMemory.kt）
默认不编译。启用：
1) `android/app/build.gradle.kts` 的 `android { }` 内加：
```kotlin
externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
```
2) 安装 NDK 并 pin `ndkVersion`（x64 用 `sdkmanager "ndk;27.0.12077973"`；aarch64 Termux 用社区 NDK）。
3) 重新构建即生成 `libmemory.so`。

## 3. Shizuku（ShizukuBridge.kt，占位）
加依赖并注册 ShizukuProvider，见文件注释。需设备安装并启动 Shizuku。

## 4. Frida（FridaBridge.kt，占位）
需 root + 设备端 frida-server，或用 frida-gadget 注入目标进程。应用侧负责管理脚本/启动。

## 5. Xposed / LSPosed（XposedBridge.kt，占位）
Xposed 模块是独立 APK（声明 xposedmodule + IXposedHookLoadPackage），注入由 LSPosed 完成；
主应用负责生成与管理 Hook 模块工程。

## 6. Agent 引擎（Dart 已实现骨架）
`lib/agent/`：工具契约与注册表、AgentEngine、shell/listFiles 工具、技能/记忆/子代理/MCP 数据结构。
接入大模型：在设置里配好供应商后，把用户输入发到对应 LLM，解析其返回的工具调用，交给 `ToolRegistry` 执行。
目前聊天页离线可用：`!<命令>` 执行 shell、`/tools`、`/skills`、`/subagents`、`/mcp`、`/memory`。
