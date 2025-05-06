import 'package:capstone_design_app/data/webrtc_streaming_service.dart';
import 'package:capstone_design_app/domain/services/streaming_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streaming Service DI
final streamingServiceProvider = Provider<StreamingService>((ref) {
  return WebRTCStreamingService();
});