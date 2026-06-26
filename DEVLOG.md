# DEVLOG - Playra

> Persistent development context log for Playra. Newest entries first.

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
