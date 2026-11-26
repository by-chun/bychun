import 'dart:convert';
import 'dart:io';

class LlmToolCall {
  final String id;
  final String name;
  final Map<String, String> args;
  const LlmToolCall(this.id, this.name, this.args);
}

class LlmResponse {
  final String text;
  final List<LlmToolCall> toolCalls;
  final String? error;
  const LlmResponse(this.text, this.toolCalls, {this.error});
}

class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final List<String> models;
  const LlmConfig({required this.baseUrl, required this.apiKey, required this.model, this.models = const []});

  bool get ready =>
      baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {'baseUrl': baseUrl, 'apiKey': apiKey, 'model': model, 'models': models};

  static LlmConfig fromJson(Map<String, dynamic> m) => LlmConfig(
        baseUrl: (m['baseUrl'] ?? '').toString(),
        apiKey: (m['apiKey'] ?? '').toString(),
        model: (m['model'] ?? '').toString(),
        models: ((m['models'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

/// OpenAI 兼容 Chat Completions 客户端（含 function calling）。
class LlmClient {
  final LlmConfig config;
  LlmClient(this.config);

  HttpClient? _active;

  /// 中断当前请求（用户点停止时调用）。
  void abort() {
    try {
      _active?.close(force: true);
    } catch (_) {}
    _active = null;
  }

  /// 带重试的调用：切后台/网络抖动导致的断连会自动重试。
  /// 可重试的错误：网络中断、DNS 失败、超时、5xx。
  static bool _retryable(String e) =>
      e.contains('connection abort') ||
      e.contains('Software caused') ||
      e.contains('SocketException') ||
      e.contains('Failed host lookup') ||
      e.contains('No address associated') ||
      e.contains('timed out') ||
      e.contains('TimeoutException') ||
      e.contains('Connection closed') ||
      e.contains('HTTP 5');

  Future<LlmResponse> chat(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    LlmResponse? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 800 * attempt));
      }
      last = await _chatOnce(messages, tools);
      if (last.error == null) return last;
      if (!_retryable(last.error!)) return last;
    }
    return last ?? LlmResponse('', const [], error: '请求失败');
  }

  /// 流式调用（网络类错误自动重试；重试时不再回放已输出的字）。
  Future<LlmResponse> chatStream(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools, {
    void Function(String delta)? onDelta,
  }) async {
    LlmResponse? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(milliseconds: 600 * attempt));
      last = await _chatStreamOnce(messages, tools, onDelta: attempt == 0 ? onDelta : null);
      if (last.error == null) return last;
      if (!_retryable(last.error!)) return last;
    }
    return last ?? LlmResponse('', const [], error: '请求失败');
  }

  Future<LlmResponse> _chatStreamOnce(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools, {
    void Function(String delta)? onDelta,
  }) async {
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _active = client;
    final buf = StringBuffer();
    final acc = <int, List<String>>{}; // index -> [id, name, args]
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer ${config.apiKey}');
      req.headers.set('Accept', 'text/event-stream');
      req.write(jsonEncode(<String, dynamic>{
        'model': config.model,
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools,
        'stream': true,
      }));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        final body = await resp.transform(utf8.decoder).join();
        return LlmResponse('', const [], error: 'HTTP ${resp.statusCode}: $body');
      }
      await for (final line
          in resp.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') break;
        Map<String, dynamic> obj;
        try {
          obj = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final choices = obj['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;
        final c = delta['content'];
        if (c is String && c.isNotEmpty) {
          buf.write(c);
          onDelta?.call(c);
        }
        final tcs = delta['tool_calls'] as List?;
        if (tcs != null) {
          for (final t in tcs) {
            final m = t as Map<String, dynamic>;
            final idx = (m['index'] as num?)?.toInt() ?? 0;
            final cur = acc.putIfAbsent(idx, () => ['', '', '']);
            if (m['id'] is String) cur[0] = m['id'] as String;
            final fn = m['function'] as Map<String, dynamic>?;
            if (fn != null) {
              if (fn['name'] is String) cur[1] = cur[1] + (fn['name'] as String);
              if (fn['arguments'] is String) cur[2] = cur[2] + (fn['arguments'] as String);
            }
          }
        }
      }
      final calls = <LlmToolCall>[];
      final idxs = acc.keys.toList()..sort();
      for (final i in idxs) {
        final v = acc[i]!;
        final args = <String, String>{};
        try {
          final m = jsonDecode(v[2].isEmpty ? '{}' : v[2]) as Map<String, dynamic>;
          m.forEach((k, val) => args[k] = val.toString());
        } catch (_) {}
        calls.add(LlmToolCall(v[0], v[1], args));
      }
      return LlmResponse(buf.toString(), calls);
    } catch (e) {
      return LlmResponse(buf.toString(), const [], error: '请求失败: $e');
    } finally {
      client.close(force: true);
      _active = null;
    }
  }

  Future<LlmResponse> _chatOnce(
      List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools) async {
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');
    final client = HttpClient();
    _active = client;
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer ${config.apiKey}');
      req.write(jsonEncode(<String, dynamic>{
        'model': config.model,
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools,
      }));
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        return LlmResponse('', const [], error: 'HTTP ${resp.statusCode}: $text');
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        return LlmResponse('', const [], error: '无 choices: $text');
      }
      final msg = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>;
      final content = (msg['content'] ?? '').toString();
      final calls = <LlmToolCall>[];
      final tcs = msg['tool_calls'] as List?;
      if (tcs != null) {
        for (final t in tcs) {
          final tm = t as Map<String, dynamic>;
          final fn = tm['function'] as Map<String, dynamic>;
          final argStr = (fn['arguments'] ?? '{}').toString();
          final args = <String, String>{};
          try {
            final m = jsonDecode(argStr) as Map<String, dynamic>;
            m.forEach((k, v) => args[k] = v.toString());
          } catch (_) {}
          calls.add(LlmToolCall((tm['id'] ?? '').toString(), (fn['name'] ?? '').toString(), args));
        }
      }
      return LlmResponse(content, calls);
    } catch (e) {
      return LlmResponse('', const [], error: '请求失败: $e');
    } finally {
      client.close(force: true);
    }
  }
}
