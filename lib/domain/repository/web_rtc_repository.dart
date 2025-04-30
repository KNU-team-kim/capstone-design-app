import 'package:flutter_webrtc/flutter_webrtc.dart';

abstract class WebRTCRepository {
  Future<RTCVideoRenderer> getRenderer(String streamName);
  Future<RTCIceConnectionState> getConnectionState(String streamName);
  void dispose();
}