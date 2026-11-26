import 'dart:convert';
import 'dart:io';
import '../native/native_bridge.dart';
import 'llm.dart';

/// 一个供应商配置（可多个并存，只有一个处于「当前」）。
class ProviderConfig {
  String name;
  String baseUrl;
  String apiKey;
  String protocol;
  List<String> models;
  String model;
  String balanceScript;

  /// 上下文长度（token），0 = 按模型名自动推断。
  int contextLength;

  ProviderConfig({
    this.name = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.protocol = 'OpenAI 兼容',
    List<String>? models,
    this.model = '',
    this.balanceScript = '',
    this.contextLength = 0,
  }) : models = models ?? [];

  bool get ready => baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  LlmConfig toLlm() => LlmConfig(baseUrl: baseUrl, apiKey: apiKey, model: model, models: models);

  Map<String, dynamic> toJson() => {
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'protocol': protocol,
        'models': models,
        'model': model,
        'balanceScript': balanceScript,
        'contextLength': contextLength,
      };

  factory ProviderConfig.fromJson(Map<String, dynamic> m) => ProviderConfig(
        name: (m['name'] ?? '').toString(),
        baseUrl: (m['baseUrl'] ?? '').toString(),
        apiKey: (m['apiKey'] ?? '').toString(),
        protocol: (m['protocol'] ?? 'OpenAI 兼容').toString(),
        models: ((m['models'] as List?) ?? const []).map((e) => e.toString()).toList(),
        model: (m['model'] ?? '').toString(),
        balanceScript: (m['balanceScript'] ?? '').toString(),
        contextLength: (m['contextLength'] as num?)?.toInt() ?? 0,
      );
}

/// providers.json: {"active": "name", "list": [ ... ]}
class ProviderStore {
  static Future<File?> _file() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/providers.json');
  }

  /// 旧版单配置文件（provider.json），用于迁移。
  static Future<File?> _legacyFile() async {
    final dir = await NativeBridge.appDataDir();
    if (dir.isEmpty) return null;
    return File('$dir/provider.json');
  }

  static Future<(List<ProviderConfig>, String)> loadAllWithActive() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final list = ((m['list'] as List?) ?? const [])
            .map((e) => ProviderConfig.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        return (list, (m['active'] ?? '').toString());
      }
      // 迁移旧单配置
      final lf = await _legacyFile();
      if (lf != null && await lf.exists()) {
        final m = jsonDecode(await lf.readAsString()) as Map<String, dynamic>;
        final c = LlmConfig.fromJson(m);
        if (c.ready) {
          final p = ProviderConfig(
            name: c.model.isEmpty ? '默认' : c.model,
            baseUrl: c.baseUrl,
            apiKey: c.apiKey,
            models: List.of(c.models),
            model: c.model,
          );
          await saveAll([p], p.name);
          return ([p], p.name);
        }
      }
    } catch (_) {}
    return (<ProviderConfig>[], '');
  }

  static Future<void> saveAll(List<ProviderConfig> list, String active) async {
    try {
      final f = await _file();
      await f?.writeAsString(jsonEncode({
        'active': active,
        'list': list.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {}
  }

  static ProviderConfig? activeOf(List<ProviderConfig> list, String active) {
    if (list.isEmpty) return null;
    for (final p in list) {
      if (p.name == active) return p;
    }
    return list.first;
  }

  /// 给引擎用：当前供应商的 LlmConfig（不可用则 null）。
  static Future<LlmConfig?> load() async {
    final (list, active) = await loadAllWithActive();
    final p = activeOf(list, active);
    if (p == null || !p.ready) return null;
    return p.toLlm();
  }

  /// 当前供应商的上下文长度（0 = 未知，按模型名推断）。
  static Future<int> activeContextLength() async {
    final (list, active) = await loadAllWithActive();
    for (final p in list) {
      if (p.name == active) return p.contextLength;
    }
    return list.isEmpty ? 0 : list.first.contextLength;
  }

  /// 兼容旧调用：保存为「当前供应商」（同名更新，否则新增）。
  static Future<void> save(LlmConfig cfg) async {
    final (list, active) = await loadAllWithActive();
    final p = activeOf(list, active);
    if (p != null) {
      p.baseUrl = cfg.baseUrl;
      p.apiKey = cfg.apiKey;
      p.model = cfg.model;
      p.models = List.of(cfg.models);
      await saveAll(list, p.name);
    } else {
      final np = ProviderConfig(
        name: cfg.model.isEmpty ? '默认' : cfg.model,
        baseUrl: cfg.baseUrl,
        apiKey: cfg.apiKey,
        models: List.of(cfg.models),
        model: cfg.model,
      );
      final newList = [...list, np];
      await saveAll(newList, np.name);
    }
  }
}

/// 余额查询：用供应商自己的 Base URL 去试常见接口，字段按名字猜（balance/credit/quota/remain）。
class BalanceFetcher {
  static Future<String?> fetch(ProviderConfig c) async {
    final base0 = c.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final key = c.apiKey.trim();
    if (base0.isEmpty || key.isEmpty) return null;

    final lower = base0.toLowerCase();
    final paths = <String>[
      if (lower.contains('deepseek')) '/user/balance',
      if (lower.contains('openrouter')) '/credits',
      if (lower.contains('siliconflow')) '/user/info',
      if (lower.contains('moonshot')) '/users/me/balance',
      if (lower.contains('openai') && !lower.contains('deepseek')) '/dashboard/billing/credit_grants',
      '/user/balance',
      '/balance',
      '/credits',
      '/user/info',
      '/api/user/self',
    ];
    final bases = <String>{
      base0,
      if (base0.endsWith('/v1')) base0.substring(0, base0.length - 3),
    };

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final b in bases) {
        for (final path in paths) {
          try {
            final req = await client.getUrl(Uri.parse('$b$path'));
            req.headers.set('Authorization', 'Bearer $key');
            final resp = await req.close().timeout(const Duration(seconds: 10));
            if (resp.statusCode != 200) {
              await resp.drain<void>().catchError((_) {});
              continue;
            }
            final body = await resp.transform(const SystemEncoding().decoder).join();
            final hit = _pick(jsonDecode(body));
            if (hit != null) return hit;
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
    return null;
  }

  static bool _isBalanceKey(String k) =>
      k.contains('balance') ||
      k.contains('credit') ||
      k.contains('quota') ||
      k.contains('remain') ||
      k.contains('available') ||
      k.contains('amount');

  static String _fmt(num v) {
    final d = v.toDouble();
    if (d >= 100000) return (d / 500000).toStringAsFixed(2);
    return d.toStringAsFixed(d == d.roundToDouble() ? 0 : 2);
  }

  static String? _pick(dynamic node, [int depth = 0]) {
    if (node == null || depth > 5) return null;
    if (node is Map) {
      for (final e in node.entries) {
        final k = e.key.toString().toLowerCase();
        final v = e.value;
        if (!_isBalanceKey(k)) continue;
        if (v is num) return _fmt(v);
        final parsed = v is String ? double.tryParse(v) : null;
        if (parsed != null) return _fmt(parsed);
      }
      for (final e in node.entries) {
        final r = _pick(e.value, depth + 1);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _pick(v, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }
}
