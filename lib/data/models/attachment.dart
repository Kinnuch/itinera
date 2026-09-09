import 'dart:typed_data';

/// 条目附件。
///
/// 图片字节直接存进数据库的 BLOB 列，而不是写文件再存路径。
/// 这样 Web / Android / iOS 三端共用同一套代码——浏览器里没有 `dart:io`，
/// 也没有可写的沙盒目录。代价是数据库会变大，所以入库前一律降采样，
/// 见 [AttachmentRepository.maxImageWidth] 与 [AttachmentRepository.imageQuality]。
class Attachment {
  const Attachment({
    required this.id,
    required this.itemId,
    required this.bytes,
    required this.kind,
    this.mimeType = 'image/jpeg',
    this.caption,
    this.sortOrder = 0,
  });

  final String id;
  final String itemId;
  final Uint8List bytes;
  final AttachmentKind kind;
  final String mimeType;
  final String? caption;
  final int sortOrder;

  int get sizeBytes => bytes.lengthInBytes;

  Map<String, Object?> toRow() => {
        'id': id,
        'item_id': itemId,
        'bytes': bytes,
        'kind': kind.name,
        'mime_type': mimeType,
        'caption': caption,
        'sort_order': sortOrder,
      };

  static Attachment fromRow(Map<String, Object?> row) => Attachment(
        id: row['id'] as String,
        itemId: row['item_id'] as String,
        bytes: _toBytes(row['bytes']),
        kind: AttachmentKind.values.firstWhere(
          (e) => e.name == row['kind'],
          orElse: () => AttachmentKind.image,
        ),
        mimeType: row['mime_type'] as String? ?? 'image/jpeg',
        caption: row['caption'] as String?,
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );

  /// sqflite 在不同平台上会把 BLOB 读成 `Uint8List` 或 `List<int>`，统一收口。
  static Uint8List _toBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return Uint8List(0);
  }
}

enum AttachmentKind { image, document }
