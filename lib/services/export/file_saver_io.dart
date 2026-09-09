import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 移动端/桌面端：先落到临时目录，再交给系统分享面板。
Future<void> saveBytes(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
  String? shareText,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path, mimeType: mimeType)], text: shareText);
}

/// 只有浏览器需要申请持久化存储，这里是空实现。
Future<bool> requestPersistentStorage() async => true;

/// 移动端的数据存在应用沙盒里，不会被系统随手清掉。
bool get storageIsEvictable => false;
