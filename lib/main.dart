import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'pages/home_page.dart';
import 'widgets/hidden_engine.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const YuanbaoApp(),
    ),
  );
}

class YuanbaoApp extends StatelessWidget {
  const YuanbaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: '豆包助手',
      debugShowCheckedModeBanner: false,
      themeMode: state.themeMode,
      theme: AppTheme.light(ThemeData.light().textTheme),
      darkTheme: AppTheme.dark(ThemeData.dark().textTheme),
      home: const AppScaffold(),
    );
  }
}

/// 顶层：把隐藏的本地引擎 WebView 挂载到最底层，保证全 App 生命周期可用
class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        HomePage(),
        HiddenEngine(),
      ],
    );
  }
}
