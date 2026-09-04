# DEVLOG - Playra

> Persistent development context log for Playra. Newest entries first.

## 2026-09-04 (part 8) — fix: repair the failing CI and extend it with format, coverage and a build job

### What was fixed

- **CI had been red since the SecretStore commit, and it was my bug.**
  `test/secret_store_test.dart` checked the key file permissions with
  `stat -f '%Lp'`, which is BSD/macOS syntax. On the Linux runner `-f` means "file system status",
  so the test compared `'600'` against `File: "/tmp/..."`. It passed locally on macOS and failed on
  every push. Replaced with `(await keyFile.stat()).mode & 0x1FF`, rendered as octal — no
  subprocess, and identical on both platforms.

### What was done

- **Formatting gate.** `dart format --output=none --set-exit-if-changed .` added to CI. This was
  not free: the codebase is hand-formatted, and 73 of 83 files differed from the 80-column
  default. `analysis_options.yaml` now pins `formatter: page_width: 160`, which matches the
  existing style (p99 line length is 146) and cuts the churn to 50 files; the repo was then
  formatted once. The change is whitespace and wrapping only — analyze stayed clean and all 146
  tests still pass.
- **Coverage.** `flutter test --coverage` plus `codecov/codecov-action@v5`, with
  `fail_ci_if_error: false` so a Codecov outage can never fail the build. Codecov badge added to
  the README next to the CI badge.
- **Build job.** A second job on `ubuntu-latest` running `flutter build apk --debug`, with
  `actions/setup-java@v4` (temurin 17, matching `android/app/build.gradle.kts`). It deliberately
  passes no TMDB key, so the job also proves the app builds without one.
- The Flutter version is now a single `FLUTTER_VERSION` env var instead of being repeated per job.

### Current state

- `dart format --set-exit-if-changed`: passes. `flutter analyze`: no issues.
  `flutter test --coverage`: 146/146, `coverage/lcov.info` written (23 KB).
- `flutter build apk --debug` verified locally (335 s) before adding it to CI, rather than
  assuming the Android job would work.

### Pending / next steps

- Codecov: the badge stays "unknown" until the first upload lands. Tokenless upload works for
  public repos but is rate-limited; adding a `CODECOV_TOKEN` repository secret makes it reliable.
  The workflow already reads it and tolerates its absence.
- The one-time reformat is a large, mechanical diff. It is worth committing on its own and listing
  in a `.git-blame-ignore-revs` file so `git blame` skips it.
- Still open: tagging a release with attached artifacts, the repo social preview image, and the
  `Blade.Runner.2049.2017` year-parsing bug from part 6.

## 2026-09-04 (part 7) — refactor: extract a shared widget layer and split the god screens into directories

### What was done

**New `lib/widgets/` — generic, feature-agnostic widgets**

- `subtitle_style_controls.dart` — `SubtitleStyleControls`, the whole subtitle appearance block
  (enabled, size, bottom padding, outline, bold, font, three colour tiles). It had existed twice:
  once in `settings_screen` and once again, with hardcoded white text, in the player sheet.
  The two copies differed only in colour, so the widget now takes its colours from the ambient
  `Theme` and the player wraps it in a dark one. `leading`/`trailing` slots carry the rows that
  belong to only one surface (subtitle delay, subtitle manager).
- `color_picker_tile.dart` — `ColorPickerTile` plus `kColorPalette` /
  `kColorPaletteWithTransparent`, replacing `_colorTile` (settings) and `_colourTile` (player).
- `poster_image.dart` — `PosterImage.file` / `PosterImage.network`, one fallback and one
  decode-size policy for what were seven separate `Image.file`/`Image.network` blocks across
  `home_screen`, `video_library_screen` and `media_info_screen`.
- `empty_state.dart`, `section_header.dart` (+ `SectionSeparator`), `progress_pie.dart`,
  `labelled_value.dart` — the remaining copy-pasted helpers.
- `tmdb_key_dialog.dart` moved here from `screens/widgets/`, since home and settings both use it.

**Screens split into feature directories**

- `screens/player/` — `playra_player_screen.dart`, `track_keys.dart` (the stable audio/subtitle
  key helpers, previously private top-level functions), `widgets/subtitle_options_sheet.dart`.
- `screens/home/` — `home_screen.dart`, `library_entry.dart` (`LibraryEntry`, `StructuredEntry`),
  `widgets/recent_card.dart`.
- `screens/library/` — `video_library_screen.dart`, `widgets/video_detail_screen.dart`.

**Composition over inheritance**

No widget subclasses another. Reuse is by composition and by `Theme` inheritance, which is the
mechanism Flutter actually provides for "same widget, different surface" — the alternative
(a base class with colour hooks) would have hardcoded a palette into the shared layer.

### What was fixed

- Line counts: player 2043 -> 1722, home 1825 -> 1637, library 1541 -> 1347, settings 690 -> 585.
  The subtitle sheet itself went from 305 lines to 211 once its duplicated controls were gone.
- Settings' text and outline colour pickers previously offered a half-transparent black swatch
  that the player's did not; both now use the same palette, with transparency offered only for
  the background colour.

### What broke and was fixed during the work

- Building the player's dark overlay with `Theme.of(context).copyWith(brightness: dark)` kept the
  light theme's typography, so the sheet's section headers rendered near-black on near-black.
  Caught by looking at the running app, not by the analyzer. Fixed by constructing a fresh
  `ThemeData(brightness: Brightness.dark, ...)`.

### Current state

- `flutter analyze`: no issues found. `flutter test`: 146/146 passing.
- `flutter build bundle` and `flutter build macos --debug`: both succeed.
- Verified in the running macOS app against the real library, not just compiled: settings subtitle
  block (all controls, current colours correct), the player sheet after the theme fix, the
  structured library list (parent link, folders, `ProgressPie`, posters), the recents strip
  (`RecentCard`), media info and the downloads screen.

### Pending / next steps

- `playra_storage.dart` (1285 lines) is untouched — it is a single storage class, not a widget
  tree, so splitting it is a different job (per-domain stores) and was out of scope here.
- The three screens are smaller but still large; further extraction (player top/bottom bars, the
  home library list builders) needs those `State` methods to stop reaching into shared mutable
  state first.
- Still open from the review: `dart format --set-exit-if-changed` and a build job in CI, coverage
  reporting, tagging a release, the repo social preview image, and the `Blade.Runner.2049.2017`
  year-parsing bug from part 6.

## 2026-09-04 (part 6) — docs: add README screenshots captured from the running macOS app

### What was done

- **`screenshots/`** — six captures from the real macOS build (1.3 MB total, metadata stripped):
  `library.png`, `player.png`, `subtitle-search.png`, `subtitle-editor.png`, `media-info.png`,
  `settings.png`.
- **README** — a hero library shot plus a 2x2 table under the badges, each cell captioned, with a
  note that the demo library is generated and a TMDB attribution line in the License section
  (required now that TMDB posters are displayed).
- **Capture rig** (all in the scratchpad, nothing installed on the machine): 11 demo videos built
  from PIL title cards and encoded with ffmpeg; `.srt` sidecars; a Swift `click`/`scroll` helper
  posting CGEvents, because Flutter windows expose no accessibility tree and AppleScript
  `click at` does nothing on them; window placement and bounds via System Events; capture via
  `screencapture -R`.
- **Demo state was seeded through Hive** rather than by driving the folder picker: library folder,
  `iconsLarge` view mode, a `Home NAS` SMB server entry, TMDB media-cache mappings and poster
  images fetched into the app's own `poster_cache`.

### What was fixed

- `IMAX` was already added to the release-token lists in part 5; capturing surfaced a second case
  of the same class: `Blade.Runner.2049.2017` parses as title "Blade Runner" with year **2049**,
  because `_extractYear` takes `firstMatch` and 2049 matches `(19|20)\d{2}`. The TMDB lookup then
  returns nothing. Not fixed — the demo file was swapped for `Tenet.2020` instead, so the bug is
  still open and reported to the user.

### Design decisions

- **Generated demo library, not the real one.** The user's actual library would have put their
  personal media titles into a public README. Films are represented by generated colour cards
  carrying the title, so no copyrighted frame is published either.
- **Live Hive data was moved aside and restored.** `~/Documents/playra_*.hive` plus `media_cache`
  hold the user's real state; they were copied to a backup, renamed `.claudebak`, and restored
  afterwards (sizes and mtimes verified identical). `settings.hive` was deliberately left in place
  so the saved titulky.com login kept working. Demo posters added to `poster_cache` were removed
  by diffing against the backup.
- **The titulky.com password was never read.** A check printed only `HAS_USERNAME` / `HAS_PASSWORD`
  booleans; the search screenshot then used the app's own auto-login.

### Current state

- `flutter analyze`: no issues found. `flutter test`: 146/146 passing.
- Every screenshot was reviewed before being kept; the early ones were rejected (empty library,
  hidden controls, missing subtitle, wrong tile) and recaptured.
- The 256 KB `LibraryService._minVideoBytes` floor silently dropped the first batch of demo files;
  they were re-encoded with CBR padding to clear it.
- `~/Movies/Playra Demo Library` was deleted after capture.

### Pending / next steps

- The parser bug above (`Title YYYY` where the title itself ends in a year-like number).
- Still open from the review: splitting the large screen files, `dart format --set-exit-if-changed`
  and a build job in CI, coverage reporting, tagging a release, and the repo's social preview image.

## 2026-09-04 (part 5) — chore: translate remaining Czech comments and cover parsers and blocs with tests

### What was done

**Comments (all of `lib/` is now English)**

- Translated 129 Czech comment lines across 12 files: 119 leading `//` / `///` comments and 10
  trailing ones. Heaviest files were `video_library_screen.dart` (40), `titulky_repository.dart`
  (26) and `subtitle_relevance_service.dart` (24), plus `tmdb_service`, `media_cache_service`,
  `video_name_parser`, `media_cache`, `media_info`, `app_settings`, `video_selection_screen` and
  `video_player_screen`.
- Four comments still contain Czech and deliberately stay that way: they are English comments
  quoting the literal strings matched in titulky.com HTML ("Odhlásit", "denní limit",
  "Alternativní titulky").
- The first sweep only matched comments at the start of a line, which missed 10 trailing ones
  (`relevance += 60; // Max 60 bodů…`). Both forms are now covered by the verification script.

**Tests: 37 -> 146**

- `test/video_name_parser_test.dart` (17) — the README "Recognised formats" table is now literally
  a test: one case per row, so a parser change that breaks the documented behaviour fails CI. Plus
  release-token stripping, bracket removal, the SxxExx / 2x05 / folder-derived paths.
- `test/srt_parser_service_test.dart` (21) — parse (CRLF, dot separator, multi-row cues, malformed
  blocks), `formatDuration`, `toSrt` round trip and renumbering, `applyGlobalShift` including the
  clamp at zero, and `applyKeyBasedSync` (single key, linear interpolation, holding the outer
  offsets, no-op cases), plus file read/write.
- `test/subtitle_relevance_service_test.dart` (20) — all four season/episode formats and every
  documented scoring tier (100/70/50/40/0 for TV, 80/40/60 for movies), plus the 70-point split
  in `sortByRelevance`.
- `test/episode_continuation_service_test.dart` (13) — real files in a temp directory: next
  episode, numbering gaps, never going backwards, season rollover, same-season preference,
  different show in the same folder, differing release tags, non-video files, movies, SMB source,
  missing directory.
- `test/bloc/subtitle_bloc_test.dart` (20) — mocktail on `TitulkyRepository`: login success /
  rejection / throw, auto-login without credentials, logout, the query the site is actually asked
  for, relevance-sorted results, the fsf=1 merge with duplicate filtering, login-required and
  generic search errors, no-results, manual query override, search cancellation, toggle/select on
  results, and the three download outcomes.
- `test/bloc/subtitle_editor_bloc_test.dart` (18) — load/error paths, global shift accumulation and
  reset, key point marking/removal/interpolation, individual offsets, save to the original and to
  an explicit target, and the temp-file helper.

**Code change found by writing the tests**

- `IMAX` was missing from the release-token lists in `video_name_parser.dart` and
  `episode_continuation_service.dart`, so `Avatar-2009-IMAX.avi` parsed as "Avatar IMAX (2009)" —
  the README table claimed "Avatar (2009)". Added `imax` to both lists. The `\b` boundary keeps
  words like "Imaximus" intact, which is covered by a test.

### What was fixed

- `lib/` violated the project's own English-only comment rule that is published in
  `.github/copilot-instructions.md`.
- The README's recognised-formats table had one row the code did not actually produce.

### Current state

- `flutter analyze`: no issues found.
- `flutter test`: 146/146 passing (was 37).
- `flutter build bundle`: succeeds.
- Verified by script that no Czech-diacritic comment remains in `lib/` beyond the four intentional
  titulky.com string quotes, in both leading and trailing comment positions.
- Every assertion was written against probed actual output, not against assumption: the parser and
  relevance scores were dumped first with a throwaway test, which is how the IMAX mismatch surfaced.

### Design decisions

- **No `bloc_test` package.** It cannot be installed: `bloc_test` needs a newer `analyzer` than
  `hive_generator ^2.0.1` allows, and pub rejects the combination. Rather than drop
  `hive_generator`/`build_runner` (still needed to regenerate the committed `.g.dart` Hive
  adapters), the bloc tests use `expectLater`/`firstWhere` over `bloc.stream` directly, with
  `mocktail` for the repository. Only `mocktail` was added to dev_dependencies.
- Search tests must let the second results emission (the alternatives merge) land before asserting
  on the next one, otherwise they race; `searchWith` pumps the event queue for that reason.

### Pending / next steps

- Not done from the review list, and untouched here: screenshots in the README, splitting the
  large screen files, `dart format --set-exit-if-changed` and a build job in CI, coverage
  reporting, and tagging a release.
- `/movies/Interstellar (2014)/movie.mkv` still parses as "movie" — the parser only falls back to
  the directory name when the file name is under 3 characters or has no letters, so a generic
  `movie.mkv` next to a well-named folder is not recognised. Left as-is and deliberately not
  encoded in a test; worth revisiting if it shows up in practice.

## 2026-09-04 (part 4) — feat: move SMB server passwords into the encrypted secret box

### What was done

- **`SecretStore` gained a per-server password API** — `serverPassword(id)` and
  `setServerPassword(id, password)`, keyed `server_password:<id>`, alongside the TMDB key.
- **`PlayraStorage` splits the credential on write and merges it on read.** `saveServer()` writes
  `s.withoutPassword().encode()` into the plaintext `playra_servers` box and puts the password in
  `SecretStore`; `getServers()` merges it back, falling back to a password still embedded in the
  box so a connection keeps working if the migration could not run; `deleteServer()` drops the
  stored password too. Every call site (`servers_screen`, `smb_browser_service`,
  `smb_proxy_server`, `library_service`, …) is untouched — they still read `server.password`.
- **`ServerConnection.withoutPassword()`** — `copyWith` cannot express this, since a null argument
  there means "keep the current value".
- **Migration for existing servers.** `PlayraStorage.migrateSecretsToSecretStore()` walks the
  `playra_servers` box, moves any embedded password into `SecretStore` and rewrites the entry
  without it. Entries already migrated are skipped.
- **Restructured the migration ownership.** `SecretStore` no longer imports `PlayraStorage` (it was
  a circular import): it is now a pure store, and `PlayraStorage` — which owns the legacy boxes —
  holds both migrations behind one `migrateSecretsToSecretStore()` call, run from `main()` after
  `SecretStore.init()`. `takeLegacyTmdbApiKey()` is gone, replaced by the private
  `_migrateTmdbApiKey()`.
- **`SecretStore.init({Directory? keyDirectory})`** — a test seam, because path_provider is not
  available to unit tests.
- **New `test/secret_store_test.dart`** — 11 tests over a temporary Hive directory.

### What was fixed

- SMB server passwords were stored as plaintext JSON in the `playra_servers` Hive box, readable by
  anything that could open the file.

### Current state

- `flutter analyze`: no issues found.
- `flutter test`: 37/37 passing.
- `flutter build bundle`: succeeds.
- The security claim is now actually exercised rather than only compiled: one test writes a known
  canary string as a server password and a TMDB key, flushes the box and asserts neither appears
  anywhere in the raw `playra_secrets.hive` bytes on disk; another asserts the key file is mode
  `600` via `stat`. The round trip, per-id isolation, deletion, the legacy migration and the
  already-migrated no-op are each covered.

### Pending / next steps

- Two plaintext credentials remain, both out of scope for this change: `PlayerSettings.syncPassword`
  (LAN sync, `playra_player` box) and the titulky.com login in `AppSettings` (legacy
  `SettingsService` box, which uses a generated Hive adapter). Both can move the same way.
- The server edit dialog still pre-fills the stored password into its (obscured) field, unlike the
  TMDB dialog. That is deliberate — not pre-filling would silently wipe the password on every edit
  unless a "keep existing" path is added.
- Still unverified on a running app: the first-launch dialog and the on-device migration.

## 2026-09-04 (part 3) — chore: make env.json feed the build-time TMDB key automatically

### What was done

- **`env.example.json`** — a committed template holding an empty `TMDB_API_KEY`, so a fresh clone
  can `cp env.example.json env.json` and every run configuration works immediately.
- **`scripts/flutter-env.sh`** — wrapper that adds `--dart-define-from-file=env.json` only when
  that file exists and otherwise runs plain `flutter`, so it never breaks a checkout without the
  file. Usage: `./scripts/flutter-env.sh run -d macos`, `./scripts/flutter-env.sh build macos
  --release`.
- **`.vscode/launch.json`** — Playra / profile / release configurations, all with
  `"toolArgs": ["--dart-define-from-file=env.json"]`, plus a comment explaining the
  `cp env.example.json env.json` prerequisite.
- **`.idea/runConfigurations/main_dart.xml`** — same define via `additionalArgs` (local only,
  `.idea/` is git-ignored).
- **`scripts/ios_release_and_run.sh`** — `flutter build ios --release` now passes the define when
  `env.json` is present; previously release builds for the device shipped with no key at all.
- **New `test/tmdb_key_test.dart`** — covers `TmdbService.isWellFormedKey` (length, case,
  whitespace, non-hex) and asserts `isKeyFixedAtBuildTime` tracks the define.
- **Docs.** README step 2/3 and `docs/TMDB_SETUP.md` (both languages) now describe the two ways to
  supply the key and state that an empty `TMDB_API_KEY` in `env.json` counts as unset.

### What was fixed

- `env.json` existed and was documented, but nothing passed it to the compiler — the key only
  arrived if `--dart-define-from-file=env.json` was typed by hand, so IDE runs and the iOS release
  script silently built without a key.

### Current state

- `flutter analyze`: no issues found.
- `flutter test`: 26/26 passing, both plain and via `./scripts/flutter-env.sh test`.
- Define plumbing verified end to end with a throwaway test that printed the compiled-in value:
  through the script `String.fromEnvironment('TMDB_API_KEY')` is 32 characters and matches the key
  in `env.json`; with plain `flutter test` it is empty, which is the path that falls back to the
  Settings field. The temporary test was deleted afterwards.
- `bash -n` clean on both scripts.

### Pending / next steps

- `.vscode/launch.json` is committed and hardcodes the define, so a clone without `env.json` gets
  "Did not find the file passed to --dart-define-from-file" from the IDE launch button. The
  `cp env.example.json env.json` step is documented in the file itself and in the README; the
  script path degrades gracefully instead.
- Still unverified on a running app: the encrypted-box round trip, the key-file `chmod`, the
  legacy-key migration and the first-launch dialog.

## 2026-09-04 (part 2) — feat: store the TMDB key in an encrypted Hive box and drop all torrent features

### What was done

- **New `lib/services/secret_store.dart`.** A Hive box (`playra_secrets`) encrypted with
  `HiveAesCipher`, holding user-supplied credentials — currently only the TMDB API key.
  The 32-byte AES key lives in `.playra_secret_key` in the application-support directory,
  created empty, chmod-ed to `600` on macOS/Linux and only then written to, so the key is never
  world-readable even briefly. `SecretStore.init()` runs from `main()` right after
  `PlayraStorage.init()`. If the box cannot be decrypted (lost or regenerated key file) it is
  deleted and reopened empty rather than crashing startup.
- **`TmdbService` resolves the key as: `--dart-define=TMDB_API_KEY` first, then `SecretStore`.**
  Added `isKeyFixedAtBuildTime`, `isWellFormedKey` (32 hex chars) and `verifyKey()`, which pings
  `/authentication` so a wrong key is rejected before it is stored.
- **Stopped leaking the key into logs.** Dio puts the full request URI — `api_key` query parameter
  included — into its error messages, and `tmdb_service.dart` printed those verbatim in seven
  places. All of them now go through `_redact()`, which replaces the key with `***`.
- **New `lib/screens/widgets/tmdb_key_dialog.dart`.** Shared by the first-launch prompt in
  `home_screen.dart` and the Settings tile. Obscured input with a reveal toggle, hex-only input
  formatter, 32-char limit, inline verification spinner, and a Remove action. The stored key is
  never written back into the field — the dialog only reports that one exists.
- **Settings.** The old `Filmy (Torrentio)` section is replaced by
  `settings.section_metadata` holding a single `_TmdbKeyTile`, which shows "key stored", the
  "get one free" hint, or "set at build time" when a define is active.
- **Migration.** `PlayraStorage.takeLegacyTmdbApiKey()` lifts a key written by the previous
  (uncommitted) build out of the plaintext settings box and re-encodes the box, which also drops
  the now-removed fields, so no stale credential is left behind on disk.
- **Removed every torrent-related feature.** Deleted 18 files: `torrent_stream.dart`,
  `cinemeta_meta.dart`, `movie_search_screen.dart`, `stream_selection_sheet.dart`,
  `download_status_bar.dart`, the `torrentio`, `torrent_client`, `torrent_proxy_server`,
  `torrent_acquisition`, `movie_acquisition`, `real_debrid`, `aria2`, `magnet_builder`,
  `cinemeta` and `http_download` services, and the `downloads`, `streams` and `movie_search`
  blocs. Stripped the matching providers, lifecycle hooks and imports from `main.dart`, the
  movie-search and download-status-bar entry points from `home_screen.dart`, and the
  `DownloadsCubit` queue from `downloads_screen.dart` (which keeps its SMB-downloaded-file
  management). `PlayerSettings` lost `realDebridApiKey`, `acquisitionMode`, `minSeeders`,
  `preferredQuality`, `enableTorrentStreaming`, `kAcquisitionModeOptions` and
  `kPreferredQualityOptions`.
- **Translations.** Dropped the whole `movies` section, the Torrentio/Real-Debrid/seeder/quality
  settings keys, the `torrent_streaming` pair and the six DownloadsCubit-only `downloads` keys
  from both `cs.json` and `en.json`; added the nine `settings.tmdb_key*` /
  `settings.section_metadata` strings.
- **Docs.** `README.md` gained a "Scope" section stating the app only plays media you already have
  and has no torrent/magnet/debrid support; the Cinemeta bullet, the "Movie acquisition" section
  and the stale bloc/service/tree listings are gone. `docs/TMDB_SETUP.md` documents the storage
  design and its limits in both languages.

### What was fixed

- The TMDB API key was previously written as plaintext JSON into the `playra_player` Hive box
  alongside the other settings, and every Dio failure printed the key to the log.
- The first-launch prompt in `home_screen.dart` created a `TextEditingController` inside a
  `showDialog` builder and never disposed it, and accepted any string without validating it.

### Current state

- `flutter analyze`: no issues found.
- `flutter test`: 19/19 passing.
- `flutter build bundle`: succeeds (kernel snapshot built from current sources).
- Verified by grep that no `torrent`/`magnet`/`debrid`/`aria2`/`cinemeta`/`seeder` reference
  remains in `lib/`, `test/` or `assets/translations/`, that `cs.json` and `en.json` have
  identical key sets, and that every `.tr()` key used in `lib/` resolves.

### Pending / next steps

- Not exercised on a running app yet: the encrypted-box round trip, the key-file `chmod`, the
  legacy-key migration and the first-launch dialog all need a manual run per platform.
- `env.json` in the project root holds a live TMDB key. It is git-ignored and grep of the full
  history confirms it was never committed, but it sits unencrypted on disk — remove it if the
  in-app key is used from now on.
- `syncPassword` and the SMB server credentials are still stored as plaintext in the
  `playra_player` / `playra_servers` boxes. They could move into `SecretStore` the same way.

## 2026-09-04 — chore: finish the Playra rebrand and clean the repository up for public review

### What was done

- **Took the TMDB API key out of the source.** `tmdb_service.dart` now reads
  `String.fromEnvironment('TMDB_API_KEY')` instead of a hardcoded literal, and exposes
  `TmdbService.isConfigured`. `search()` returns early with an explicit
  `TMDB: no API key` log when the define is missing — previously every Dio error was swallowed into
  an empty result list, so a missing key looked identical to "nothing found". Added `env.json` to
  `.gitignore` for `--dart-define-from-file`.
- **Rewrote the README from scratch** (251 -> 159 lines). The old one described a titulky.com
  subtitle downloader and actively undersold the project: it called the app "a demonstration
  implementation" with "illustrative" API endpoints, listed subtitle timing editing under *Future
  Improvements* when `subtitle_editor_screen.dart` implements it, and documented a `lib/` tree with
  a `bloc/video/` package that does not exist. It also had an unclosed code fence that swallowed the
  `## Usage` heading. The new text is organised around what the app is — playback, library, network
  sources, identification, subtitles, acquisition — with every claim taken from code:
  `PlayerSettings` for the gesture/shortcut/wheel options, `SubtitleStyleSettings` for subtitle
  appearance, `EpisodeContinuationService`, `SmbProxyServer`, `LanSyncService`, the Torrentio and
  Real-Debrid services, and the eight blocs under `lib/bloc/`.
- **Rewrote the TMDB setup instructions** in both the English and Czech halves of
  `docs/TMDB_SETUP.md`; both told the reader to paste a key into `tmdb_service.dart`.

- **Renamed the GitHub repository** `titulky_com` -> `playra` and repointed the local `origin`.
  GitHub keeps a redirect from the old URL. Set a description and ten topics; both were empty before.
- **Rewrote the README identity.** It was still titled `# Titulky.com` and described the v1
  subtitle downloader, while `pubspec.yaml` had moved on to Playra 2.0.1 — a video player. Added CI,
  Flutter, platform and licence badges, and grouped the feature list into library/playback,
  identification and subtitles. The new entries were taken from services that exist in `lib/`:
  the built-in player, `EpisodeContinuationService`, the SMB browser and its HTTP streaming proxy,
  `LanSyncService`, `CinemetaService`, `TranslationService`, `SubtitleRelevanceService` and the
  subtitle editor. None of that was mentioned anywhere in the README.
- **Cleared the repository root.** Removed eight ad-hoc `test_*.dart` scripts plus
  `inspect_login_form.dart`, and three working notes (`ENHANCED_DETAILS_SUMMARY.md`,
  `IMPLEMENTATION_SUMMARY.md`, `QUICK_START.md`). Moved `GUIDE.md` and `TMDB_SETUP.md` into `docs/`
  and `create_icon.py` into `tool/`.
- **Salvaged two of the deleted scripts into real tests** rather than dropping them:
  - `test_enhanced_details.dart` was already written against `flutter_test`, so it moved to
    `test/subtitle_details_test.dart`; its trailing block of twelve `print` calls was removed.
  - `test_subtitle_indicators.dart` was a manual script with no assertions at all. The behaviour it
    poked at is now covered properly by a new `test/subtitle_file_service_test.dart` — 12 tests over
    `SubtitleFileService.checkSubtitleFiles`, `getExpectedSubtitlePath` and `filterExistingVideos`,
    including language-suffixed variants, unsupported extensions and a missing directory.
  - The other seven scripts drive live HTTP against titulky.com behind a login. They cannot become
    unit tests without an account and a network, so they were simply deleted.
- **Added `LICENSE`** (MIT) and a `## License` section in the README.
- **Added `.github/workflows/ci.yml`** — `flutter pub get` + `flutter analyze` + `flutter test` on
  push/PR against `main`, Flutter pinned to 3.44.3.
- **Fixed the broken `TMDB_SETUP.md` link** in the README after the move, and replaced two stale
  `titulky_com` repository URLs in `docs/TMDB_SETUP.md`.

### What was fixed

Analyzer findings went from **422 to zero**.

- **391 `avoid_print`.** Converted all 149 `print(` calls under `lib/` to `debugPrint(`, and added
  `package:flutter/foundation.dart` to the five files that then had `debugPrint` out of scope
  (`app_config.dart`, `titulky_repository.dart`, `tmdb_service.dart`, `subtitle_file_service.dart`,
  `subtitle_bloc.dart`). The remaining 243 were inside the deleted root scripts. Worst offenders were
  `titulky_repository.dart` with 64 and `subtitle_bloc.dart` with 37.
- **One real compile error.** `test_download.dart:75` passed a `SubtitleSaveResult` where a `String`
  was expected — the script had not compiled for some time. It went with the rest of the root scripts.
- **24 findings via `dart fix --apply`**: deprecated `withOpacity` -> `withValues`, a deprecated form
  field `value` -> `initialValue`, `unnecessary_underscores`, `prefer_interpolation_to_compose_strings`,
  `prefer_final_fields` and an unnecessary interpolation brace.
- **Three `use_build_context_synchronously`**, each fixed to match its situation rather than by
  blanket guard:
  - `servers_screen.dart` `_editServer()` read `ServersCubit` off the context after `await showDialog`;
    the cubit is now captured before the dialog opens.
  - `subtitle_search_screen.dart` read `SubtitleBloc` in the `.then` callback after returning from the
    player; it now returns early if the element is gone, after resetting `_hasNavigatedToPlayer`.
  - `video_library_screen.dart` tested `!_isTabletOrDesktop(context) && mounted`, touching the context
    before checking `mounted`; the operands are now the other way round.

### Current state

- `flutter analyze`: **No issues found** (was 422 issues — 1 error, 421 info).
- `flutter test`: **19 tests passed**, up from 4 (of which one was a placeholder).
- CI has never run yet; the workflow reaches GitHub with this commit.

### Pending / next steps

- **The TMDB key must still be rotated.** It is out of the working tree now (see below), but it sits
  in all 44 commits of a public repository and answered `HTTP 200` when checked today. Taking it out
  of `HEAD` does not revoke it: **the key has to be revoked and reissued on themoviedb.org**, which
  only the account owner can do. Rewriting history with `git filter-repo` would stop further casual
  discovery but is not a substitute for rotation.
- No `screenshots/` yet; the README carries no images of the player or library.
- God files remain: `playra_player_screen.dart` 75 KB, `home_screen.dart` 75 KB,
  `video_library_screen.dart` 69 KB, `playra_storage.dart` 46 KB, `subtitle_search_screen.dart` 41 KB.
- Coverage is still thin at 3 test files against 75 files under `lib/`. `video_name_parser.dart`,
  `srt_parser_service.dart` and `subtitle_relevance_service.dart` are pure enough to test directly.

## 2026-06-26 (part 5) — feat: notify user about multi-disc subtitles on download

### What was done
- Verified the disc count is **not** reliably detectable before downloading: the titulky.com detail page exposes no trustworthy "Počet CD" field (the 2-disc "The Matrix" id=139476 has no CD marker in its title and only a `cd1velikost` element; even the 3-disc id=66332 shows just `cd1velikost`). Multi-part is only known after unzipping. So the notice is surfaced at download time.
- [titulky_repository.dart](lib/repositories/titulky_repository.dart): added `SubtitleSaveResult { path, partCount, merged }` and changed `saveSubtitleWithVideo()` to return it instead of a bare `String?`. `partCount` = number of subtitle files in the archive; `merged` = whether multi-part merge succeeded.
- [subtitle_state.dart](lib/bloc/subtitle/subtitle_state.dart): `SubtitleDownloaded` now carries `partCount` + `merged` (with `wasMultiPart` getter); [subtitle_bloc.dart](lib/bloc/subtitle/subtitle_bloc.dart) `_onDownloadSubtitle` forwards them.
- UI notices on download in both [subtitle_search_screen.dart](lib/screens/subtitle_search_screen.dart) and [video_player_screen.dart](lib/screens/video_player_screen.dart): orange SnackBar "Vícedílné titulky (N částí) byly spojeny…" when merged, red warning "…uložena jen první (titulky končí v půlce filmu)" when merge failed. Single-part downloads keep the existing green confirmation.

### Current state
- `flutter analyze lib/`: no errors; touched files have no new warnings (only pre-existing `avoid_print` info lints).

### Pending / next steps
- Manual test in-app: download a 2-disc subtitle and confirm the orange "spojeny" SnackBar appears in both the search screen and the in-player download flow.

## 2026-06-26 (part 4) — fix: merge multi-disc (CD1/CD2) subtitles from titulky.com

### What was fixed
- Subtitles downloaded from premium.titulky.com stopped roughly at the middle of the movie. Root cause: multi-disc subtitle archives contain several parts (e.g. `Movie [CD1].srt`, `Movie [CD2].srt`), but the ZIP extraction in [titulky_repository.dart](lib/repositories/titulky_repository.dart) `saveSubtitleWithVideo()` took only the **first** file (`break` on first match) and discarded the rest, so only CD1 (first ~half) was saved.
- Secondary issue: server sometimes strips the inner file extension (e.g. `Movie [CD1].---`), so the old extension-only check found no subtitle and could fall back to `_info.txt`.

### What was done
- Reworked the ZIP branch of `saveSubtitleWithVideo()` to collect **all** subtitle parts instead of the first: skips `_info.txt`, accepts known extensions, and for unknown extensions (`.---`) sniffs the content for `-->` to detect SRT.
- Added `_cdNumber()` to order parts by disc number (CD1 before CD2), falling back to name order.
- Added `_mergeSrtParts()` + `_parseSrt()` / `_durationFromMatch()` / `_formatSrtTime()` and a private `_SrtEntry` class: merges parts into one SRT, time-shifting each subsequent part by the previous part's end timestamp (multi-disc timelines restart at zero). Dialogue bytes are preserved via a `latin1` round-trip so the original Windows-1250 encoding survives; only ASCII index/time lines are rewritten. Falls back to saving the first part if a part is not parseable as SRT.
- Added `import 'dart:convert';`.

### Current state
- `flutter analyze lib/repositories/titulky_repository.dart`: no errors/warnings (only pre-existing `avoid_print` info lints across the file).
- Verified the merge algorithm against the real 2-disc subtitle "The Matrix" (id=139476) downloaded live: CD1 (754 cues, ends 01:04:23) + CD2 (584 cues, own timeline ends 00:59:03) → merged 1338 cues spanning 00:00:38 → 02:03:26, monotonic across the boundary (first CD2 cue at 01:04:28). Full-movie coverage confirmed instead of cutting off at the midpoint.

### Pending / next steps
- Manual test inside the app: pick a known 2-disc subtitle and confirm playback shows subtitles through the whole film.
- The CD2 offset is an estimate (assumes disc 2 begins exactly where disc 1 ends); if a release has trailing silence on disc 1 it may drift by a few seconds. A manual offset control could be added later if needed.

## 2026-06-26 (part 3) — chore: upgrade deps for macOS Swift Package Manager support

### What was done
- Bumped constraints in [pubspec.yaml](pubspec.yaml): `screen_brightness` ^0.2.2 → ^2.1.11, `flutter_volume_controller` ^1.3.2 → ^2.0.1, `window_manager` ^0.4.3 → ^0.5.1.
- Ran `flutter pub upgrade screen_retriever screen_retriever_macos screen_retriever_platform_interface` to move the transitive `screen_retriever` 0.2.0 → 0.2.1 (SPM support landed in 0.2.1; window_manager's `^0.2.0` constraint already allowed it but the lockfile was pinned).
- Migrated the screen_brightness 2.x API in [lib/screens/playra_player_screen.dart](lib/screens/playra_player_screen.dart): `ScreenBrightness().current` → `ScreenBrightness.instance.application`, `ScreenBrightness().setScreenBrightness(x)` → `ScreenBrightness.instance.setApplicationScreenBrightness(x)` (8 call sites). flutter_volume_controller 2.x kept the same `getVolume`/`setVolume` API, no code change.

### What was fixed
- The "plugins do not support Swift Package Manager for macos" warning list dropped from 6 plugins to 2. Resolved: flutter_volume_controller (2.0.1), screen_brightness_macos (2.1.4), window_manager (0.5.1), screen_retriever_macos (0.2.1).
- Still unresolved (upstream, no SPM yet): media_kit_video and media_kit_libs_macos_video. Tracked at media-kit issue #1399 (open, no maintainer commitment as of research date). media_kit_video also auto-bumped 1.2.5 → 1.3.1 during resolution.

### Current state
- `flutter pub get` / `flutter pub upgrade`: resolved cleanly.
- `flutter build macos --config-only --debug`: pod install succeeds; warning now lists only the 2 media_kit plugins.
- `flutter analyze lib`: 0 errors, 0 warnings (remaining items are pre-existing `avoid_print` infos). Full-project analyze also 0 errors.

### Pending / next steps
- Manual runtime test on macOS to confirm brightness/volume gestures still work after the screen_brightness/flutter_volume_controller major upgrades.
- Watch media-kit issue #1399 for SPM support to clear the last 2 warnings; CocoaPods fallback keeps builds working until then.

## 2026-06-26 (part 2) — feat: scrollable two-row recents + player fullscreen button

### What was done
- Recently Played ([lib/screens/home_screen.dart](lib/screens/home_screen.dart)): replaced the single-row horizontal `ListView` with a two-row horizontal `GridView.builder` (`SliverGridDelegateWithFixedCrossAxisCount` crossAxisCount 2, mainAxisExtent 100), height bumped to 296. Wrapped it in a `Scrollbar` with a dedicated `_recentsScrollController` and a `Listener` that converts vertical mouse-wheel `PointerScrollEvent` into horizontal scrolling (desktop couldn't scroll the horizontal list with a mouse wheel). Added `dispose()` to release the controller and the `package:flutter/gestures.dart` import for `PointerScrollEvent`.
- Player top bar ([lib/screens/playra_player_screen.dart](lib/screens/playra_player_screen.dart)): added a fullscreen `IconButton` (Icons.fullscreen) among the existing top-right controls, shown only on desktop, wired to the existing `_toggleDesktopFullscreen()`.

### What was fixed
- Recently Played could not be scrolled with a mouse on desktop and only showed one row; it now shows two rows and scrolls via wheel/scrollbar.

### Current state
- `flutter analyze` on home_screen.dart and playra_player_screen.dart: no issues found.
- Not yet manually run in the app.

### Pending / next steps
- Manual test on desktop: confirm wheel/scrollbar scrolls the two-row recents and the fullscreen button toggles the window.

## 2026-06-26 — feat: auto-add picker-opened files to the library

### What was done
- `PlayraStorage` ([lib/services/playra_storage.dart](lib/services/playra_storage.dart)): added a `standalone_files` store with `getStandaloneFiles()`, `addStandaloneFile(VideoItem)` and `removeStandaloneFile(String)`. These hold individual files opened via the file picker (outside any configured library folder).
- `LibraryCubit._loadInternal` ([lib/bloc/library/library_cubit.dart](lib/bloc/library/library_cubit.dart)): merges standalone files into the library video list via new `_mergeStandaloneFiles()`, deduplicating by id and pruning local files that no longer exist on disk.
- `HomeScreen._openSingleVideoFile` ([lib/screens/home_screen.dart](lib/screens/home_screen.dart)): registers the opened file with `addStandaloneFile` (setting `folder` to the parent dir name) and refreshes the library after playback.
- `HomeScreen`: `hasLibrary` no longer requires configured folders (standalone files alone can populate the library). Added `_structuredRootsFor()` so the structured (folders) view exposes the parent directories of standalone files as roots; wired it into the `_buildStructuredEntries` call.

### What was fixed
- Files opened via the top "open file" button only appeared in Recently Played and, when tapped, reported "This movie is not available on this device. Add it to library or open the matching SMB source." (`home.continue_unavailable_here`). They are now part of the library, so recents resolution (`_resolveVideoInLibrarySync`) matches them by id and they appear under their containing folder in the folders view.
- Subtitle search opened from the running player no longer leaves playback running — the player is paused before navigating to `SubtitleSearchScreen` ([lib/screens/playra_player_screen.dart](lib/screens/playra_player_screen.dart)).

### Current state
- `flutter analyze` on the changed files (home_screen.dart, library_cubit.dart, playra_storage.dart, playra_player_screen.dart): no issues found.
- Not yet manually run in the app.

### Pending / next steps
- Manual test on desktop: open a single file via the picker, confirm it shows in the folders view under its folder and can be replayed from Recently Played without the unavailable error.
- Consider a UI affordance to remove a standalone file from the library.
