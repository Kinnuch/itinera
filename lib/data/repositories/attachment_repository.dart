import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../services/media/image_store.dart';
import '../db/database.dart';
import '../models/attachment.dart';

class AttachmentRepository {
  AttachmentRepository({AppDatabase? db, ImageStore? store})
      : _db = db ?? AppDatabase.instance,
        _store = store ?? ImageStore();

  final AppDatabase _db;
  final ImageStore _store;
  static const _uuid = Uuid();

  /// 把用户选中的图片复制进应用私有目录后入库，返回记录。
  Future<Attachment> addImage({
    required String itemId,
    required String sourcePath,
    String? caption,
    int sortOrder = 0,
  }) async {
    final relative = await _store.importImage(sourcePath, itemId: itemId);
    final attachment = Attachment(
      id: _uuid.v4(),
      itemId: itemId,
      relativePath: relative,
      kind: AttachmentKind.image,
      caption: caption,
      sortOrder: sortOrder,
    );
    final db = await _db.database;
    await db.insert('attachments', attachment.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return attachment;
  }

  Future<List<Attachment>> ofItem(String itemId) async {
    final db = await _db.database;
    final rows = await db.query(
      'attachments',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(Attachment.fromRow).toList();
  }

  /// 删记录的同时删磁盘文件，否则相册会随行程编辑越攒越大。
  Future<void> remove(Attachment attachment) async {
    final db = await _db.database;
    await db.delete('attachments', where: 'id = ?', whereArgs: [attachment.id]);
    await _store.deleteRelative(attachment.relativePath);
  }
}
