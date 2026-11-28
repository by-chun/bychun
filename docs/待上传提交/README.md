# 待上传提交

已本地提交、**尚未推送**的改动。用户说「上传」时才推送，推完清空本目录。

当前状态：**8 个提交待推送**（基于 `origin/main`）

| # | 提交 | 内容 |
|---|---|---|
| 1 | `0dc7721` | 编译错误修复（ToolRegistry import / Map cast / const 插值 / _resultOf static / _ThinkingDots 改名） |
| 2 | `794408c` | 补 CA/抓包/VPN 工具 + 修原生抓包/内存/媒体/路径 bug（ca_install/ca_status、capture_read/capture_to_script、vpn_import_sub/vpn_list_nodes/vpn_update_sub；CaptureServer 头解析、vpnStart 授权时序、gmem 注入、memWatch 路径、Zygisk 路径对齐等） |
| 3 | `20bdf04` | 视频记录集数+倍速持久化，修进度恢复竞态 |
| 4 | `4c387a9` | 音乐播放列表/循环模式/当前曲目/进度持久化（playAudio 加 playlist，audioControl 加 next/prev/loop） |
| 5 | `12cb2f0` | 全屏播放进度/集数/倍速回写并同步回卡片 |
| 6–8 | `50586f1` `f8d349a` `242a478` | docs：待上传提交存档 + 进度快照更新 |

## 上传步骤

```bash
git log origin/main..HEAD --oneline        # 核对与上表一致
git push origin main
```

推完把本目录的 `.patch` 删掉，上表标记为「已上传」。

## 验证点

- CA：对 AI 说「生成并安装 CA 证书」→ `ca_install`（高危确认）→ 重启后系统信任区有 Rowan MITM CA；`ca_status` 可查
- 抓包：`capture_read` 读 HTTP 明文（需先跑代理上报）；`capture_to_script` 导出域名屏蔽脚本
- VPN：`vpn_import_sub <订阅URL>` 导入 → `vpn_list_nodes` → `vpn_update_sub`；存 `/storage/emulated/0/Rowan/vpn/sub.json`
- 视频：播一个多集视频 → 切集/调倍速/拖动进度 → 退出重开，集数/倍速/进度从原处恢复（全屏看也记录）
- 音乐：`playAudio` 带 playlist 播列表 → `audioControl next/prev/loop` 控制，重启后列表/循环/当前曲目还在
