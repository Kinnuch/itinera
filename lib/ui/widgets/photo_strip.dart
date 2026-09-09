import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/attachment.dart';
import '../../data/repositories/attachment_repository.dart';

/// 条目图片区：横向缩略图 + 「加图片」按钮。
/// 车票、菜单、房型照片都靠它。
///
/// 选图统一交出 [XFile]，由仓储读字节入库——浏览器里拿不到文件路径，
/// 只有 XFile 这层抽象在三端行为一致。
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({
    super.key,
    required this.attachments,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Attachment> attachments;
  final ValueChanged<List<XFile>> onAdd;
  final ValueChanged<Attachment> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == attachments.length) {
            return _AddButton(
              onPickGallery: () => _pick(context, ImageSource.gallery),
              onPickCamera: () => _pick(context, ImageSource.camera),
            );
          }
          final attachment = attachments[index];
          return _Preview(
            attachment: attachment,
            onRemove: () => onRemove(attachment),
            borderColor: scheme.outlineVariant,
          );
        },
      ),
    );
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    // 选图时就降采样：图片要存进数据库，原图会把库撑爆。
    const maxWidth = AttachmentRepository.maxImageWidth;
    const quality = AttachmentRepository.imageQuality;

    if (source == ImageSource.camera) {
      final shot = await picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        imageQuality: quality,
      );
      if (shot != null) onAdd([shot]);
      return;
    }
    // 相册允许多选：一次把当天的票据都加进来。
    final files = await picker.pickMultiImage(maxWidth: maxWidth, imageQuality: quality);
    if (files.isNotEmpty) onAdd(files);
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPickGallery, required this.onPickCamera});

  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () {
                  Navigator.pop(context);
                  onPickGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                onTap: () {
                  Navigator.pop(context);
                  onPickCamera();
                },
              ),
            ],
          ),
        ),
      ),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text('加图片', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.attachment,
    required this.onRemove,
    required this.borderColor,
  });

  final Attachment attachment;
  final VoidCallback onRemove;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            attachment.bytes,
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            cacheWidth: 276,
            gaplessPlayback: true,
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
