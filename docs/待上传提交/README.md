# 待上传提交

已本地提交、**尚未推送**的改动。用户说「上传」时才推送，推完清空本目录。

当前状态：**3 个提交待推送**（基于 `origin/main`）

| # | 提交 | 内容 | 涉及文件 |
|---|---|---|---|
| 1 | `f4b977c` | 悬浮窗对话同步 + 拖动节流；思考中提示；气泡变窄；工具行玻璃化/平铺；森林绿背景 + 灰边框；玻璃 85% 透明 + 全局滑杆；去掉主题色选择只留自定义背景；输入框裁切 | `chat_page.dart`、`chat_message.dart`、`floating_chat_app.dart`、`tree_drawer.dart`、`app_theme.dart`、`glass_kit.dart`、`liquid_glass.dart`、`main.dart`、`agent_engine.dart`、`appearance_store.dart` |
| 2 | `fef33bb` | DSH 式插件系统：`plugin.json` 声明清单、AI 工具 `plugin_create`/`list`/`toggle`/`delete`、输入框上方插件胶囊、示例插件 `local-hello`；工具调用行显示耗时 ms | `plugins_store.dart`(新)、`tools_rowan_plugin.dart`(新)、`chat_page.dart`、`chat_message.dart`、`agent_engine.dart` |
| 3 | `31bd415` | 容器双模式：有 root 自动用内核原生 chroot（零 ptrace、uid=0 是真 root），无 root 回退 PRoot；终端与 AI 工具共用；失败自动降级 | `ChrootLauncher.kt`(新)、`ProotLauncher.kt`、`TerminalActivity.kt`、`MainActivity.kt`、`tools_mcp.dart` |

## 上传步骤

```bash
git log origin/main..HEAD --oneline        # 核对与上表一致
git push origin main
```

推完把本目录的 `.patch` 删掉，上表标记为「已上传」。

## 这几项的关键验证点

- 群聊：新建时选「群聊」，设置 → 群成员 加人（开关控制参与）
- 插件：对 AI 说「做个插件…」，胶囊会出现在输入框上方
- chroot：终端标签标题显示 `chroot:<env>`；没有 root 时显示普通 env 名（PRoot）
