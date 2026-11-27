import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_db.g.dart';

class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  // single = 单会话；group = 群聊
  TextColumn get kind => text().withDefault(const Constant('single'))();
}

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // 群聊里是哪个成员说的（成员名）；单会话为空
  TextColumn get sender => text().withDefault(const Constant(''))();
}

class SubAgents extends Table {
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get modelTier => text().withDefault(const Constant('standard'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {name};
}

/// 群成员：一个供应商配置 + 可选人物 + 角色提示词；旁边开关控制是否参与。
class GroupMembers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // 对应 providers.json 里的供应商名
  TextColumn get provider => text()();
  // 可选：这个成员用的模型（空 = 用供应商默认模型）
  TextColumn get model => text().withDefault(const Constant(''))();
  // 可选：人物名
  TextColumn get persona => text().withDefault(const Constant(''))();
  // 可选：这个成员在群里的角色提示词
  TextColumn get rolePrompt => text().withDefault(const Constant(''))();
  // 气泡颜色（ARGB int）
  IntColumn get color => integer().withDefault(const Constant(0xFF4D7CFE))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}

/// 档位显示名；存储与提示词里仍是 light / standard / strong。
String tierLabel(String tier) => switch (tier) {
      'light' => '轻量',
      'strong' => '强力',
      _ => '标准',
    };

@DriftDatabase(tables: [Sessions, Messages, SubAgents, GroupMembers])
class AppDb extends _$AppDb {
  AppDb() : super(driftDatabase(name: 'g'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(subAgents, subAgents.enabled);
          }
          if (from < 3) {
            await m.addColumn(sessions, sessions.kind);
            await m.addColumn(messages, messages.sender);
            await m.createTable(groupMembers);
          }
        },
      );

  // ---------------- 会话 ----------------
  Future<int> createSession(String title, {String kind = 'single'}) =>
      into(sessions).insert(SessionsCompanion.insert(title: title, kind: Value(kind)));

  Stream<List<Session>> watchSessions() =>
      (select(sessions)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).watch();

  Future<void> setSessionKind(int id, String kind) =>
      (update(sessions)..where((t) => t.id.equals(id))).write(SessionsCompanion(kind: Value(kind)));

  /// 会话类型（single / group）；不存在返回 single。
  Future<String> sessionKind(int id) async {
    final rows = await (select(sessions)..where((t) => t.id.equals(id))).get();
    return rows.isEmpty ? 'single' : rows.first.kind;
  }

  // ---------------- 消息 ----------------
  Future<int> addMessage(int sessionId, String role, String content, {String sender = ''}) =>
      into(messages).insert(MessagesCompanion.insert(
        sessionId: sessionId,
        role: role,
        content: content,
        sender: Value(sender),
      ));

  Future<List<Message>> messagesOf(int sessionId) =>
      (select(messages)..where((t) => t.sessionId.equals(sessionId))).get();

  /// 会话是否还在（用于启动时恢复上次打开的会话）。
  Future<bool> sessionExists(int id) async {
    final rows = await (select(sessions)..where((t) => t.id.equals(id))).get();
    return rows.isNotEmpty;
  }

  // ---------------- 子代理 ----------------
  Future<List<SubAgent>> allSubAgents() => select(subAgents).get();

  Future<void> upsertSubAgent(SubAgentsCompanion s) =>
      into(subAgents).insertOnConflictUpdate(s);

  // ---------------- 群成员 ----------------
  Stream<List<GroupMember>> watchGroupMembers() => select(groupMembers).watch();

  Future<List<GroupMember>> allGroupMembers() => select(groupMembers).get();

  Future<int> addGroupMember(GroupMembersCompanion m) => into(groupMembers).insert(m);

  Future<void> updateGroupMember(GroupMembersCompanion m) =>
      into(groupMembers).insertOnConflictUpdate(m);

  Future<void> setGroupMemberEnabled(int id, bool enabled) =>
      (update(groupMembers)..where((t) => t.id.equals(id))).write(GroupMembersCompanion(enabled: Value(enabled)));

  Future<void> deleteGroupMember(int id) =>
      (delete(groupMembers)..where((t) => t.id.equals(id))).go();

  Future<void> deleteSession(int id) async {
    await (delete(messages)..where((t) => t.sessionId.equals(id))).go();
    await (delete(sessions)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteSubAgent(String name) =>
      (delete(subAgents)..where((t) => t.name.equals(name))).go();
}
