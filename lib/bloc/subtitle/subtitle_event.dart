import 'package:equatable/equatable.dart';

import '../../models/subtitle.dart';
import '../../models/video_info.dart';

abstract class SubtitleEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoginToTitulky extends SubtitleEvent {
  final String username;
  final String password;
  final bool saveCredentials;

  LoginToTitulky(this.username, this.password, {this.saveCredentials = true});

  @override
  List<Object> get props => [username, password, saveCredentials];
}

/// Automatické přihlášení z uložených údajů
class AutoLoginToTitulky extends SubtitleEvent {}

class SearchSubtitles extends SubtitleEvent {
  final VideoInfo videoInfo;

  SearchSubtitles(this.videoInfo);

  @override
  List<Object> get props => [videoInfo];
}

/// Manuální vyhledávání s vlastním dotazem
class SearchSubtitlesManual extends SubtitleEvent {
  final VideoInfo videoInfo;
  final String query;

  SearchSubtitlesManual(this.videoInfo, this.query);

  @override
  List<Object> get props => [videoInfo, query];
}

/// Načíst další stránku výsledků
class LoadMoreSubtitles extends SubtitleEvent {}

class SelectSubtitle extends SubtitleEvent {
  final Subtitle subtitle;

  SelectSubtitle(this.subtitle);

  @override
  List<Object> get props => [subtitle];
}

class DownloadSubtitle extends SubtitleEvent {
  final Subtitle subtitle;
  final VideoInfo videoInfo;

  DownloadSubtitle(this.subtitle, this.videoInfo);

  @override
  List<Object> get props => [subtitle, videoInfo];
}

class LogoutFromTitulky extends SubtitleEvent {}

/// Přepíná zobrazení ostatních (méně relevantních) titulků
class ToggleShowOtherSubtitles extends SubtitleEvent {}
