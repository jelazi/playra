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
     - Application URL: You can use `https://github.com/yourusername/playra`
     - Application summary: `Desktop application for downloading subtitles`
   - Accept the terms and submit

3. **Copy your API key**:
   - After approval (usually instant), you'll see your API Key (v3 auth)
   - Copy the entire key

4. **Give the key to the app** — do not put it in the source:
   - Just start Playra. On first launch it asks for the key, checks it against TMDB and stores it.
   - You can change or remove it any time under **Settings -> Movie & TV metadata -> TMDB API key**.

For CI or reproducible release builds you can pass it at build time instead. A build-time define
takes precedence over the stored key and hides the Settings field:

### Example:
```bash
flutter run --dart-define=TMDB_API_KEY=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
# or, from a git-ignored file holding {"TMDB_API_KEY": "..."}:
flutter run --dart-define-from-file=env.json
```

`TmdbService` resolves the key in this order: `--dart-define=TMDB_API_KEY`, then the key saved in
Settings. If neither is set, every lookup returns nothing and the app logs `TMDB: no API key`.

### How the stored key is protected

- It lives in `SecretStore` — a Hive box encrypted with AES (`HiveAesCipher`), separate from the
  plaintext settings box.
- The 32-byte encryption key is written to `.playra_secret_key` in the application-support
  directory and chmod-ed to `600` on macOS and Linux, so the Hive file alone is useless.
- The key is never written back into the input field, never included in the LAN-sync snapshot, and
  is stripped from Dio error messages before anything is logged.
- The key is validated (32 hex characters) and verified against TMDB before it is stored.
- A key saved by an older build in the plaintext settings box is migrated into the encrypted box on
  first start and removed from the old location.

This protects the key against a leaked backup, a synced folder or a shared Hive file. It is not a
defence against an attacker who already runs code as your user — for that the key would have to
live in the OS keychain.

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
     - URL aplikace: Můžete použít `https://github.com/vaseuzivatelskejmeno/playra`
     - Popis aplikace: `Desktopová aplikace pro stahování titulků`
   - Přijměte podmínky a odešlete

3. **Zkopírujte váš API klíč**:
   - Po schválení (obvykle okamžitě) uvidíte váš API Key (v3 auth)
   - Zkopírujte celý klíč

4. **Přidejte klíč do aplikace**:
   - Stačí spustit Playru. Při prvním startu se na klíč sama zeptá, ověří ho u TMDB a uloží.
   - Kdykoli ho změníte nebo smažete v **Nastavení -> Metadata filmů a seriálů -> TMDB API klíč**.
   - Pro CI nebo release buildy lze klíč předat i při sestavení; ten má přednost před uloženým.
   - Uložený klíč je v Hive boxu šifrovaném AES; šifrovací klíč leží v samostatném souboru
     `.playra_secret_key` s právy `600`, takže samotný Hive soubor je bez něj nečitelný.

### Příklad:
```bash
flutter run --dart-define=TMDB_API_KEY=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

---

## Important Notes / Důležité poznámky

- **Free tier limits**: 1,000 requests per day (enough for normal use)
- **Omezení zdarma**: 1 000 požadavků denně (dostačující pro běžné použití)

- The API key is free and you don't need a credit card
- API klíč je zdarma a nepotřebujete kreditní kartu

- Keep your API key private, don't share it publicly
- Uchovejte svůj API klíč v tajnosti, nesdílejte ho veřejně
