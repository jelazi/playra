import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';

import 'bloc/library/library_cubit.dart';
import 'bloc/servers/servers_cubit.dart';
import 'bloc/settings/playra_settings_cubit.dart';
import 'bloc/subtitle/subtitle_bloc.dart';
import 'repositories/titulky_repository.dart';
import 'screens/home_screen.dart';
import 'screens/player_launcher.dart';
import 'services/library_service.dart';
import 'services/media_cache_service.dart';
import 'services/playra_storage.dart';
import 'services/settings_service.dart';
import 'services/smb_browser_service.dart';
import 'services/smb_proxy_server.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();

  // Initialise Hive (legacy + new boxes)
  await Hive.initFlutter();
  await SettingsService.init();
  await MediaCacheService.init();
  await PlayraStorage.init();

  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('cs'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('cs'),
      startLocale: Locale(SettingsService.getSettings().language ?? 'cs'),
      child: const PlayraApp(),
    ),
  );
}

class PlayraApp extends StatelessWidget {
  const PlayraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final smbBrowser = SmbBrowserService();
    final smbProxy = SmbProxyServer(smbBrowser);
    final libraryService = LibraryService();

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => TitulkyRepository()),
        RepositoryProvider<SmbBrowserService>.value(value: smbBrowser),
        RepositoryProvider<SmbProxyServer>.value(value: smbProxy),
        RepositoryProvider<PlayerLauncher>.value(value: PlayerLauncher(smbBrowser, smbProxy)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlayraSettingsCubit()),
          BlocProvider(create: (_) => LibraryCubit(libraryService)),
          BlocProvider(create: (_) => ServersCubit()),
          BlocProvider(create: (ctx) => SubtitleBloc(repository: ctx.read<TitulkyRepository>())),
        ],
        child: MaterialApp(
          title: 'app.title'.tr(),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo), useMaterial3: true),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: ThemeMode.system,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
