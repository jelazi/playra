// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 0;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      username: fields[0] as String?,
      sessionCookie: fields[1] as String?,
      language: fields[2] as String?,
      lastVideoPath: fields[3] as String?,
      preferredSubtitleLanguage: fields[4] as String?,
      password: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.username)
      ..writeByte(1)
      ..write(obj.sessionCookie)
      ..writeByte(2)
      ..write(obj.language)
      ..writeByte(3)
      ..write(obj.lastVideoPath)
      ..writeByte(4)
      ..write(obj.preferredSubtitleLanguage)
      ..writeByte(5)
      ..write(obj.password);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
