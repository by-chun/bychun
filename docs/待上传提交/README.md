# 待上传提交

已本地提交、**尚未推送**的改动。用户说「上传」时才推送，推完清空本目录。

当前状态：**3 个提交待推送**（基于 `origin/main`，最后一个是本存档提交）

| # | 提交 | 内容 | 涉及文件 |
|---|---|---|---|
| 1 | `0dc7721` | 编译错误修复：补 ToolRegistry import、Map 类型 cast、去 const 插值、_resultOf 去 static、_ThinkingDots 改名 | `agent_engine.dart`、`chat_page.dart`、`chat_message.dart` 等 |
| 2 | `794408c` | 补 CA/抓包/VPN 工具 + 修原生抓包与内存/媒体/路径若干 bug：新增 `ca_install`/`ca_status`、`capture_read`/`capture_to_script`、`vpn_import_sub`/`vpn_list_nodes`/`vpn_update_sub`；修 CaptureServer 头解析、vpnStart 授权时序、gmem 注入、memWatch 路径与确认、媒体进度清零/控制器泄漏、播放静默失败、Zygisk 路径对齐 | `tools_ca.dart`(新)、`tools_vpn.dart`(新)、`tools_capture.dart`、`agent_engine.dart`、`permission.dart`、`CaptureServer.kt`、`MainActivity.kt`、`gmem.dart`、`tools_mem.dart`、`default_prompt.dart`、`media_cards.dart`、`music_handler.dart` |
| 3 | `50586f1` | docs：待上传提交存档 | `docs/待上传提交/` |

## 上传步骤

```bash
git log origin/main..HEAD --oneline        # 核对与上表一致
git push origin main
```

推完把本目录的 `.patch` 删掉，上表标记为「已上传」。

## 验证点

- CA：对 AI 说「生成并安装 CA 证书」→ 调 `ca_install`（高危确认）→ 重启后系统信任区有 Rowan MITM CA；`ca_status` 可查
- 抓包：`capture_read` 读 HTTP 明文（需先跑代理上报）；`capture_to_script` 把抓到的域名导出成 `capture-block.sh` + `capture-domains.json`
- VPN：`vpn_import_sub <订阅URL>` 导入节点 → `vpn_list_nodes` 查看 → `vpn_update_sub` 更新；存 `/storage/emulated/0/Rowan/vpn/sub.json`
- 抓包明文：CaptureServer 头解析修好后，mitmproxy addon POST 到 127.0.0.1:8899/hit 能正常上报
