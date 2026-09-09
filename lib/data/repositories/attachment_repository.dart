import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/attachment.dart';

class AttachmentRepository {
  AttachmentRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// 入库前的降采样参数。图片存在数据库里，不压就会把库撑爆：
  /// 手机原图一张 4–8MB，压到 1600px / 质量 80 之后约 200–400KB，
  /// 对「看清车票和菜单」这个用途完全够用。
  static const double maxImageWidth = 1600;
  static const int imageQuality = 80;

  /// 单张上限。超过就拒绝，避免误选一张超大扫描件把库写坏。
  static const int maxBytes = 4 * 1024 * 1024;

  /// 把 image_picker 选到的文件读成字节入库。
  /// 用 `XFile.readAsBytes()` 而不是 `File(path)`：浏览器里没有 `dart:io`。
  /// 超过 [maxBytes] 返回 null，由调用方提示用户。
  Future<Attachment?> addFromXFile({
    required String itemId,
    required XFile file,
    String? caption,
    int sortOrder = 0,
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > maxBytes) return null;
    return addBytes(
      itemId: itemId,
      bytes: bytes,
      mimeType: file.mimeType ?? _guessMime(file.name),
      caption: caption,
      sortOrder: sortOrder,
    );
  }

  Future<Attachment> addBytes({
    required String itemId,
    required Uint8List bytes,
    String mimeType = 'image/jpeg',
    String? caption,
    int sortOrder = 0,
  }) async {
    final attachment = Attachment(
      id: _uuid.v4(),
      itemId: itemId,
      bytes: bytes,
      kind: AttachmentKind.image,
      mimeType: mimeType,
      caption: caption,
      sortOrder: sortOrder,
    );
    final db = await _db.database;
    await db.insert(
      'attachments',
      attachment.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  Future<void> remove(Attachment attachment) async {
    final db = await _db.database;
    await db.delete('attachments', where: 'id = ?', whereArgs: [attachment.id]);
  }

  /// 条目被删时清掉它的全部附件。外键级联在 sqflite 上要显式开 PRAGMA，
  /// web 端的 wasm 实现行为不完全一致，所以这里主动再删一次。
  Future<void> removeAllOfItem(String itemId) async {
    final db = await _db.database;
    await db.delete('attachments', where: 'item_id = ?', whereArgs: [itemId]);
  }

  /// 全库图片占用，设置页用来提示「图片已占 32 MB」。
  Future<int> totalBytes() async {
    final db = await _db.database;
    final rows = await db.rawQuery('SELECT SUM(LENGTH(bytes)) AS total FROM attachments');
    return ((rows.first['total'] as num?) ?? 0).toInt();
  }

  String _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
