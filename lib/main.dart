import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app.dart';
import 'core/injection_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化依赖注入
  await initDependencies();

  runApp(const BusApp());
}
