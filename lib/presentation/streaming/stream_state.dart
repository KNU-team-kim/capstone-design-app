import 'package:capstone_design_app/domain/entity/stream.dart';

class StreamsState {
  final Map<String, StreamEntity> streams;
  final int? focusedStreamIndex;

  const StreamsState({
    this.streams = const {},
    this.focusedStreamIndex,
  });

  StreamsState copyWith({
    Map<String, StreamEntity>? streams,
    int? focusedStreamIndex,
  }) {
    return StreamsState(
      streams: streams ?? this.streams,
      focusedStreamIndex:  focusedStreamIndex,
    );
  }
}