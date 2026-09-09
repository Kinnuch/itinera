import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 浏览器：构造 Blob 后用一个隐藏的 <a download> 触发下载。
///
/// 不用 Web Share API：桌面 Chrome/Firefox 都不支持 `navigator.share` 传文件，
/// 下载是唯一在各浏览器上都能用的路径。
Future<void> saveBytes(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
  String? shareText,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor as JSAny);
  anchor.click();
  anchor.remove();
  // 不撤销的话这个 blob 会一直占着内存直到页面关闭。
  web.URL.revokeObjectURL(url);
}

/// 申请持久化存储配额。
///
/// 默认的 IndexedDB 是「best-effort」的：磁盘紧张时浏览器可以直接清掉。
/// 拿到 persistent 授权后，只有用户主动清除网站数据才会丢。
/// 已安装成 PWA 的站点通常会被直接批准，普通标签页则看浏览器的启发式判断。
Future<bool> requestPersistentStorage() async {
  try {
    final manager = web.window.navigator.storage;
    final already = await manager.persisted().toDart;
    if (already.toDart) return true;
    final granted = await manager.persist().toDart;
    return granted.toDart;
  } catch (_) {
    return false;
  }
}

/// 浏览器里的数据原则上都可能被清掉，界面要如实告诉用户。
bool get storageIsEvictable => true;
