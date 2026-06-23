import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'state/app_state.dart';
import 'state/layout_state.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  runApp(const CommitMintApp());
}

class CommitMintApp extends StatelessWidget {
  const CommitMintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..init()),
        ChangeNotifierProvider(create: (_) => LayoutState()),
      ],
      child: MaterialApp(
        title: 'Commit Mint',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const HomeShell(),
      ),
    );
  }
}
