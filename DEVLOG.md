# DEVLOG - Playra

> Persistent development context log for Playra. Newest entries first.

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
