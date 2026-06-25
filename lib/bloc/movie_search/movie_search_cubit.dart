import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/cinemeta_meta.dart';
import '../../services/cinemeta_service.dart';

enum MovieSearchStatus { idle, loading, results, empty, error }

class MovieSearchState extends Equatable {
  final MovieSearchStatus status;
  final String query;
  final List<CinemetaMeta> results;
  final String? error;

  const MovieSearchState({
    this.status = MovieSearchStatus.idle,
    this.query = '',
    this.results = const [],
    this.error,
  });

  MovieSearchState copyWith({
    MovieSearchStatus? status,
    String? query,
    List<CinemetaMeta>? results,
    String? error,
  }) =>
      MovieSearchState(
        status: status ?? this.status,
        query: query ?? this.query,
        results: results ?? this.results,
        error: error,
      );

  @override
  List<Object?> get props => [status, query, results, error];
}

class MovieSearchCubit extends Cubit<MovieSearchState> {
  MovieSearchCubit(this._cinemeta) : super(const MovieSearchState());

  final CinemetaService _cinemeta;

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      emit(const MovieSearchState());
      return;
    }
    emit(state.copyWith(status: MovieSearchStatus.loading, query: trimmed, error: null));
    try {
      final results = await _cinemeta.searchMovies(trimmed);
      if (isClosed) return;
      emit(state.copyWith(
        status: results.isEmpty ? MovieSearchStatus.empty : MovieSearchStatus.results,
        results: results,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: MovieSearchStatus.error, error: e.toString()));
    }
  }

  void clear() => emit(const MovieSearchState());
}
