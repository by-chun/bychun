/// 按模型名推断上下文长度（token）。
///
/// 模型列表接口不返回上下文窗口，只能靠命名规则匹配；匹配不到按 128k 处理。
/// 用户可在供应商编辑里手动覆盖（ProviderConfig.contextLength）。
int contextLimitFor(String model) {
  final m = model.toLowerCase().trim();
  if (m.isEmpty) return 128000;

  // 百万级
  if (m.contains('gemini-1.5-pro') || m.contains('gemini-2') || m.contains('gemini-exp')) return 1000000;
  if (m.contains('gpt-4.1')) return 1000000;
  if (m.contains('glm-4-long') || m.contains('qwen-long') || m.contains('qwen2.5-1m')) return 1000000;

  // 200k
  if (m.contains('claude')) return 200000;
  if (m.contains('qwen3') || m.contains('qwen2.5-72b') || m.contains('qwen-max')) return 131072;
  if (m.contains('o1') || m.contains('o3') || m.contains('o4')) return 200000;

  // 128k
  if (m.contains('gpt-4o') || m.contains('gpt-4-turbo') || m.contains('gpt-4.5')) return 128000;
  if (m.contains('deepseek')) return 128000;
  if (m.contains('glm-4') || m.contains('kimi') || m.contains('moonshot')) return 128000;
  if (m.contains('llama-3.1') || m.contains('llama-3.3') || m.contains('llama-4')) return 128000;
  if (m.contains('mistral-large')) return 128000;
  if (m.contains('doubao') || m.contains('hunyuan') || m.contains('ernie')) return 128000;

  // 64k 及以下
  if (m.contains('gpt-3.5')) return 16385;
  if (m.contains('gemma')) return 8192;

  return 128000;
}

/// 给人看的简写：128000 → 128k。
String fmtTokens(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
  return '$n';
}
