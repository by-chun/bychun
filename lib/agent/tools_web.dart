import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../native/native_bridge.dart';
import 'tool.dart';
import 'tool_registry.dart';

String _stripHtml(String html) {
  var s = html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
      .replaceAll(RegExp(r'<(br|/p|/div|/li|/h[1-6])[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  s = s.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// 通用 HTTP 请求（AI 对接任意 API：搜索视频/音乐/小说等）。
class HttpRequestTool extends AgentTool {
  @override
  String get name => 'httpRequest';

  @override
  String get description =>
      '发 HTTP 请求（GET/POST），返回响应文本（JSON 原样）。对接任意 API 用：拿搜索结果、解析出播放直链。';

  @override
  Map<String, String> get parameters => {
        'url': '完整 URL',
        'method': 'GET 或 POST，默认 GET',
        'headers': '可选：JSON 对象字符串，如 {"Authorization":"Bearer x"}',
        'body': '可选：POST 请求体',
      };

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final url = (args['url'] ?? '').trim();
    if (!url.startsWith('http')) return const ToolResult(false, 'url 必须是 http(s)');
    final method = (args['method'] ?? 'GET').trim().toUpperCase();
    Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (Android 14) AppleWebKit/537.36 Chrome/120 Safari/537.36',
    };
    final raw = (args['headers'] ?? '').trim();
    if (raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map;
        m.forEach((k, v) => headers[k.toString()] = v.toString());
      } catch (_) {}
    }
    try {
      final uri = Uri.parse(url);
      final resp = method == 'POST'
          ? await http.post(uri, headers: headers, body: args['body'] ?? '').timeout(const Duration(seconds: 25))
          : await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      final body = resp.body;
      return ToolResult(resp.statusCode >= 200 && resp.statusCode < 400,
          'HTTP ${resp.statusCode}\n${body.length > 20000 ? '${body.substring(0, 20000)}\n…（已截断）' : body}');
    } catch (e) {
      return ToolResult(false, '请求异常：$e');
    }
  }
}

/// 联网搜索（DuckDuckGo HTML 版，无需 key）。
class WebSearchTool extends AgentTool {
  @override
  String get name => 'webSearch';

  @override
  String get description => '联网搜索（无需 API Key）。返回标题/链接/摘要列表。';

  @override
  Map<String, String> get parameters => {'query': '搜索词', 'limit': '可选：条数，默认 8'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final q = (args['query'] ?? '').trim();
    if (q.isEmpty) return const ToolResult(false, 'query 不能为空');
    final limit = int.tryParse((args['limit'] ?? '8').trim()) ?? 8;
    try {
      final resp = await http.post(
        Uri.parse('https://html.duckduckgo.com/html/'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Android 14) AppleWebKit/537.36 Chrome/120 Safari/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'q': q},
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        return ToolResult(false, '搜索失败 HTTP ${resp.statusCode}');
      }
      final html = resp.body;
      final blocks = RegExp(r'result__a[\s\S]*?</a>').allMatches(html).toList();
      final sb = StringBuffer();
      var n = 0;
      for (final m in blocks) {
        if (n >= limit) break;
        final chunk = m.group(0)!;
        final href = RegExp(r'href="([^"]+)"').firstMatch(chunk)?.group(1) ?? '';
        final title = _stripHtml(RegExp(r'>([\s\S]*?)</a>').firstMatch(chunk)?.group(1) ?? '');
        if (title.isEmpty) continue;
        final link = href.contains('uddg=')
            ? Uri.decodeComponent(RegExp(r'uddg=([^&]+)').firstMatch(href)?.group(1) ?? href)
            : href;
        sb.writeln('${n + 1}. $title');
        sb.writeln('   $link');
        n++;
      }
      if (n == 0) return const ToolResult(true, '没有搜到结果（可能被限流，稍后重试或换关键词）');
      return ToolResult(true, sb.toString().trim());
    } catch (e) {
      return ToolResult(false, '搜索异常：$e');
    }
  }
}

/// 读网页正文（去标签转纯文本）。
class FetchPageTool extends AgentTool {
  @override
  String get name => 'fetchPage';

  @override
  String get description => '抓取网页并转成纯文本（去脚本/样式/标签）。适合读文章、文档、搜索结果页。';

  @override
  Map<String, String> get parameters => {'url': '网址', 'maxChars': '可选：最多字符数，默认 0（不限制）'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final url = (args['url'] ?? '').trim();
    if (!url.startsWith('http')) return const ToolResult(false, 'url 必须是 http(s)');
    final maxChars = int.tryParse((args['maxChars'] ?? '0').trim()) ?? 0;
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Android 14) AppleWebKit/537.36 Chrome/120 Safari/537.36',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        return ToolResult(false, '抓取失败 HTTP ${resp.statusCode}');
      }
      final text = _stripHtml(resp.body);
      if (text.isEmpty) return const ToolResult(true, '（页面没有可读正文）');
      if (maxChars > 0 && text.length > maxChars) {
        return ToolResult(true, '${text.substring(0, maxChars)}\n…（已截断）');
      }
      return ToolResult(true, text);
    } catch (e) {
      return ToolResult(false, '抓取异常：$e');
    }
  }
}

/// 流式执行容器命令：输出会实时推给界面，同时返回结尾部分给 AI。
class RunStreamTool extends AgentTool {
  /// 当前正在跑的 tag（点停止时用它杀进程）。
  static String? currentTag;

  @override
  String get name => 'runStream';

  @override
  String get description =>
      '在 Alpine 容器里流式执行命令：输出实时显示，结果全部返回给 AI。适合装包、抓包、编译等长任务。';

  @override
  Map<String, String> get parameters => {'cmd': '要执行的命令'};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final cmd = (args['cmd'] ?? '').trim();
    if (cmd.isEmpty) return const ToolResult(false, 'cmd 不能为空');
    await NativeBridge.showLogWindow(title: '实时输出');
    final tag = 'ai-${DateTime.now().millisecondsSinceEpoch}';
    currentTag = tag;
    final buf = <String>[];
    StreamSubscription? sub;
    try {
      sub = NativeBridge.outputStream.listen((e) {
        if (e['tag'] != tag) return;
        final line = e['line']?.toString();
        if (line != null) buf.add(line);
      });
      final code = await NativeBridge.streamExec(cmd, tag: tag);
      await Future.delayed(const Duration(milliseconds: 200));
      return ToolResult(code == 0, buf.isEmpty ? '（无输出，退出码 $code）' : buf.join('\n'));
    } finally {
      await sub?.cancel();
      currentTag = null;
    }
  }
}




/// 清空抓包缓冲。
class CaptureClearTool extends AgentTool {
  @override
  String get name => 'captureClear';

  @override
  String get description => '清空抓包缓冲。';

  @override
  Map<String, String> get parameters => {};

  @override
  Future<ToolResult> execute(Map<String, String> args) async {
    final ok = await NativeBridge.captureClear();
    return ToolResult(ok, ok ? '已清空' : '清空失败');
  }
}

void registerWebTools(ToolRegistry reg) {
  reg.register(WebSearchTool());
  reg.register(FetchPageTool());
  reg.register(HttpRequestTool());
  reg.register(RunStreamTool());
  reg.register(CaptureClearTool());
}
