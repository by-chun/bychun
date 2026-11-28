import 'dart:convert';
import 'package:http/http.dart' as http;

import 'tool.dart';
import 'tool_registry.dart';
import '../native/native_bridge.dart';

/// VPN 订阅管理：订阅 URL 导入、节点列表、更新、选择，存成脚本/配置复用。
/// 实际的隧道由容器里的 sing-box / v2ray 等承担（AI 装好后读 sub.json 跑）。

const String _subPath = '/storage/emulated/0/Rowan/vpn/sub.json';

/// 把内容（base64）写入用户可见文件，返回是否成功。
Future<bool> _writeFile(String path, String content) async {
  final b64 = base64Encode(utf8.encode(content));
  final dir = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '/storage/emulated/0/Rowan';
  final r = await NativeBridge.exec(
      "mkdir -p '$dir' && printf %s '$b64' | base64 -d > '$path' && echo OK");
  return r.stdout.contains('OK');
}

Future<Map<String, dynamic>?> _readStore() async {
  final r = await NativeBridge.exec("cat '$_subPath' 2>/dev/null");
  if (r.code != 0 || r.stdout.trim().isEmpty) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(r.stdout) as Map);
  } catch (_) {
    return null;
  }
}

String _b64Decode(String s) {
  var t = s.trim();
  try {
    return utf8.decode(base64.decode(t));
  } catch (_) {
    try {
      t = t.replaceAll('-', '+').replaceAll('_', '/');
      final pad = t.length % 4;
      if (pad != 0) t += '=' * (4 - pad);
      return utf8.decode(base64.decode(t));
    } catch (_) {
      return '';
    }
  }
}

String _urlDecode(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

String _proto(String link) {
  final i = link.indexOf('://');
  return i < 0 ? '' : link.substring(0, i).toLowerCase();
}

String _extractName(String link) {
  final h = link.indexOf('#');
  if (h >= 0 && h + 1 < link.length) {
    final n = _urlDecode(link.substring(h + 1).trim());
    if (n.isNotEmpty) return n;
  }
  return '';
}

/// 解析一条节点链接 → {name, proto, host, port}。解析失败时 host 退化为原始链接。
Map<String, String> _parseNode(String link) {
  final proto = _proto(link);
  var name = _extractName(link);
  var host = '';
  var port = '';
  try {
    switch (proto) {
      case 'vmess':
        final body = link.substring('vmess://'.length).split('#').first;
        final dec = _b64Decode(body);
        if (dec.isEmpty) break;
        final m = Map<String, dynamic>.from(jsonDecode(dec) as Map);
        host = (m['add'] ?? '').toString();
        port = (m['port'] ?? '').toString();
        if (name.isEmpty) name = (m['ps'] ?? '').toString();
        break;
      case 'ss':
        var rest = link.substring('ss://'.length).split('#').first;
        var decoded = _b64Decode(rest);
        if (decoded.isEmpty) decoded = rest;
        final at = decoded.lastIndexOf('@');
        if (at >= 0) {
          final hp = decoded.substring(at + 1);
          final c = hp.lastIndexOf(':');
          if (c > 0) {
            host = hp.substring(0, c);
            port = hp.substring(c + 1);
          } else {
            host = hp;
          }
        }
        break;
      case 'ssr':
        final body = link.substring('ssr://'.length).split('/').first;
        final dec = _b64Decode(body);
        final parts = dec.split(':');
        if (parts.length >= 6) {
          host = parts[0];
          port = parts[1];
        }
        final rq = link.indexOf('remarks=');
        if (rq >= 0 && name.isEmpty) {
          name = _urlDecode(link.substring(rq + 8).split('&').first);
        }
        break;
      case 'trojan':
      case 'vless':
        var rest = link.substring(link.indexOf('://') + 3).split('#').first.split('?').first;
        final at = rest.lastIndexOf('@');
        if (at >= 0) {
          final hp = rest.substring(at + 1);
          final c = hp.lastIndexOf(':');
          if (c > 0) {
            host = hp.substring(0, c);
            port = hp.substring(c + 1);
          } else {
            host = hp;
          }
        }
        break;
      case 'hysteria2':
      case 'hy2':
      case 'tuic':
        var rest = link.substring(link.indexOf('://') + 3).split('#').first.split('?').first;
        final at = rest.lastIndexOf('@');
        if (at >= 0) rest = rest.substring(at + 1);
        final c = rest.lastIndexOf(':');
        if (c > 0) {
          host = rest.substring(0, c);
          port = rest.substring(c + 1);
        } else {
          host = rest;
        }
        break;
    }
  } catch (_) {}
  if (name.isEmpty) name = host.isEmpty ? link : '$proto://$host${port.isEmpty ? '' : ':$port'}';
  if (host.isEmpty) host = link;
  return {'name': name, 'proto': proto, 'host': host, 'port': port, 'link': link};
}

/// 解码订阅正文成节点链接列表：先按行拆，再判断是否 base64。
List<String> _decodeSub(String body) {
  var t = body.trim();
  if (t.isEmpty) return const [];
  // 已经是节点明文列表
  if (RegExp(r'(ss|ssr|vmess|vless|trojan|hysteria2|hy2|tuic)://').hasMatch(t)) {
    return t.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  final dec = _b64Decode(t);
  if (dec.isNotEmpty) t = dec;
  return t.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

class VpnImportSubTool extends AgentTool {
  @override
  String get name => 'vpn_import_sub';

  @override
  String get description =>
      '导入 VPN 订阅：传订阅 URL，抓取并解析出节点列表，存到 /storage/emulated/0/Rowan/vpn/sub.json。'
      '支持 ss/ssr/vmess/vless/trojan/hysteria2 等常见格式，明文或 base64 订阅都能解析。'
      '存成文件后下次可直接用 vpn_update_sub 更新、vpn_list_nodes 查看。';

  @override
  Map<String, String> get parameters => {'url': '订阅 URL'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final url = (args['url'] ?? '').trim();
    if (!url.startsWith('http')) return const ToolResult(false, 'url 必须是 http(s)');
    String body;
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Android 14) AppleWebKit/537.36 Chrome/120 Safari/537.36'},
      ).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return ToolResult(false, '订阅拉取失败 HTTP ${resp.statusCode}');
      body = resp.body;
    } catch (e) {
      return ToolResult(false, '订阅请求异常：$e');
    }
    final links = _decodeSub(body);
    if (links.isEmpty) return const ToolResult(false, '订阅里没有解析出节点');
    final nodes = <Map<String, String>>[for (final l in links) _parseNode(l)];
    final store = {
      'updated': DateTime.now().millisecondsSinceEpoch,
      'source': url,
      'nodes': nodes,
    };
    final ok = await _writeFile(_subPath, jsonEncode(store));
    if (!ok) return const ToolResult(false, '写入失败（检查存储权限）');
    return ToolResult(
      true,
      '已导入 ${nodes.length} 个节点，存到 $_subPath',
      view: 'list',
      title: 'VPN 节点',
      viewData: {
        'items': [
          for (final n in nodes)
            {
              'title': n['name'],
              'subtitle': '${n['proto']} · ${n['host']}${(n['port'] ?? '').isEmpty ? '' : ':${n['port']}'}',
              'badge': n['proto']!.toUpperCase(),
            },
        ],
      },
    );
  }
}

class VpnListNodesTool extends AgentTool {
  @override
  String get name => 'vpn_list_nodes';

  @override
  String get description => '列出已导入的 VPN 节点（来自订阅，存于 sub.json）。';

  @override
  Map<String, String> get parameters => const {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final store = await _readStore();
    final nodes = (store?['nodes'] as List?) ?? const [];
    if (nodes.isEmpty) return const ToolResult(true, '还没有导入节点，用 vpn_import_sub 导入。');
    final updated = (store?['updated'] as num?)?.toInt();
    return ToolResult(
      true,
      '共 ${nodes.length} 个节点${updated == null ? '' : '（${DateTime.fromMillisecondsSinceEpoch(updated)}）'}',
      view: 'list',
      title: 'VPN 节点',
      viewData: {
        'items': [
          for (final raw in nodes)
            () {
              final n = Map<String, dynamic>.from(raw as Map);
              return {
                'title': (n['name'] ?? '').toString(),
                'subtitle':
                    '${n['proto']} · ${n['host']}${(n['port'] ?? '').toString().isEmpty ? '' : ':${n['port']}'}',
                'badge': (n['proto'] ?? '').toString().toUpperCase(),
              };
            }(),
        ],
      },
    );
  }
}

class VpnUpdateSubTool extends AgentTool {
  @override
  String get name => 'vpn_update_sub';

  @override
  String get description => '用上次导入的订阅 URL 重新拉取并更新节点列表。';

  @override
  Map<String, String> get parameters => const {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final store = await _readStore();
    final url = (store?['source'] ?? '').toString();
    if (url.isEmpty) return const ToolResult(false, '还没有订阅记录，先用 vpn_import_sub 导入。');
    return VpnImportSubTool().execute({'url': url});
  }
}

void registerVpnTools(ToolRegistry reg) {
  reg.register(VpnImportSubTool());
  reg.register(VpnListNodesTool());
  reg.register(VpnUpdateSubTool());
}
