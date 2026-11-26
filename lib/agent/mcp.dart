import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';

/// MCP Server 配置（HTTP JSON-RPC）。
class McpServer {
  String name;
  String url;
  Map<String, String> headers;

  /// 关掉后 AI 看不到这个 MCP，也不会去连（留着不用删）。
  bool enabled;

  McpServer({
    this.name = '',
    this.url = '',
    Map<String, String>? headers,
    this.enabled = true,
  }) : headers = headers ?? {};

  Map<String, dynamic> toJson() =>
      {'name': name, 'url': url, 'headers': headers, 'enabled': enabled};

  factory McpServer.fromJson(Map<String, dynamic> m) => McpServer(
        name: (m['name'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        headers: ((m['headers'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        enabled: m['enabled'] != false,
      );
}

class McpStore {
  static Future<File?> _file() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/mcp.json');
  }

  static Future<List<McpServer>> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => McpServer.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<McpServer> list) async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}

/// 最小 MCP 客户端：initialize -> tools/list -> tools/call（HTTP JSON-RPC）。
class McpClient {
  static int _id = 0;

  static Future<dynamic> _rpc(McpServer s, String method, Map<String, dynamic> params) async {
    final c = HttpClient();
    try {
      c.connectionTimeout = const Duration(seconds: 10);
      final req = await c.postUrl(Uri.parse(s.url));
      req.headers.contentType = ContentType.json;
      s.headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({'jsonrpc': '2.0', 'id': ++_id, 'method': method, 'params': params}));
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final body = await resp.transform(utf8.decoder).join();
      if (body.isEmpty) return null;
      return jsonDecode(body);
    } finally {
      c.close();
    }
  }

  static Future<void> _init(McpServer s) async {
    await _rpc(s, 'initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'Rowan', 'version': '1.0'},
    });
    await _rpc(s, 'notifications/initialized', {});
  }

  static Future<List<dynamic>> listTools(McpServer s) async {
    await _init(s);
    final r = await _rpc(s, 'tools/list', {});
    final tools = (r?['result']?['tools']) as List?;
    return tools ?? [];
  }

  static Future<String> callTool(McpServer s, String name, Map<String, dynamic> args) async {
    await _init(s);
    final r = await _rpc(s, 'tools/call', {'name': name, 'arguments': args});
    final content = r?['result']?['content'];
    if (content is List) {
      return content.map((e) => e is Map ? (e['text'] ?? e.toString()) : e.toString()).join('\n');
    }
    return r?.toString() ?? '无返回';
  }
}
