# Playra

Cross-platform Flutter video player with integrated subtitle management. Playra indexes a local or
network video library, identifies what each file is, plays it back, and finds, edits and synchronises
matching subtitles — without leaving the app.

[![CI](https://github.com/jelazi/playra/actions/workflows/ci.yml/badge.svg)](https://github.com/jelazi/playra/actions/workflows/ci.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.44-blue.svg)
![Platform](https://img.shields.io/badge/Platform-iOS%20|%20Android%20|%20macOS%20|%20Windows%20|%20Linux-lightgrey.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

### Library and playback
- ✅ **Video library** with drag & drop (desktop) and file picker (mobile)
- ✅ **Built-in player** with subtitle rendering and per-track selection
- ✅ **Episode continuation** — finds the likely next episode of a series and offers to play it
- ✅ **SMB network shares** — browse and stream from a NAS through a local HTTP proxy
- ✅ **LAN sync** — keep library state in step across machines on the same network

### Identification
- ✅ **Filename parsing** of movies and TV episodes (e.g. `True.Detective.S01E02.720p.BluRay`)
- ✅ **TMDB integration** — posters, ratings, genres and descriptions in Czech or English
- ✅ **Cinemeta lookup** as an additional metadata source
- ✅ **Translation fallback** for episode metadata TMDB does not localise

### Subtitles
- ✅ **Search on titulky.com** driven by the resolved TMDB title, with premium account login
- ✅ **Relevance ranking** of candidate subtitles against the actual video file
- ✅ **Preview in the player** before committing to a download
- ✅ **Subtitle editor** with timing offset correction and SRT re-export
- ✅ **Automatic download and renaming** to match the video file

### General
- ✅ **Localization** — Czech and English
- ✅ **Cross-platform** — iOS, Android, macOS, Windows, Linux

## How it works?

1. **Add videos** - drag & drop files (desktop) or use file picker (mobile)
2. **Automatic identification** - app parses filename (e.g. `True.Detective.S01E02.720p.BluRay`)
3. **TMDB search** - finds movie/TV information in Czech/English database
4. **Display details** - poster, rating, genres, description
5. **Subtitle search** - automatically searches subtitles using correct TMDB title

## Platforms

This app runs on multiple platforms:

- **iOS** - iPhone and iPad with Files app integration
- **Android** - Phone and tablet with document picker
- **macOS** - Desktop with drag & drop and file picker
- **Windows** - Desktop with drag & drop and file picker
- **Linux** - Desktop with drag & drop and file picker

## Architecture

The app uses clean architecture with:

- **BLoC pattern** for state management
- **Repository pattern** for API communication
- **Separation of concerns** between UI, business logic and data
- **Localization** with easy_localization
- **Hive** for local settings storage

### Project Structure

```
lib/
├── bloc/
│   ├── subtitle/              # BLoC for subtitle management
│   │   ├── subtitle_bloc.dart
│   │   ├── subtitle_event.dart
│   │   └── subtitle_state.dart
│   └── video/                 # BLoC for video playback
│       ├── video_bloc.dart
│       ├── video_event.dart
│       └── video_state.dart
├── models/
│   ├── video_info.dart        # Model for video information
│   ├── subtitle.dart          # Model for subtitles
│   ├── media_info.dart        # Model for TMDB data
│   └── app_settings.dart      # Model for app settings
├── repositories/
│   └── titulky_repository.dart # API communication with titulky.com
├── services/
│   ├── settings_service.dart  # Settings management (Hive)
│   ├── tmdb_service.dart      # TMDB API integration
│   └── video_name_parser.dart # Video filename parsing
├── screens/
│   ├── video_library_screen.dart      # Video library (main)
│   ├── video_selection_screen.dart    # Login screen
│   ├── subtitle_search_screen.dart    # Found subtitles list
│   └── video_player_screen.dart       # Video player with subtitles
└── main.dart
```

## Technologies Used

- **Flutter** - UI framework
- **flutter_bloc** - State management
- **easy_localization** - Localization (cs/en)
- **hive** - Local database for settings
- **media_kit** - Video player with subtitle support
- **dio** - HTTP client
- **html** - Web scraping for titulky.com
- **file_picker** - File selection
- **desktop_drop** - Drag & drop support
- **TMDB API** - Movies and TV series database

## Installation

### 1. Install dependencies
```bash
flutter pub get
```

### 2. Set up TMDB API key

**The app requires a TMDB API key for movie identification!**

Read the detailed guide in [docs/TMDB_SETUP.md](docs/TMDB_SETUP.md)

Quick setup:
1. Sign up at https://www.themoviedb.org/signup
2. Get API key at https://www.themoviedb.org/settings/api
3. Insert the key into `lib/services/tmdb_service.dart` at line 7:
   ```dart
   static const String _apiKey = 'YOUR_API_KEY';
   ```

### 3. Run the application

**iOS:**
```bash
flutter run -d ios
```

**Android:**
```bash
flutter run -d android
```

**macOS:**
```bash
flutter run -d macos
```

**Windows:**
```bash
flutter run -d windows
```

**Linux:**
```bash
flutter run -d linux

## Usage

### 1. Login

- Launch the application
- Enter your titulky.com login credentials
- Click "Login"

### 2. Adding Videos

**Desktop (macOS, Windows, Linux):**
- Drag video files into the right panel
- Or click "Add Videos" and select files

**Mobile (iOS, Android):**
- Click "Add Videos"
- Use file picker to select video files
- On iOS: Files app supports iCloud Drive, SMB servers, etc.
- On Android: Document picker supports local storage, cloud drives

### 3. Automatic Identification

The app automatically:
- Parses filename (e.g. `True.Detective.S01E02.720p.BluRay.mkv`)
- Identifies: `True Detective`, season 1, episode 2
- Searches TMDB database
- Displays Czech/English title, poster, rating, genres

### 3. Automatic Identification

The app automatically:
- Parses filename (e.g. `True.Detective.S01E02.720p.BluRay.mkv`)
- Identifies: `True Detective`, season 1, episode 2
- Searches TMDB database
- Displays Czech/English title, poster, rating, genres

### 4. Subtitle Search

- Select video from the list
- Review TMDB information
- Click "Search Subtitles"
- App searches subtitles using correct TMDB title

### 5. Testing and Download

- Review found subtitles list
- Click play icon for testing
- Check timing
- Click download icon to save

### Language Switching

- Use 🌐 icon in top right corner
- Select 🇨🇿 Czech or 🇬🇧 English
- TMDB data displays in selected language

## Supported Filename Formats

The app recognizes these formats:

**Movies:**
- `The.Matrix.1999.1080p.BluRay.x264.mkv` → The Matrix (1999)
- `Inception 2010 720p.mp4` → Inception (2010)
- `Avatar-2009-IMAX.avi` → Avatar (2009)

**TV Series:**
- `True.Detective.S01E02.720p.BluRay.mkv` → True Detective S01E02
- `Breaking.Bad.S05E16.1080p.WEB-DL.mkv` → Breaking Bad S05E16
- `Game of Thrones - S08E06 - 4K.mkv` → Game of Thrones S08E06

## License

Released under the [MIT License](LICENSE).

## Titulky.com API

**Note:** This app is a demonstration implementation. For full functionality you need:

1. Check actual titulky.com API documentation
2. Update endpoints in `TitulkyRepository`
3. Implement proper authentication (possibly OAuth2, API key, etc.)
4. Add missing methods according to real API

### Required Modifications

In `lib/repositories/titulky_repository.dart` update:

```dart
final String _baseUrl = 'https://actual-api-url.titulky.com';
```

And update methods according to real API documentation.

## Requirements

- Flutter SDK ≥ 3.10.4
- **iOS:** iOS 11.0+ with Xcode
- **Android:** Android 5.0+ (API 21+) with Android Studio
- **macOS:** macOS 10.14+ with Xcode
- **Windows:** Windows 10+ with Visual Studio
- **Linux:** Ubuntu 20.04+ or similar
- Premium account on titulky.com

## Known Issues

- API endpoints are illustrative - need to be updated according to real API
- Temporary subtitle download for testing is not fully implemented
- Missing support for multiple subtitle languages at once

## Future Improvements

- [ ] Support for downloading multiple subtitles at once
- [ ] History of downloaded subtitles
- [ ] Automatic subtitle synchronization
- [ ] Support for subtitle format conversion
- [ ] Ability to edit timing directly in the app
- [ ] Batch processing of multiple videos

