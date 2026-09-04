import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/player_settings.dart';
import '../../models/subtitle_style_settings.dart';
import '../../services/playra_storage.dart';

class PlayraSettingsState extends Equatable {
  final PlayerSettings player;
  final SubtitleStyleSettings subtitleStyle;

  const PlayraSettingsState({required this.player, required this.subtitleStyle});

  PlayraSettingsState copyWith({PlayerSettings? player, SubtitleStyleSettings? subtitleStyle}) =>
      PlayraSettingsState(player: player ?? this.player, subtitleStyle: subtitleStyle ?? this.subtitleStyle);

  @override
  List<Object?> get props => [player, subtitleStyle];
}

class PlayraSettingsCubit extends Cubit<PlayraSettingsState> {
  PlayraSettingsCubit() : super(PlayraSettingsState(player: PlayraStorage.getPlayerSettings(), subtitleStyle: PlayraStorage.getStyle()));

  Future<void> updatePlayer(PlayerSettings p) async {
    await PlayraStorage.savePlayerSettings(p);
    emit(state.copyWith(player: p));
  }

  Future<void> updateStyle(SubtitleStyleSettings s) async {
    await PlayraStorage.saveStyle(s);
    emit(state.copyWith(subtitleStyle: s));
  }
}
