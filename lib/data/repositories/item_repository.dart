import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/time_utils.dart';
import '../db/database.dart';
import '../models/attachment.dart';
import '../models/plan_item.dart';

class ItemRepository {
  ItemRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;
  static const _uuid = Uuid();

  String newId() => _uuid.v4();

  /// 一次性拉出整趟行程的条目并挂上附件（N+1 查询在行程规模下没必要，
  /// 一趟行程通常几十条，两次查询就够）。
  Future<List<PlanItem>> itemsOfTrip(String tripId) async {
    final db = await _db.database;
    final itemRows = await db.query(
      'plan_items',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'date ASC, start_minutes IS NULL, start_minutes ASC, sort_order ASC',
    );
    if (itemRows.isEmpty) return const [];

    final ids = itemRows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final attachmentRows = await db.query(
      'attachments',
      where: 'item_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'sort_order ASC',
    );
    final grouped = <String, List<Attachment>>{};
    for (final row in attachmentRows) {
      final a = Attachment.fromRow(row);
      grouped.putIfAbsent(a.itemId, () => []).add(a);
    }

    return itemRows
        .map((row) => PlanItem.fromRow(row, attachments: grouped[row['id']] ?? const []))
        .toList();
  }

  Future<List<PlanItem>> itemsOfDay(String tripId, DateOnly date) async {
    final all = await itemsOfTrip(tripId);
    return all.where((i) => i.date == date).toList();
  }

  Future<void> upsertItem(PlanItem item) async {
    final db = await _db.database;
    await db.insert(
      'plan_items',
      item.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteItem(String id) async {
    final db = await _db.database;
    await db.delete('plan_items', where: 'id = ?', whereArgs: [id]);
  }

  /// 手动拖拽排序后落库：只写 sort_order，不动时间。
  Future<void> reorder(List<PlanItem> orderedItems) async {
    final db = await _db.database;
    final batch = db.batch();
    for (var i = 0; i < orderedItems.length; i++) {
      batch.update(
        'plan_items',
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [orderedItems[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// 把一条安排整体挪到另一天，落到目标日末尾。
  Future<void> moveToDate(PlanItem item, DateOnly target) async {
    final db = await _db.database;
    final maxRow = await db.rawQuery(
      'SELECT MAX(sort_order) AS m FROM plan_items WHERE trip_id = ? AND date = ?',
      [item.tripId, target.toIso()],
    );
    final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
    await db.update(
      'plan_items',
      {'date': target.toIso(), 'sort_order': nextOrder},
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> nextSortOrder(String tripId, DateOnly date) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT MAX(sort_order) AS m FROM plan_items WHERE trip_id = ? AND date = ?',
      [tripId, date.toIso()],
    );
    return ((rows.first['m'] as int?) ?? -1) + 1;
  }
}
