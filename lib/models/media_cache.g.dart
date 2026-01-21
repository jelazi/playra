// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MediaCacheAdapter extends TypeAdapter<MediaCache> {
  @override
  final int typeId = 1;

  @override
  MediaCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MediaCache(
      cleanName: fields[0] as String,
      tmdbId: fields[1] as int,
      mediaType: fields[2] as String,
      title: fields[3] as String,
      originalTitle: fields[4] as String,
      overview: fields[5] as String?,
      posterPath: fields[6] as String?,
      releaseDate: fields[7] as String?,
      voteAverage: fields[8] as double?,
      genres: (fields[9] as List?)?.cast<String>(),
      numberOfSeasons: fields[10] as int?,
      numberOfEpisodes: fields[11] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, MediaCache obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.cleanName)
      ..writeByte(1)
      ..write(obj.tmdbId)
      ..writeByte(2)
      ..write(obj.mediaType)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.originalTitle)
      ..writeByte(5)
      ..write(obj.overview)
      ..writeByte(6)
      ..write(obj.posterPath)
      ..writeByte(7)
      ..write(obj.releaseDate)
      ..writeByte(8)
      ..write(obj.voteAverage)
      ..writeByte(9)
      ..write(obj.genres)
      ..writeByte(10)
      ..write(obj.numberOfSeasons)
      ..writeByte(11)
      ..write(obj.numberOfEpisodes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
