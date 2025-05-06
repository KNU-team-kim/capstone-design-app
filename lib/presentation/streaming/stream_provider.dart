import 'package:capstone_design_app/domain/entity/stream.dart';
import 'package:capstone_design_app/domain/services/streaming_service.dart';
import 'package:capstone_design_app/presentation/streaming/stream_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/di.dart';

final streamsProvider = StateNotifierProvider<StreamsNotifier, StreamsState>((ref) {
  final streamingService = ref.watch(streamingServiceProvider);
  return StreamsNotifier(streamingService);
});

class StreamsNotifier extends StateNotifier<StreamsState> {
  final StreamingService _streamingService;

  StreamsNotifier(this._streamingService) : super(const StreamsState());

  Future<void> connectAllStreams(List<String> streamNames) async {
    // 병렬로 모든 스트림 연결 요청
    final connectionResults = await Future.wait(
        streamNames.map((name) async {
          final connected = await _streamingService.connectToStream(name);
          if (connected) {
            return MapEntry(
              name,
              StreamEntity(
                name: name,
                isConnected: true,
                streamObject: _streamingService.getStreamObject(name),
              ),
            );
          }
          return null;
        })
    );

    // 성공한 연결 결과만 필터링
    final successfulConnections = connectionResults
        .whereType<MapEntry<String, StreamEntity>>()
        .toList();

    if (successfulConnections.isNotEmpty) {
      // 모든 연결 결과를 한 번에 상태 업데이트
      final updatedStreams = Map<String, StreamEntity>.from(state.streams);

      for (final entry in successfulConnections) {
        updatedStreams[entry.key] = entry.value;
      }

      state = state.copyWith(streams: updatedStreams);
    }
  }

  // Future<void> initialize(List<String> streamNames) async {
  //   await _streamingService.initialize();
  //
  //   final Map<String, StreamEntity> streams = {};
  //   for (final name in streamNames) {
  //     streams[name] = StreamEntity(name: name);
  //   }
  //
  //   state = state.copyWith(streams: streams);
  // }
  //
  // // 특정 스트림 연결
  // Future<void> connectToStream(String streamName) async {
  //   if (state.streams[streamName]?.isConnected == true) return;
  //
  //   final connected = await _streamingService.connectToStream(streamName);
  //   if (connected) {
  //     final streamObject = _streamingService.getStreamObject(streamName);
  //     final updatedStream = state.streams[streamName]!.copyWith(
  //       isConnected: true,
  //       streamObject: streamObject,
  //     );
  //
  //     final updatedStreams = Map<String, StreamEntity>.from(state.streams);
  //     updatedStreams[streamName] = updatedStream;
  //
  //     state = state.copyWith(streams: updatedStreams);
  //   }
  // }

  // 포커스된 스트림 설정
  void setFocusedStream(int? index) {
    state = state.copyWith(focusedStreamIndex: index);
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    await _streamingService.disconnectAll();
  }
}