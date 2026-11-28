import 'dart:convert';

import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';

/// 读写监听（watchpoint）—— 靠 Zygisk Frida gadget 盯住地址，找出谁在读/写它。
/// gadget 默认 listen 在 127.0.0.1:27042，容器里用 frida 连上去跑脚本、命中实时回传。

class MemWatchTool extends AgentTool {
  @override
  String get name => 'memWatch';

  @override
  String get description =>
      '读写监听：盯住目标进程的某个地址，找出谁在读/写它（需 root + Zygisk Frida 模块，'
      'gadget listen 在 127.0.0.1:27042）。mode 支持 r(读)/w(写)/rw(读写)。'
      '返回要跑的 Frida 脚本；在容器里 frida 连上去执行后，命中会实时回传。';

  @override
  Map<String, String> get parameters => {
        'addr': '要监听的地址（0x..）',
        'size': '字节数，默认 8',
        'mode': 'r / w / rw，默认 w',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final addr = (args['addr'] ?? '').trim();
    final size = int.tryParse(args['size'] ?? '8') ?? 8;
    var mode = (args['mode'] ?? 'w').trim().toLowerCase();
    if (addr.isEmpty) return const ToolResult(false, 'addr 不能为空');
    if (mode != 'r' && mode != 'w' && mode != 'rw') mode = 'w';
    if (size <= 0 || size > 4096) return const ToolResult(false, 'size 需在 1~4096');

    final js = _script(addr, size, mode);
    final b64 = base64Encode(utf8.encode(js));

    // 把脚本写到运行时 scripts 目录（供 gadget 或 frida 直接加载），失败也不阻断
    String? scriptPath;
    final w = await NativeBridge.rootExec(
        "mkdir -p /data/local/tmp/rowan/scripts && echo '$b64' | base64 -d > /data/local/tmp/rowan/scripts/memwatch.js && echo WROTE");
    if ((w.stdout).contains('WROTE')) {
      scriptPath = '/data/local/tmp/rowan/scripts/memwatch.js';
    }

    return ToolResult(
      true,
      '已生成读写监听脚本（$addr · $mode · $size 字节）。\n'
      '${scriptPath != null ? '脚本已写到 $scriptPath\n' : '脚本写入失败（无 root / 模块未装），脚本内容见下：\n'}\n'
      '执行方式：容器里 pip install frida-tools 后，frida 连 127.0.0.1:27042 跑这段脚本，命中实时回传。\n\n$js',
      view: 'stream',
      title: 'memWatch · $addr',
    );
  }

  static String _script(String addr, int size, String mode) {
    return '''
// Rowan memWatch —— 读写监听
const ADDR = ptr("$addr");
const SIZE = $size;
const MODE = "$mode"; // r / w / rw

try {
  MemoryAccessMonitor.enable([{ base: ADDR, size: SIZE }], {
    onAccess(d) {
      if (MODE === "r" && d.operation !== "read") return;
      if (MODE === "w" && d.operation !== "write") return;
      send({ op: d.operation, addr: d.address.toString(), from: d.from.toString() });
    }
  });
  send({ ready: true, addr: ADDR.toString(), size: SIZE, mode: MODE });
} catch (e) {
  send({ error: String(e && e.message ? e.message : e) });
}
''';
  }
}

void registerMemTools(ToolRegistry reg) {
  reg.register(MemWatchTool());
}
