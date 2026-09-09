import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'schema.dart';

/// 单例数据库句柄。所有仓储都从这里拿 `Database`。
///
/// 三端同一套 SQL：移动端走系统 SQLite，浏览器里走编译成 wasm 的 SQLite，
/// 数据落在 IndexedDB。平台差异只在 [_factory] 这一处，上层完全无感。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  DatabaseFactory? _overrideFactory;

  DatabaseFactory get _factory =>
      _overrideFactory ?? (kIsWeb ? databaseFactoryFfiWeb : databaseFactory);

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final factory = _factory;
    // web 端 getDatabasesPath() 返回的是逻辑前缀而不是文件系统路径，
    // 所以统一走 factory，不要用顶层的 getDatabasesPath()。
    final dir = await factory.getDatabasesPath();
    final path = kIsWeb ? 'itinera.db' : '$dir/itinera.db';

    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
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
      ),
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 仅测试用：注入内存库工厂。
  void overrideFactoryForTest(DatabaseFactory factory) {
    _overrideFactory = factory;
    _db = null;
  }
}
