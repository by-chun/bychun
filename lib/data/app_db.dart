import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_db.g.dart';

class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class SubAgents extends Table {
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get modelTier => text().withDefault(const Constant('standard'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {name};
}

/// 档位显示名；存储与提示词里仍是 light / standard / strong。
String tierLabel(String tier) => switch (tier) {
      'light' => '轻量',
      'strong' => '强力',
      _ => '标准',
    };

@DriftDatabase(tables: [Sessions, Messages, SubAgents])
class AppDb extends _$AppDb {
  AppDb() : super(driftDatabase(name: 'g'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(subAgents, subAgents.enabled);
          }
        },
      );

  Future<int> createSession(String title) =>
      into(sessions).insert(SessionsCompanion.insert(title: title));

  Stream<List<Session>> watchSessions() =>
      (select(sessions)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).watch();

  Future<int> addMessage(int sessionId, String role, String content) =>
      into(messages).insert(MessagesCompanion.insert(
        sessionId: sessionId,
        role: role,
        content: content,
      ));

  Future<List<Message>> messagesOf(int sessionId) =>
      (select(messages)..where((t) => t.sessionId.equals(sessionId))).get();

  /// 会话是否还在（用于启动时恢复上次打开的会话）。
  Future<bool> sessionExists(int id) async {
    final rows = await (select(sessions)..where((t) => t.id.equals(id))).get();
    return rows.isNotEmpty;
  }

  Future<List<SubAgent>> allSubAgents() => select(subAgents).get();

  Future<void> upsertSubAgent(SubAgentsCompanion s) =>
      into(subAgents).insertOnConflictUpdate(s);

  Future<void> deleteSession(int id) async {
    await (delete(messages)..where((t) => t.sessionId.equals(id))).go();
    await (delete(sessions)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteSubAgent(String name) =>
      (delete(subAgents)..where((t) => t.name.equals(name))).go();
}
