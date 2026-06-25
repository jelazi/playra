import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/torrent_stream.dart';
import '../../services/movie_acquisition_service.dart';
import '../../services/playra_storage.dart';
import '../../services/smb_download_service.dart';

void _log(String msg) => debugPrint('[playra.downloads] $msg');

enum DownloadStatus { downloading, completed, failed, cancelled }

class DownloadTask extends Equatable {
  final String id;
  final String name;
  final int received;
  final int total;
  final DownloadStatus status;
  final String? statusLabel; // transient stage, e.g. while Real-Debrid caches
  final String? error;
  final String? localPath;

  const DownloadTask({
    required this.id,
    required this.name,
    this.received = 0,
    this.total = 0,
    this.status = DownloadStatus.downloading,
    this.statusLabel,
    this.error,
    this.localPath,
  });

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  DownloadTask copyWith({
    int? received,
    int? total,
    DownloadStatus? status,
    String? statusLabel,
    String? error,
    String? localPath,
  }) =>
      DownloadTask(
        id: id,
        name: name,
        received: received ?? this.received,
        total: total ?? this.total,
        status: status ?? this.status,
        statusLabel: statusLabel,
        error: error ?? this.error,
        localPath: localPath ?? this.localPath,
      );

  @override
  List<Object?> get props => [id, name, received, total, status, statusLabel, error, localPath];
}

class DownloadsState extends Equatable {
  final List<DownloadTask> tasks;
  const DownloadsState({this.tasks = const []});

  /// Tasks that are still running.
  List<DownloadTask> get active => tasks.where((t) => t.status == DownloadStatus.downloading).toList();

  @override
  List<Object?> get props => [tasks];
}

/// Owns the queue of active movie downloads and their progress.
class DownloadsCubit extends Cubit<DownloadsState> {
  DownloadsCubit(this._resolver) : super(const DownloadsState());

  final AcquisitionResolver _resolver;
  final Map<String, DownloadCancellationToken> _tokens = {};

  /// Starts downloading [stream] under the friendly [displayName].
  Future<void> startDownload(TorrentStream stream, {required String displayName}) async {
    final id = '${stream.infoHash}:${DateTime.now().microsecondsSinceEpoch}';
    final token = DownloadCancellationToken();
    _tokens[id] = token;

    _log('startDownload: "$displayName" (task added, tasks=${state.tasks.length + 1})');
    _upsert(DownloadTask(id: id, name: displayName, statusLabel: 'preparing'));

    try {
      final settings = PlayraStorage.getPlayerSettings();
      final service = _resolver.resolve(settings);
      _log('resolved acquisition service: ${service.runtimeType}');
      final path = await service.download(
        stream,
        cancellationToken: token,
        onProgress: (received, total, fileName) {
          if (isClosed) return;
          _update(id, (t) => t.copyWith(received: received, total: total, statusLabel: null));
        },
      );
      if (isClosed) return;
      _log('download completed: $path');
      _update(id, (t) => t.copyWith(status: DownloadStatus.completed, localPath: path, statusLabel: null));
    } catch (e, st) {
      _log('download FAILED: $e');
      _log('$st');
      if (isClosed) return;
      final cancelled = token.isCancelled;
      _update(id, (t) => t.copyWith(
            status: cancelled ? DownloadStatus.cancelled : DownloadStatus.failed,
            error: cancelled ? null : e.toString(),
            statusLabel: null,
          ));
    } finally {
      _tokens.remove(id);
    }
  }

  void cancel(String id) {
    _tokens[id]?.cancel();
  }

  /// Removes a finished task from the list.
  void dismiss(String id) {
    emit(DownloadsState(tasks: state.tasks.where((t) => t.id != id).toList()));
  }

  void _upsert(DownloadTask task) {
    final tasks = [...state.tasks];
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.insert(0, task);
    }
    emit(DownloadsState(tasks: tasks));
  }

  void _update(String id, DownloadTask Function(DownloadTask) transform) {
    final tasks = [...state.tasks];
    final index = tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    tasks[index] = transform(tasks[index]);
    emit(DownloadsState(tasks: tasks));
  }
}
