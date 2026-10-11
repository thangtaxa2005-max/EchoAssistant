import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get dueAt => integer()();
  IntColumn get durationMinutes => integer().withDefault(const Constant(0))();
  TextColumn get recurrence => text().withDefault(const Constant('none'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get originText => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get role => text()();
  TextColumn get body => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Tasks, ChatMessages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'echo_assistant'));

  @override
  int get schemaVersion => 1;

  Stream<List<Task>> watchTasks() =>
      (select(tasks)..orderBy([(t) => OrderingTerm.asc(t.dueAt)])).watch();

  Future<List<Task>> allTasks() =>
      (select(tasks)..orderBy([(t) => OrderingTerm.asc(t.dueAt)])).get();

  Future<Task?> taskById(String id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> saveTask(TasksCompanion value) async {
    await into(tasks).insertOnConflictUpdate(value);
  }

  Future<void> removeTask(String id) async {
    await (delete(tasks)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<ChatMessage>> watchMessages() =>
      (select(chatMessages)
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .watch();

  Future<void> addMessage(ChatMessagesCompanion value) async {
    await into(chatMessages).insert(value);
  }
}
