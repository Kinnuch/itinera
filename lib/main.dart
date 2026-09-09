import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 日期本地化数据必须在任何 DateFormat('zh_CN') 之前初始化。
  await initializeDateFormatting('zh_CN');
  runApp(const ProviderScope(child: ItineraApp()));
}
