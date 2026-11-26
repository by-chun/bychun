import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../agent/agent_engine.dart';
import '../data/db_provider.dart';

/// 全局唯一的 Agent 引擎（注入数据库，供技能/子代理统一读取）。
final agentEngineProvider = Provider<AgentEngine>((ref) {
  return AgentEngine(ref.read(appDbProvider));
});
