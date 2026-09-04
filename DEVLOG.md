# DEVLOG - Playra

> Persistent development context log for Playra. Newest entries first.

## 2026-09-04 — chore: finish the Playra rebrand and clean the repository up for public review

### What was done

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

- **The TMDB API key is still live and public.** `lib/services/tmdb_service.dart:10` holds
  `***REMOVED***`, it is present in all 44 commits, and a request to
  `api.themoviedb.org` with it still answers `HTTP 200`. Deleting the line changes nothing while the
  history stands: **the key has to be revoked and reissued on themoviedb.org**, which only the account
  owner can do. After that it should become `String.fromEnvironment('TMDB_API_KEY')`, and the README's
  "Set up TMDB API key" section — which currently tells the reader to paste a key into the source —
  needs rewriting to describe `--dart-define`.
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
