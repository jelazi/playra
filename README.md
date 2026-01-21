# Titulky.com Desktop

Desktopová aplikace pro správu videí a stahování titulků z webu titulky.com s automatickou identifikací filmů a seriálů.

## Funkce

- ✅ **Knihovna videí** s drag & drop podporou
- ✅ **Automatická identifikace** filmů a seriálů z názvu souboru
- ✅ **TMDB integrace** - zobrazení informací o filmech/seriálech v češtině/angličtině
- ✅ **Inteligentní vyhledávání** titulků podle TMDB názvu
- ✅ **Přihlášení** k titulky.com s placením účtem
- ✅ **Testování titulků** v přehrávači před stažením
- ✅ **Kontrola načasování** titulků s videem
- ✅ **Automatické stažení** a přejmenování titulků
- ✅ **Lokalizace** - čeština a angličtina

## Jak to funguje?

1. **Přidejte videa** - přetáhněte soubory nebo použijte tlačítko "Přidat"
2. **Automatická identifikace** - aplikace parsuje název (např. `True.Detective.S01E02.720p.BluRay`)
3. **TMDB vyhledávání** - najde informace o filmu/seriálu v české/anglické databázi
4. **Zobrazení detailů** - poster, hodnocení, žánry, popis
5. **Vyhledání titulků** - automaticky vyhledá titulky podle správného názvu

## Architektura

Aplikace používá čistou architekturu s:

- **BLoC pattern** pro state management
- **Repository pattern** pro API komunikaci
- **Separace concerns** mezi UI, business logikou a daty
- **Lokalizace** s easy_localization
- **Hive** pro lokální úložiště nastavení

### Struktura projektu

```
lib/
├── bloc/
│   ├── subtitle/              # BLoC pro správu titulků
│   │   ├── subtitle_bloc.dart
│   │   ├── subtitle_event.dart
│   │   └── subtitle_state.dart
│   └── video/                 # BLoC pro přehrávání videa
│       ├── video_bloc.dart
│       ├── video_event.dart
│       └── video_state.dart
├── models/
│   ├── video_info.dart        # Model pro informace o videu
│   ├── subtitle.dart          # Model pro titulky
│   ├── media_info.dart        # Model pro TMDB data
│   └── app_settings.dart      # Model pro nastavení
├── repositories/
│   └── titulky_repository.dart # API komunikace s titulky.com
├── services/
│   ├── settings_service.dart  # Správa nastavení (Hive)
│   ├── tmdb_service.dart      # TMDB API integrace
│   └── video_name_parser.dart # Parsování názvů videí
├── screens/
│   ├── video_library_screen.dart      # Knihovna videí (hlavní)
│   ├── video_selection_screen.dart    # Přihlášení
│   ├── subtitle_search_screen.dart    # Seznam nalezených titulků
│   └── video_player_screen.dart       # Přehrávač s titulky
└── main.dart
```

## Použité technologie

- **Flutter** - UI framework
- **flutter_bloc** - State management
- **easy_localization** - Lokalizace (cs/en)
- **hive** - Lokální databáze pro nastavení
- **media_kit** - Video přehrávač s podporou titulků
- **dio** - HTTP klient
- **html** - Web scraping titulky.com
- **file_picker** - Výběr souborů
- **desktop_drop** - Drag & drop support
- **TMDB API** - Databáze filmů a seriálů

## Instalace

### 1. Nainstalujte závislosti
```bash
flutter pub get
```

### 2. Nastavte TMDB API klíč

**Aplikace vyžaduje TMDB API klíč pro identifikaci filmů!**

Přečtěte si detailní návod v souboru [TMDB_SETUP.md](TMDB_SETUP.md)

Rychlý postup:
1. Zaregistrujte se na https://www.themoviedb.org/signup
2. Získejte API klíč na https://www.themoviedb.org/settings/api
3. Vložte klíč do `lib/services/tmdb_service.dart` na řádek 7:
   ```dart
   static const String _apiKey = 'VÁŠ_API_KLÍČ';
   ```

### 3. Spusťte aplikaci
```bash
flutter run -d macos    # Pro macOS
flutter run -d windows  # Pro Windows  
flutter run -d linux    # Pro Linux
```

## Použití

### 1. Přihlášení

- Spusťte aplikaci
- Zadejte své přihlašovací údaje k titulky.com
- Klikněte na "Přihlásit se"

### 2. Přidání videí

**Drag & Drop:**
- Přetáhněte video soubory do pravého panelu

**File picker:**
- Klikněte na "Přidat videa"
- Vyberte jeden nebo více video souborů

### 3. Automatická identifikace

Aplikace automaticky:
- Parsuje název souboru (např. `True.Detective.S01E02.720p.BluRay.mkv`)
- Identifikuje: `True Detective`, sezóna 1, epizoda 2
- Vyhledá v TMDB databázi
- Zobrazí český/anglický název, poster, hodnocení, žánry

### 4. Vyhledání titulků

- Vyberte video ze seznamu
- Prohlédněte si informace z TMDB
- Klikněte na "Vyhledat titulky"
- Aplikace vyhledá titulky podle správného názvu z TMDB

### 5. Testování a stažení

- Prohlédněte si seznam nalezených titulků
- Klikněte na ikonu přehrávání pro testování
- Zkontrolujte načasování
- Klikněte na ikonu stahování pro uložení

### Přepínání jazyků

- Použijte ikonu 🌐 v pravém horním rohu
- Vyberte 🇨🇿 Čeština nebo 🇬🇧 English
- TMDB data se zobrazí v zvoleném jazyce

## Podporované formáty názvů

Aplikace rozpozná tyto formáty:

**Filmy:**
- `The.Matrix.1999.1080p.BluRay.x264.mkv` → The Matrix (1999)
- `Inception 2010 720p.mp4` → Inception (2010)
- `Avatar-2009-IMAX.avi` → Avatar (2009)

**Seriály:**
- `True.Detective.S01E02.720p.BluRay.mkv` → True Detective S01E02
- `Breaking.Bad.S05E16.1080p.WEB-DL.mkv` → Breaking Bad S05E16
- `Game of Thrones - S08E06 - 4K.mkv` → Game of Thrones S08E06

## API Titulky.com

**Poznámka:** Tato aplikace je ukázková implementace. Pro plnou funkčnost je potřeba:

1. Zkontrolovat skutečnou API dokumentaci titulky.com
2. Upravit endpointy v `TitulkyRepository`
3. Implementovat správnou autentizaci (možná OAuth2, API klíč, atd.)
4. Přidat chybějící metody podle skutečného API

### Potřebné úpravy

V souboru `lib/repositories/titulky_repository.dart` upravte:

```dart
final String _baseUrl = 'https://actual-api-url.titulky.com';
```

A aktualizujte metody podle skutečné API dokumentace.

## Požadavky

- Flutter SDK ≥ 3.10.4
- macOS 10.14+, Windows 10+, nebo Linux (Ubuntu 20.04+)
- Placený účet na titulky.com

## Známé problémy

- API endpointy jsou ilustrativní - je potřeba je upravit podle skutečného API
- Dočasné stahování titulků pro testování není plně implementováno
- Chybí podpora pro více jazyků titulků najednou

## Budoucí vylepšení

- [ ] Podpora pro stahování více titulků najednou
- [ ] Historie stažených titulků
- [ ] Automatické synchronizace titulků
- [ ] Podpora pro konverzi formátů titulků
- [ ] Možnost úpravy načasování přímo v aplikaci
- [ ] Batch processing více videí

