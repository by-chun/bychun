import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';

/// CA 证书相关工具：生成自签 CA 并装进系统信任区（需 root）。
/// 装好后抓包代理才能解 HTTPS 明文（配合 mitmproxy / PCAPd 等）。
class CaStatusTool extends AgentTool {
  @override
  String get name => 'ca_status';

  @override
  String get description =>
      '查看当前自签 CA 证书状态（哈希名 + PEM 内容）。未生成时为空。';

  @override
  Map<String, String> get parameters => const {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final r = await NativeBridge.caStatus();
    final hash = (r['hash'] ?? '').toString();
    final pem = (r['pem'] ?? '').toString();
    if (hash.isEmpty && pem.isEmpty) {
      return const ToolResult(true, '还没有生成 CA 证书。用 ca_install 生成并安装（需 root）。');
    }
    final tabs = <Map<String, dynamic>>[
      {
        'name': '概览',
        'rows': [
          {'k': '哈希名', 'v': hash.isEmpty ? '—' : hash},
          {'k': '安装路径', 'v': 'Android 13- 用 /system/etc/security/cacerts；14+ 走 APEX'},
          {'k': '生效', 'v': '需要重启设备'},
        ],
      },
      if (pem.isNotEmpty)
        {
          'name': '证书 PEM',
          'rows': [
            {'k': 'PEM', 'v': pem},
          ],
        },
    ];
    return ToolResult(
      true,
      '当前 CA：${hash.isEmpty ? '未生成' : hash}',
      view: 'detail',
      title: 'CA 证书',
      viewData: {'tabs': tabs},
    );
  }
}

class CaInstallTool extends AgentTool {
  @override
  String get name => 'ca_install';

  @override
  String get description =>
      '生成自签 CA 证书并装进系统信任区（需 root，装完要重启才生效）。'
      '用于让抓包代理能解 HTTPS 明文；不改已装证书时无需重复调用。';

  @override
  Map<String, String> get parameters => const {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final r = await NativeBridge.caInstall();
    final ok = r['ok'] == true;
    final log = (r['log'] ?? '').toString();
    final buf = StringBuffer();
    if (log.isNotEmpty) buf.write(log);
    if (ok) buf.write('\n\n证书已装进系统信任区，重启设备后生效。');
    return ToolResult(
      ok,
      ok ? 'CA 证书已生成并安装，重启后生效' : '安装失败',
      view: 'stream',
      title: 'CA 安装',
      viewData: {
        'lines': [
          if (log.isNotEmpty) ...log.split('\n'),
          ok ? '[ok] 已安装，重启生效' : '[fail] 安装失败（需 root）',
        ],
        'running': false,
      },
    );
  }
}

void registerCaTools(ToolRegistry reg) {
  reg.register(CaStatusTool());
  reg.register(CaInstallTool());
}
