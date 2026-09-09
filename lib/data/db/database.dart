import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// 单例数据库句柄。所有仓储都从这里拿 `Database`。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'itinera.db');
    return openDatabase(
      path,
      version: Schema.version,
      onConfigure: (db) async {
        // sqflite 默认不开外键，级联删除依赖它。
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final sql in Schema.createStatements) {
          batch.execute(sql);
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 是首个版本，后续迁移在此按 oldVersion 逐档补。
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 仅测试用：注入内存库或 ffi 库。
  // ignore: use_setters_to_change_properties
  void overrideForTest(Database db) => _db = db;
}
