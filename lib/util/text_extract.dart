import 'dart:convert';

import 'package:http/http.dart' as http;

import '../native/native_bridge.dart';

/// 抓一章/一页正文并转成纯文本。失败返回 null。
Future<String?> fetchChapterText(String url) async {
  if (!url.startsWith('http')) return null;
  try {
    final resp = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    }).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    var charset = 'utf-8';
    final ct = (resp.headers['content-type'] ?? '').toLowerCase();
    if (ct.contains('gbk') || ct.contains('gb2312')) charset = 'gbk';
    final head = latin1.decode(resp.bodyBytes.take(2048).toList());
    final m = RegExp("charset\\s*=\\s*[\"']?([\\w-]+)", caseSensitive: false).firstMatch(head);
    if (m != null) charset = m.group(1)!.toLowerCase();
    String body;
    if (charset.contains('utf-8') || charset.contains('utf8')) {
      body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    } else {
      final decoded = await NativeBridge.decodeText(resp.bodyBytes, charset);
      body = decoded ?? utf8.decode(resp.bodyBytes, allowMalformed: true);
    }
    final text = stripHtml(body);
    return text.trim().isEmpty ? null : text.trim();
  } catch (_) {
    return null;
  }
}

String stripHtml(String html) {
  var s = html
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
      .replaceAll(RegExp(r'<(br|/p|/div|/h[1-6]|/li)[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final n = int.tryParse(m.group(1)!);
    return n == null ? '' : String.fromCharCode(n);
  });
  s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final n = int.tryParse(m.group(1)!, radix: 16);
    return n == null ? '' : String.fromCharCode(n);
  });
  final lines = s
      .split('\n')
      .map((e) => e.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ').trim())
      .where((e) => e.isNotEmpty);
  return lines.join('\n\n');
}
