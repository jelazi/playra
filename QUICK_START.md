# Rychlý start / Quick Start

## 🇨🇿 Česky

### 1. Nastavení TMDB API klíče (povinné!)

**Aplikace bez TMDB API klíče nebude fungovat správně!**

1. Jděte na https://www.themoviedb.org/signup a zaregistrujte se (zdarma)
2. Přejděte na https://www.themoviedb.org/settings/api
3. Klikněte na "Create" a vyberte "Developer"
4. Vyplňte formulář (můžete použít libovolné údaje)
5. Zkopírujte API Key (v3 auth)
6. Otevřete soubor `lib/services/tmdb_service.dart`
7. Na řádku 7 vložte váš klíč:
   ```dart
   static const String _apiKey = 'VÁŠ_API_KLÍČ_ZDE';
   ```
8. Uložte soubor

Detailní návod: [TMDB_SETUP.md](TMDB_SETUP.md)

### 2. Spuštění aplikace

```bash
flutter run -d macos
```

### 3. První použití

1. **Přihlášení**: Zadejte své přihlašovací údaje k titulky.com
2. **Přidání videí**: 
   - Přetáhněte video soubory do pravého panelu
   - Nebo klikněte na "Přidat videa"
3. **Automatická identifikace**: Aplikace parsuje název a vyhledá film/seriál v TMDB
4. **Zobrazení informací**: Uvidíte poster, hodnocení, žánry, popis
5. **Vyhledání titulků**: Klikněte na "Vyhledat titulky"
6. **Testování**: Klikněte na ikonu přehrávání u titulků
7. **Stažení**: Klikněte na ikonu stahování

### Tipy

- 🌐 Změňte jazyk ikonou v pravém horním rohu
- 🎬 Podporované názvy: `Film.2024.1080p.mkv` nebo `Serial.S01E02.720p.mkv`
- 🔄 Pro aktualizaci info klikněte na "Hledat znovu"
- 🚪 Logout ikonou v pravém horním rohu

---

## 🇬🇧 English

### 1. TMDB API Key Setup (required!)

**The app won't work properly without TMDB API key!**

1. Go to https://www.themoviedb.org/signup and register (free)
2. Visit https://www.themoviedb.org/settings/api
3. Click "Create" and select "Developer"
4. Fill in the form (you can use any data)
5. Copy the API Key (v3 auth)
6. Open file `lib/services/tmdb_service.dart`
7. On line 7, paste your key:
   ```dart
   static const String _apiKey = 'YOUR_API_KEY_HERE';
   ```
8. Save the file

Detailed guide: [TMDB_SETUP.md](TMDB_SETUP.md)

### 2. Running the app

```bash
flutter run -d macos
```

### 3. First use

1. **Login**: Enter your titulky.com credentials
2. **Add videos**: 
   - Drag and drop video files to the right panel
   - Or click "Add Videos"
3. **Auto identification**: App parses filename and searches TMDB
4. **Show info**: See poster, rating, genres, description
5. **Search subtitles**: Click "Search Subtitles"
6. **Test**: Click play icon on subtitles
7. **Download**: Click download icon

### Tips

- 🌐 Change language with icon in top-right corner
- 🎬 Supported names: `Movie.2024.1080p.mkv` or `Series.S01E02.720p.mkv`
- 🔄 To refresh info click "Search Again"
- 🚪 Logout with icon in top-right corner

---

## Příklady názvů souborů / Filename Examples

✅ **Funguje / Works:**
- `The.Matrix.1999.1080p.BluRay.x264.mkv`
- `True Detective S01E02.mkv`
- `Inception.2010.720p.WEB-DL.mkv`
- `Breaking.Bad.S05E16.1080p.mkv`

❌ **Nefunguje / Doesn't work:**
- `video.mkv` (chybí název / missing title)
- `můj_film_2024.avi` (diakritika / diacritics)
- Používejte anglické názvy bez diakritiky / Use English names without diacritics
