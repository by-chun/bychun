# 第三方代码声明

本项目整体以 **GPL-3.0** 发布（见根目录 `LICENSE`）。

## 包含的第三方代码

### JsxposedX 内存引擎
- 位置：`android/app/src/main/cpp/memtool/`
- 来源：https://github.com/JsxposedX/JsxposedX
- 许可证：GNU GPL-3.0
- 说明：完整的进程内存搜索/读写/指针扫描/硬件断点引擎（`memory_tool_*.cpp/h`）。
  本地修改仅限 JNI 符号名（包名适配），其余保持原样。

## 其他依赖
- Capstone（BSD-3-Clause）：反汇编
- Keystone（GPL-2.0 with LLVM exception）：汇编
- Termux terminal-emulator / terminal-view（Apache-2.0 / GPL 混合，见各自模块）
- Rhino（MPL-2.0）：Xposed JS 脚本引擎
