import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'services/export/file_saver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 日期本地化数据必须在任何 DateFormat('zh_CN') 之前初始化。
  await initializeDateFormatting('zh_CN');

  // 浏览器里 IndexedDB 默认是 best-effort 的，磁盘紧张时会被清掉。
  // 尽早申请持久化配额；拿不到也照常运行，只是设置页会如实提示风险。
  await requestPersistentStorage();

  runApp(const ProviderScope(child: ItineraApp()));
}
