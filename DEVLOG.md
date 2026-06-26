# DEVLOG - Playra

> Persistent development context log for Playra. Newest entries first.

## 2026-06-26 (part 6) — fix: subtitle selection UI, external formats, internal=styled everywhere

### What was fixed
1. **Selection didn't update in the sheet** — `_SubtitleOptionsSheet` highlighted `widget.current`, which is passed once at open. Added a local `_selectedKey` (init from `widget.current`, updated on tap) so the radio reflects the choice immediately. ([playra_player_screen.dart](lib/screens/playra_player_screen.dart))
2. **External subtitles sometimes didn't show** — external loading used `SrtParserService` which only understands SRT, so `.vtt`/`.ass`/`.ssa` produced no cues. Added [subtitle_parser.dart](lib/services/subtitle_parser.dart) (tolerant SRT + WebVTT + ASS/SSA → cues) and switched `_loadExternalSubtitle` to it.
3. **Internal subtitles should render like external (styled)** — extended [matroska_subtitle_extractor.dart](lib/services/matroska_subtitle_extractor.dart) with a buffered byte-source abstraction and `extractFromHttp` (HTTP range requests), so embedded text subtitles are now extracted and shown via the styled overlay for **SMB/HTTP MKV** too (not just local files). `_loadEmbeddedSubtitlesIfPossible` picks file vs http by source. Non-Matroska / bitmap subs still fall back to the engine.

### Current state
- `flutter analyze` (changed files): no issues. `flutter build macos --debug`: ✓ built.
- Pending user runtime test: SMB MKV styled internal subs (HTTP extraction may issue many small range requests — watch performance), VTT/ASS external files, selection radio.

## 2026-06-26 (part 5) — fix: embedded subtitles disappeared after fvp swap

### What was fixed
- After the fvp migration, movies with embedded subtitles showed no subtitles. Root cause: `_openMedia` unconditionally called `setSubtitleTracks([])` (killing engine subtitles) while the styled-overlay path only covered local MKV/WebM and never auto-selected the extracted track. So SMB/remote/MP4 embedded subs vanished entirely and local MKV subs stayed off until manually picked.

### What was done
- [playra_player_screen.dart](lib/screens/playra_player_screen.dart): removed the unconditional engine-subtitle disable. Engine subtitles now stay on by default so embedded subs show immediately for every container.
- Added an engine-rendered subtitle source kind: `SubtitleSource.engineIndex` (fallback, unstyled, switchable via `setSubtitleTracks([i])`). `_readMediaInfo` now also builds `_engineSubtitleSources` from `MediaInfo.subtitle`.
- `_buildSubtitleSources` lists "off" + engine embedded tracks + external files, and reflects the engine's auto-selected track as current.
- `_selectSubtitle` handles three kinds: off (disable engine), engine (`setSubtitleTracks([i])`), overlay (disable engine + styled cues).
- `_loadEmbeddedSubtitlesIfPossible` (local MKV/WebM) now *upgrades* the engine entries to styled overlay tracks and auto-switches the default-shown subtitle to its styled version.
- `_attachAutoSubtitleIfAvailable` falls back to the first embedded engine track when no external sidecar exists.

### Result
- Embedded subtitles show again everywhere: styled overlay for local MKV/WebM (after background extraction), engine fallback (unstyled, switchable) for SMB/remote/MP4 and bitmap subs.

### Current state
- `flutter analyze lib/screens/playra_player_screen.dart`: no issues. `flutter build macos --debug`: ✓ built. Still pending user runtime test.

## 2026-06-26 (part 4) — experiment: swap media_kit → fvp in the main player (branch experiment/adaptive-video-player)

### What was done
- Added `fvp: ^0.37.2` to [pubspec.yaml](pubspec.yaml) and registered it as the backend for the official `video_player` plugin in [main.dart](lib/main.dart) (`fvp.registerWith()`). media_kit stays initialized for the legacy editor screens (subtitle_editor_screen, video_player_screen) which were left untouched.
- Migrated [playra_player_screen.dart](lib/screens/playra_player_screen.dart) off media_kit `Player`/`VideoController`/`Video` to `VideoPlayerController` + `VideoPlayer` (fvp):
  - State now driven by one `_onControllerValue` listener on `VideoPlayerController.value` (playing/position/duration/error) instead of media_kit streams.
  - `_openMedia` creates the controller (networkUrl for http/SMB-proxy, file otherwise), initializes, disables the engine's burned-in subtitles via `setSubtitleTracks([])`, reads tracks via `getMediaInfo()`, autoplays.
  - New track model: `AudioTrackInfo` (from `MediaInfo.audio` metadata, switched via `setAudioTracks`) and `SubtitleSource` (off / external file / embedded), replacing media_kit `AudioTrack`/`SubtitleTrack`.
  - Video rendered through `_buildVideoSurface()` (FittedBox + BoxFit) to preserve the existing fit modes; all controls/gestures/top+bottom bars/overlays kept as-is.
- Subtitles are now rendered by Playra, not the engine — new [styled_subtitle_overlay.dart](lib/screens/widgets/styled_subtitle_overlay.dart) draws the active cue as Flutter text with full `SubtitleStyleSettings` (colour, background, outline, font, size, bold) and applies subtitle delay by offsetting cue lookup. `_setSubtitleDelayMs` now updates overlay state instead of the mpv `sub-delay` property.
- External subtitles (sidecar files / SMB-proxy siblings / picked files) are parsed via `SrtParserService` and routed to the overlay → same styling as before.
- New [matroska_subtitle_extractor.dart](lib/services/matroska_subtitle_extractor.dart): dependency-free EBML/Matroska reader that extracts text subtitle tracks (`S_TEXT/UTF8`, `S_TEXT/ASS`, `S_TEXT/SSA`) from local MKV/WebM and converts them to cues, so embedded subtitles also render through the styled overlay. The scan skips audio/video block payloads via file seeks. Runs in the background after playback starts; non-MKV/remote embedded subs are not extracted.
- Added `player.subtitles_off` translation (cs/en).

### What was fixed / why fvp instead of adaptive_video_player
- `adaptive_video_player` was rejected: it's a high-level YouTube-oriented widget with its own controls UI and no imperative controller — it cannot reproduce the existing player. `fvp` (libmdk) keeps an imperative `VideoPlayerController` API plus embedded track access, so the custom UI and features survive. Caveat researched & accepted: fvp burns subtitles via libass (no per-cue styling), hence Playra now renders subtitles itself.

### Current state
- `flutter analyze lib`: 0 errors, 0 warnings (only pre-existing `avoid_print` infos elsewhere).
- `flutter build macos --debug`: ✓ built successfully (fvp links; not in the SPM warning list).
- NOT yet runtime-tested — user will test playback.

### Pending / next steps (verify at runtime)
- Audio track switching index mapping (`setAudioTracks` uses list position) — confirm the right track is selected.
- Embedded MKV/WebM subtitle extraction correctness + timing (cluster timecodes, ASS field parsing) and performance on large files.
- Video fit modes (FittedBox vs the old media_kit `fit`) look identical.
- External subtitle fetch over the SMB proxy (http) and subtitle delay direction.
- If the experiment is kept: migrate or remove the legacy media_kit editor screens and drop media_kit.

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
