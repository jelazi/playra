# TMDB API Setup / Nastavení TMDB API

## English

### What is TMDB?
TMDB (The Movie Database) is a free database that provides information about movies and TV series including titles in multiple languages, posters, ratings, genres, and more.

### How to get an API key:

1. **Register on TMDB**:
   - Go to https://www.themoviedb.org/signup
   - Create a free account

2. **Request API key**:
   - Go to https://www.themoviedb.org/settings/api
   - Click on "Create" or "Request an API Key"
   - Select "Developer"
   - Fill in the required information:
     - Application name: `Titulky.com Desktop App` (or any name)
     - Application URL: You can use `https://github.com/yourusername/titulky_com`
     - Application summary: `Desktop application for downloading subtitles`
   - Accept the terms and submit

3. **Copy your API key**:
   - After approval (usually instant), you'll see your API Key (v3 auth)
   - Copy the entire key

4. **Add the key to the app**:
   - Open file: `lib/services/tmdb_service.dart`
   - Find line 7: `static const String _apiKey = '';`
   - Paste your key between the quotes: `static const String _apiKey = 'your_api_key_here';`
   - Save the file

### Example:
```dart
static const String _apiKey = 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6';
```

---

## Čeština

### Co je TMDB?
TMDB (The Movie Database) je bezplatná databáze, která poskytuje informace o filmech a seriálech včetně názvů v různých jazycích, posterů, hodnocení, žánrů a dalších.

### Jak získat API klíč:

1. **Registrace na TMDB**:
   - Jděte na https://www.themoviedb.org/signup
   - Vytvořte si bezplatný účet

2. **Požádejte o API klíč**:
   - Jděte na https://www.themoviedb.org/settings/api
   - Klikněte na "Create" nebo "Request an API Key"
   - Vyberte "Developer"
   - Vyplňte požadované informace:
     - Název aplikace: `Titulky.com Desktop App` (nebo jakýkoliv název)
     - URL aplikace: Můžete použít `https://github.com/vaseuzivatelskejmeno/titulky_com`
     - Popis aplikace: `Desktopová aplikace pro stahování titulků`
   - Přijměte podmínky a odešlete

3. **Zkopírujte váš API klíč**:
   - Po schválení (obvykle okamžitě) uvidíte váš API Key (v3 auth)
   - Zkopírujte celý klíč

4. **Přidejte klíč do aplikace**:
   - Otevřete soubor: `lib/services/tmdb_service.dart`
   - Najděte řádek 7: `static const String _apiKey = '';`
   - Vložte váš klíč mezi uvozovky: `static const String _apiKey = 'vas_api_klic';`
   - Uložte soubor

### Příklad:
```dart
static const String _apiKey = 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6';
```

---

## Important Notes / Důležité poznámky

- **Free tier limits**: 1,000 requests per day (enough for normal use)
- **Omezení zdarma**: 1 000 požadavků denně (dostačující pro běžné použití)

- The API key is free and you don't need a credit card
- API klíč je zdarma a nepotřebujete kreditní kartu

- Keep your API key private, don't share it publicly
- Uchovejte svůj API klíč v tajnosti, nesdílejte ho veřejně
