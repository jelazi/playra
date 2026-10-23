# Vendored media_kit native library packages

Copies of `media_kit_libs_android_video` 1.3.8, `media_kit_libs_macos_video` 1.1.4 and
`media_kit_libs_ios_video` 1.1.4, wired in through `dependency_overrides` in `pubspec.yaml`.

The only change is the libmpv build they download: the **full** variant instead of the
default one, because the default FFmpeg build has no `pgssub` decoder, so picture-based
Blu-ray subtitles (PGS) in MKV files cannot be shown at all.

- Android: `libmpv-android-video-build` v1.1.8 `full-<abi>.jar` (v1.1.7, used upstream,
  ships only the default variant) — URLs and MD5s in `android/build.gradle`.
- macOS / iOS: `libmpv-darwin-build` v0.6.0 `*-universal-video-full.tar.gz` — URL and
  SHA-256 in `macos/Makefile` and `ios/Makefile`.

When upgrading media_kit, re-copy the new package versions and re-apply this change.
