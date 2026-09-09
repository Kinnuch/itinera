import 'dart:typed_data';

export 'file_saver_io.dart' if (dart.library.js_interop) 'file_saver_web.dart';

/// 把一份字节交给用户保存/分享。
///
/// 移动端调系统分享面板（可以直接发微信给同行的人），
/// 浏览器里触发一次下载——桌面浏览器基本都不支持 Web Share 传文件。
/// 具体实现由条件导入在编译期二选一。
typedef SaveBytes = Future<void> Function(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
  String? shareText,
});
