import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/torrent_stream.dart';
import '../../services/playra_storage.dart';
import '../../services/torrentio_service.dart';

enum StreamsStatus { loading, results, empty, error }

class StreamsState extends Equatable {
  final StreamsStatus status;
  final List<TorrentStream> streams;
  final String? error;

  const StreamsState({this.status = StreamsStatus.loading, this.streams = const [], this.error});

  StreamsState copyWith({StreamsStatus? status, List<TorrentStream>? streams, String? error}) =>
      StreamsState(status: status ?? this.status, streams: streams ?? this.streams, error: error);

  @override
  List<Object?> get props => [status, streams, error];
}

class StreamsCubit extends Cubit<StreamsState> {
  StreamsCubit(this._torrentio) : super(const StreamsState());

  final TorrentioService _torrentio;

  Future<void> loadMovie(String imdbId) async {
    emit(const StreamsState(status: StreamsStatus.loading));
    try {
      final settings = PlayraStorage.getPlayerSettings();
      final raw = await _torrentio.movieStreams(imdbId);
      final filtered = TorrentioService.applyFilters(
        raw,
        preferredQuality: settings.preferredQuality,
        minSeeders: settings.minSeeders,
      );
      if (isClosed) return;
      emit(StreamsState(
        status: filtered.isEmpty ? StreamsStatus.empty : StreamsStatus.results,
        streams: filtered,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(StreamsState(status: StreamsStatus.error, error: e.toString()));
    }
  }
}
