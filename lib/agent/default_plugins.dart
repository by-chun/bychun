import 'script_store.dart';

/// 首次启动写入的插件（全部可编辑、可删除）。
/// 类型说明：rule=注入系统提示的规则；其余是可执行插件。
List<Script> defaultPlugins() => [
      Script(name: '手册·容器', type: 'rule', content: '''
容器是 Alpine（containerShell 执行），默认只有 busybox。
1) 先 apk update。官方源慢/失败就换源（版本必须与容器一致（看容器内 /etc/alpine-release，当前 3.21））：
   printf "https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.21/main\\n" > /etc/apk/repositories
   printf "https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.21/community\\n" >> /etc/apk/repositories
   apk update
   （阿里源把 mirrors.tuna.tsinghua.edu.cn 换成 mirrors.aliyun.com）
2) 常用：apk add python3 py3-pip curl git nodejs lua5.3 binutils openjdk17 poppler-utils aria2 rclone
   pip 若报 externally-managed：加 --break-system-packages
3) 多行脚本用 writeFile 写文件（原文写入，不用转义），再 containerShell 执行。
4) 容器根目录 = App files/alpine；宿主可直接读写的容器路径就是 /root /tmp 等。
'''),
      Script(name: '手册·抓包', type: 'rule', content: '''
抓包链路（HTTPS 也能解）：mitmproxy → addon → 上报本机 8899 → captureLog 读取。
1) apk add mitmproxy
2) 用 writeFile 写 /root/mitm/capture.py：
   from mitmproxy import http
   import json, urllib.request
   def response(flow: http.HTTPFlow):
       rec = {"method": flow.request.method, "url": flow.request.pretty_url,
              "status": flow.response.status_code,
              "req": flow.request.get_text(strict=False)[:2000],
              "res": flow.response.get_text(strict=False)[:4000]}
       try:
           urllib.request.urlopen(urllib.request.Request(
               "http://127.0.0.1:8899/hit", json.dumps(rec).encode(),
               {"Content-Type": "application/json"}), timeout=2)
       except Exception:
           pass
3) 启动：mitmdump -s /root/mitm/capture.py --set confdir=/root/.mitmproxy -q -p 8080 &
4) 让流量走代理：代理 App（如 PCAPd）设 127.0.0.1:8080，或 root 下 iptables 重定向
5) 证书：/root/.mitmproxy/mitmproxy-ca-cert.pem 装成系统证书（root，放 /system/etc/security/cacerts/，文件名改哈希.0）
6) 看结果：captureLog(limit) 或悬浮窗 fetch("http://127.0.0.1:8899/hits")
7) 有 SSL Pinning 抓不到 → 用 Frida hook（Rowan Frida 模块）
'''),
      Script(name: '手册·网盘下载', type: 'rule', content: '''
网盘不要把 SDK 打进 App，容器里解决：
- 多网盘统一（阿里/夸克/115/百度/123/天翼/移动/光鸭）：用 openlist（Go 单文件）
  下载 aarch64 静态二进制 → openlist server → 得到 WebDAV/HTTP 直链
- rclone（apk add rclone）：挂载/同步云盘，也可 rclone copy 下载
- aria2（apk add aria2）：aria2c -x16 -s16 "直链" -d /root/dl 多线程下载
- 蓝奏云/123 等无 CLI 的：写 python 脚本解析（社区有现成实现，先 webSearch 找）
'''),
      Script(name: '手册·悬浮窗', type: 'rule', content: '''
两种悬浮窗，都能用：
A) HTML（快、稳）：createOverlay(html)
   按钮调用：Rowan.call("工具名", JSON.stringify(参数), "回调id")
   结果返回：window.__rowanResult(cbId, jsonString)
   可用工具：memScan/memRead/memWrite/playAudio/playVideo/httpRequest/webSearch/shell/containerShell
   尺寸样式随 HTML（壳默认 320x520dp，内容自适应）
B) Java（原生、能力强）：runJavaOverlay(dexPath, className)
   容器里：apk add openjdk17 → 下 android.jar 与 r8.jar
   javac -cp android.jar -d out X.java
   java -cp r8.jar com.android.tools.r8.D8 --lib android.jar --output . out/X.class
   → classes.dex 交给 runJavaOverlay，入口 public static void run(Context)
'''),
      Script(name: '手册·内存与逆向', type: 'rule', content: '''
- 找进程：listApps → pid；memScan(pid, value) 搜 32 位整数
- 读：memRead(pid, address, size)；写：memWrite(pid, address, value, type)
- 反汇编：逆向页看 .so
- 内存操作全部需要 root；没 root 会失败
'''),
      Script(name: '示例·点歌', type: 'api', content: '''
# 用法：把下面的 URL 换成你的音乐 API，AI 会把 {kw} 替换成歌名
# 返回 JSON 里取音频直链字段（示例为 data.url），然后 playAudio(直链, 歌名)
curl -s "https://你的API/search?keyword={kw}" | head -c 4000
'''),
      Script(name: '示例·系统信息', type: 'shell', content: '''
echo "== CPU =="; cat /proc/loadavg
echo "== 内存 =="; free -m 2>/dev/null || head -3 /proc/meminfo
echo "== 磁盘 =="; df -h /
echo "== 进程 TOP =="; top -b -n 1 | head -12
'''),
    ];
