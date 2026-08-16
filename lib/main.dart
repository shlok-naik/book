import 'package:flutter/material.dart';

import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/presentation/pages/root_shell.dart';

void main() {
  runApp(const BookApp());
}

class BookApp extends StatelessWidget {
  const BookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Book',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      scrollBehavior: AppScrollBehavior(),
      home: const RootShell(),
    );
  }
}
