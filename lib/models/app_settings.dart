import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 0)
class AppSettings extends HiveObject {
  @HiveField(0)
  String? username;

  @HiveField(1)
  String? sessionCookie;

  @HiveField(2)
  String? language;

  @HiveField(3)
  String? lastVideoPath;

  @HiveField(4)
  String? preferredSubtitleLanguage; // 'cs', 'en', 'all'

  @HiveField(5)
  String? password; // Uložené heslo pro auto-login

  @HiveField(6)
  List<String> downloadedVideoPaths; // Seznam cest k videím, pro které byly staženy titulky

  AppSettings({
    this.username,
    this.sessionCookie,
    this.language = 'cs',
    this.lastVideoPath,
    this.preferredSubtitleLanguage = 'cs',
    this.password,
    List<String>? downloadedVideoPaths,
  }) : downloadedVideoPaths = downloadedVideoPaths ?? [];

  AppSettings copyWith({
    String? username,
    String? sessionCookie,
    String? language,
    String? lastVideoPath,
    String? preferredSubtitleLanguage,
    String? password,
    List<String>? downloadedVideoPaths,
  }) {
    return AppSettings(
      username: username ?? this.username,
      sessionCookie: sessionCookie ?? this.sessionCookie,
      language: language ?? this.language,
      lastVideoPath: lastVideoPath ?? this.lastVideoPath,
      preferredSubtitleLanguage: preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      password: password ?? this.password,
      downloadedVideoPaths: downloadedVideoPaths ?? this.downloadedVideoPaths,
    );
  }
}
