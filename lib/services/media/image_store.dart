import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 图片落盘管理。
///
/// 只存相对路径入库：iOS 每次升级都会换掉沙盒容器的绝对路径，
/// 存绝对路径的相册在版本更新后会集体变白。
class ImageStore {
  static const _uuid = Uuid();
  static const _folder = 'attachments';

  Directory? _root;

  Future<Directory> _rootDir() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _root = dir;
  }

  /// 解析成当前进程下可用的绝对路径。
  Future<String> absolutePath(String relativePath) async {
    final dir = await _rootDir();
    return p.join(dir.path, relativePath);
  }

  Future<File?> resolve(String relativePath) async {
    final file = File(await absolutePath(relativePath));
    return await file.exists() ? file : null;
  }

  /// 把相册/相机来的文件复制进沙盒，返回相对路径。
  /// 复制而非引用原路径：image_picker 在 iOS 给的是临时缓存文件，系统随时会清。
  Future<String> importImage(String sourcePath, {required String itemId}) async {
    final dir = await _rootDir();
    final itemDir = Directory(p.join(dir.path, itemId));
    if (!await itemDir.exists()) {
      await itemDir.create(recursive: true);
    }
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final fileName = '${_uuid.v4()}$ext';
    await File(sourcePath).copy(p.join(itemDir.path, fileName));
    return p.join(itemId, fileName);
  }

  Future<void> deleteRelative(String relativePath) async {
    final file = File(await absolutePath(relativePath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 删除条目时清掉它的整个图片目录。
  Future<void> deleteItemFolder(String itemId) async {
    final dir = await _rootDir();
    final itemDir = Directory(p.join(dir.path, itemId));
    if (await itemDir.exists()) {
      await itemDir.delete(recursive: true);
    }
  }
}
