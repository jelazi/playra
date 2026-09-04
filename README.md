# Playra

A cross-platform video player for your own library. Playra scans local folders and SMB shares, works
out what each file actually is, plays it with a proper gesture- and keyboard-driven player, and
handles subtitles end to end — finding them, ranking them, fixing their timing and keeping them next
to the video.

[![CI](https://github.com/jelazi/playra/actions/workflows/ci.yml/badge.svg)](https://github.com/jelazi/playra/actions/workflows/ci.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.44-blue.svg)
![Platform](https://img.shields.io/badge/Platform-iOS%20|%20Android%20|%20macOS%20|%20Windows%20|%20Linux-lightgrey.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Runs on iOS, Android, macOS, Windows and Linux from one codebase.

## Playback

Built on [media_kit](https://pub.dev/packages/media_kit), so it plays what libmpv plays.

- **Resume where you stopped** — playback position is remembered per video
- **Touch gestures** — vertical swipes for brightness and volume, horizontal swipe to seek with
  configurable sensitivity, double-tap to skip by a configurable step
- **Desktop controls** — rebindable keyboard shortcuts for play/pause, fullscreen and seeking, plus
  configurable double-click and mouse-wheel actions (seek, volume or brightness)
- **Track selection** — audio and subtitle tracks per video, falling back to your preferred languages
- **Subtitle styling** — font family and size, text/background/outline colours, outline width, bold
  and distance from the bottom edge
- **Keep-awake** while playing, and a native window on desktop

## Library

- **Local folders** — point Playra at any number of directories and it indexes the videos inside
- **Drag & drop** on desktop, file picker on mobile
- **Three view modes** — structured (mirrors your folders), flat, or smart grouping
- **Three visual modes** — list, small icons, large icons
- **Subtitle indicators** — see at a glance which videos already have subtitles on disk
- **Episode continuation** — after an episode ends, Playra finds the likely next file and offers it

## Network sources

- **SMB shares** — save server connections, browse them in-app and stream straight from a NAS
- **Local streaming proxy** — a small `shelf` HTTP server bridges SMB to the player, with a
  configurable stream cache size, so no full download is needed before playback starts
- **LAN sync** — keep library state consistent across machines on the same network

## Identification

- **Filename parsing** for movies and TV episodes
- **TMDB** for posters, ratings, genres and descriptions in Czech or English
- **Cinemeta** as a second metadata source
- **Translation fallback** for episode metadata TMDB does not localise
- **Video hashing** for precise matching

Recognised formats:

| Filename | Resolved as |
|---|---|
| `The.Matrix.1999.1080p.BluRay.x264.mkv` | The Matrix (1999) |
| `Inception 2010 720p.mp4` | Inception (2010) |
| `Avatar-2009-IMAX.avi` | Avatar (2009) |
| `True.Detective.S01E02.720p.BluRay.mkv` | True Detective S01E02 |
| `Game of Thrones - S08E06 - 4K.mkv` | Game of Thrones S08E06 |

## Subtitles

- **Search on titulky.com** driven by the resolved TMDB title rather than the raw filename
- **Relevance ranking** of candidates against the actual release
- **Preview before committing** — try a subtitle in the player before saving it
- **Multi-disc merge** — CD1/CD2 archives are joined into one file instead of silently keeping half
- **Built-in editor** — shift timing, correct individual entries, export back to SRT
- **Automatic naming** so the file lands next to the video and is picked up on the next scan

A premium titulky.com account is required for downloads.

## Movie acquisition

For titles not in your library, Playra can resolve streams through Torrentio and fetch them via
Real-Debrid or a native torrent client (`auto` picks Real-Debrid on mobile, the torrent client on
desktop). Streams can be filtered by target quality and a minimum seeder count, and on desktop
playback can start while the download is still running.

## Architecture

- **BLoC/Cubit** for state management — eight feature blocs (`library`, `subtitle`,
  `subtitle_editor`, `downloads`, `servers`, `streams`, `movie_search`, `settings`)
- **Service layer** for everything external: TMDB, Cinemeta, SMB, torrent and Real-Debrid clients,
  SRT parsing, filename parsing, hashing, LAN sync
- **Repository** for titulky.com scraping and session handling
- **Hive** for settings and cached metadata
- **easy_localization** for Czech and English

```
lib/
├── bloc/          # downloads, library, movie_search, servers, settings,
│                  # streams, subtitle, subtitle_editor
├── config/
├── models/        # video_info, media_info, subtitle, subtitle_entry,
│                  # player_settings, subtitle_style_settings, server_connection, ...
├── repositories/  # titulky_repository.dart
├── screens/       # playra_player, video_library, subtitle_search, subtitle_editor,
│                  # server_browser, downloads, settings, media_info, ...
├── services/      # tmdb, cinemeta, smb_browser, smb_proxy_server, lan_sync,
│                  # torrent_client, real_debrid, srt_parser, video_name_parser, ...
└── main.dart
```

## Getting started

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Set up a TMDB API key

**The app requires a TMDB API key for movie identification.** Without it every lookup returns no
results and the app logs `TMDB: no API key`.

1. Sign up at https://www.themoviedb.org/signup
2. Get an API key at https://www.themoviedb.org/settings/api
3. Pass it at build time — **never commit it**:

```bash
echo '{"TMDB_API_KEY": "your_key_here"}' > env.json   # env.json is git-ignored
flutter run --dart-define-from-file=env.json
```

The key is read through `String.fromEnvironment('TMDB_API_KEY')`, so it is compiled into the binary
you build and never enters the repository. A one-off run can also take
`--dart-define=TMDB_API_KEY=<key>` inline. Details in [docs/TMDB_SETUP.md](docs/TMDB_SETUP.md).

### 3. Run

```bash
flutter run -d macos --dart-define-from-file=env.json
```

Swap `macos` for `ios`, `android`, `windows` or `linux`. Release builds take the same flag, e.g.
`flutter build macos --dart-define-from-file=env.json`.

## Requirements

- Flutter SDK ≥ 3.10.4
- **iOS** 11.0+ · **Android** 5.0+ (API 21+) · **macOS** 10.14+ · **Windows** 10+ · **Linux** Ubuntu 20.04+
- TMDB API key (free)
- Premium titulky.com account, for subtitle downloads only

## Development

```bash
flutter analyze
flutter test
```

Both run in CI on every push and pull request against `main`.

## License

Released under the [MIT License](LICENSE).
