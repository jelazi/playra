import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';

import 'bloc/subtitle/subtitle_bloc.dart';
import 'repositories/titulky_repository.dart';
import 'screens/video_library_screen.dart';
import 'services/media_cache_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Media Kit for video playback
  MediaKit.ensureInitialized();

  // Initialize Hive for settings storage
  await SettingsService.init();

  // Inicializace Media Cache
  await MediaCacheService.init();

  // Inicializace lokalizace
  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('cs'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('cs'),
      startLocale: Locale(SettingsService.getSettings().language ?? 'cs'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [RepositoryProvider(create: (context) => TitulkyRepository())],
      child: BlocProvider(
        create: (context) => SubtitleBloc(repository: context.read<TitulkyRepository>()),
        child: MaterialApp(
          title: 'app.title'.tr(),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
          home: const VideoLibraryScreen(),
        ),
      ),
    );
  }
}
