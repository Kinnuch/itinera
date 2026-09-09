/// 条目附件。图片按副本存入应用文档目录，DB 只存相对路径，
/// 这样换机/重装后路径仍然有效（绝对路径在 iOS 每次更新都会变）。
class Attachment {
  const Attachment({
    required this.id,
    required this.itemId,
    required this.relativePath,
    required this.kind,
    this.caption,
    this.sortOrder = 0,
  });

  final String id;
  final String itemId;
  final String relativePath;
  final AttachmentKind kind;
  final String? caption;
  final int sortOrder;

  Map<String, Object?> toRow() => {
        'id': id,
        'item_id': itemId,
        'relative_path': relativePath,
        'kind': kind.name,
        'caption': caption,
        'sort_order': sortOrder,
      };

  static Attachment fromRow(Map<String, Object?> row) => Attachment(
        id: row['id'] as String,
        itemId: row['item_id'] as String,
        relativePath: row['relative_path'] as String,
        kind: AttachmentKind.values.firstWhere(
          (e) => e.name == row['kind'],
          orElse: () => AttachmentKind.image,
        ),
        caption: row['caption'] as String?,
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );
}

enum AttachmentKind { image, document }
