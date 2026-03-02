import 'package:equatable/equatable.dart';

/// Represents a single subtitle cue entry parsed from an SRT file.
class SubtitleEntry extends Equatable {
  final int index;
  final Duration startTime;
  final Duration endTime;
  final String text;

  const SubtitleEntry({required this.index, required this.startTime, required this.endTime, required this.text});

  SubtitleEntry copyWith({int? index, Duration? startTime, Duration? endTime, String? text}) {
    return SubtitleEntry(index: index ?? this.index, startTime: startTime ?? this.startTime, endTime: endTime ?? this.endTime, text: text ?? this.text);
  }

  /// Shifts this subtitle entry by the given offset (can be positive or negative).
  SubtitleEntry shifted(Duration offset) {
    final newStart = startTime + offset;
    final newEnd = endTime + offset;
    return copyWith(startTime: newStart < Duration.zero ? Duration.zero : newStart, endTime: newEnd < Duration.zero ? Duration.zero : newEnd);
  }

  @override
  List<Object?> get props => [index, startTime, endTime, text];

  @override
  String toString() => 'SubtitleEntry($index, ${_formatDuration(startTime)} -> ${_formatDuration(endTime)}, "$text")';

  static String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds,$millis';
  }
}
