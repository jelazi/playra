# Titulky.com Desktop - Průvodce

## 📁 Struktura projektu

```
lib/
├── bloc/                          # BLoC pattern - oddělené složky
│   ├── video/                     # Video přehrávač BLoC
│   │   ├── video_bloc.dart       # Hlavní BLoC třída
│   │   ├── video_event.dart      # Events
│   │   └── video_state.dart      # States
│   └── subtitle/                  # Titulky BLoC
│       ├── subtitle_bloc.dart    # Hlavní BLoC třída
│       ├── subtitle_event.dart   # Events
│       └── subtitle_state.dart   # States
├── models/                        # Data modely
│   ├── app_settings.dart         # Nastavení aplikace (Hive)
│   ├── subtitle.dart             # Model titulků
│   └── video_info.dart           # Model videa
├── repositories/                  # API komunikace
│   └── titulky_repository.dart   # Titulky.com API
├── screens/                       # UI obrazovky
│   ├── video_selection_screen.dart
│   ├── subtitle_search_screen.dart
│   └── video_player_screen.dart
├── services/                      # Služby
│   └── settings_service.dart     # Hive settings
└── main.dart                      # Entry point

assets/
└── translations/                  # Lokalizace
    ├── cs.json                    # Čeština
    └── en.json                    # Angličtina
```

## 🌍 Lokalizace

Aplikace podporuje češtinu (cs) a angličtinu (en).

### Použití v kódu:

```dart
// Jednoduchý překlad
Text('auth.login_button'.tr())

// Překlad s parametry
Text('subtitle.uploader'.tr(args: [subtitle.uploader]))
```

### Přidání nového textu:

1. Přidejte klíč do `assets/translations/cs.json`
2. Přidejte klíč do `assets/translations/en.json`
3. Použijte v kódu: `'váš.klíč'.tr()`

## 💾 Ukládání nastavení (Hive)

```dart
// Inicializace (už provedeno v main.dart)
await SettingsService.init();

// Získání nastavení
final settings = SettingsService.getSettings();

// Uložení nastavení
await SettingsService.saveSettings(settings);

// Aktualizace konkrétní hodnoty
await SettingsService.updateLanguage('en');
await SettingsService.updateUsername('user@example.com');
```

## 🏗️ BLoC Architektura

### Video BLoC

**Events:**
- `LoadVideo` - Načtení videa
- `PlayVideo` - Přehrání
- `PauseVideo` - Pozastavení
- `SeekVideo` - Přetočení
- `SetSubtitle` - Nastavení titulků
- `DisposeVideo` - Uvolnění

**States:**
- `VideoInitial` - Počáteční stav
- `VideoLoading` - Načítání
- `VideoLoaded` - Načteno
- `VideoError` - Chyba

### Subtitle BLoC

**Events:**
- `LoginToTitulky` - Přihlášení
- `SearchSubtitles` - Vyhledání titulků
- `SelectSubtitle` - Výběr titulků
- `DownloadSubtitle` - Stažení
- `LogoutFromTitulky` - Odhlášení

**States:**
- `SubtitleInitial` - Nepřihlášen
- `SubtitleLoggingIn` - Přihlašování
- `SubtitleLoggedIn` - Přihlášen
- `SubtitleLoginFailed` - Chyba přihlášení
- `SubtitleSearching` - Vyhledávání
- `SubtitleSearchResults` - Výsledky
- `SubtitleDownloading` - Stahování
- `SubtitleDownloaded` - Staženo
- `SubtitleError` - Chyba

## 🔧 Generování kódu

Pro generování Hive adaptéru:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## 🚀 Spuštění

```bash
# macOS
flutter run -d macos

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

## 📦 Použité balíčky

- **flutter_bloc**: State management
- **easy_localization**: Lokalizace
- **hive_flutter**: Lokální databáze
- **media_kit**: Video přehrávač
- **dio**: HTTP klient
- **file_picker**: Výběr souborů

## 🎨 Přidání nového jazyka

1. Vytvořte `assets/translations/XX.json` (XX = kód jazyka)
2. Aktualizujte `main.dart`:
```dart
EasyLocalization(
  supportedLocales: const [Locale('cs'), Locale('en'), Locale('XX')],
  ...
)
```

## ⚙️ Nastavení aplikace

Nastavení se automaticky ukládají do Hive databáze:
- Username
- Session cookie
- Jazyk
- Poslední cesta k videu

## 🐛 Debug

Pro zobrazení debug informací v konzoli:
- Hive box obsah
- API požadavky (Dio)
- BLoC transitions

## 📝 Poznámky

- API endpointy v `TitulkyRepository` jsou ilustrativní
- Před použitím upravte podle skutečného API titulky.com
- Dočasné stahování titulků pro testování lze rozšířit
