import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'state/app_state.dart';
import 'state/layout_state.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // Industry-standard desktop minimum so panels can't be crushed into overflow.
  await windowManager.setMinimumSize(const Size(900, 600));
  // Intercept the close button so the app minimizes to the notification area
  // (system tray) instead of exiting — see HomeShell's window/tray listeners.
  await windowManager.setPreventClose(true);
  // Load all locale date symbols so the Date/Time Locale setting can format.
  await initializeDateFormatting();
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
        ChangeNotifierProvider(create: (_) => SettingsState()..init()),
      ],
      child: Consumer<SettingsState>(
        builder: (context, settings, _) {
          // Keep the static palette in sync, then force a full rebuild of the
          // app subtree on theme change so every widget re-reads AppColors.
          AppColors.apply(settings.palette);
          return MaterialApp(
            title: 'Commit Mint',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.from(settings.palette),
            home: KeyedSubtree(
              key: ValueKey(settings.themeMode),
              child: const HomeShell(),
            ),
          );
        },
      ),
    );
  }
}
