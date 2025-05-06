import 'dart:convert';

import 'package:capstone_design_app/domain/services/streaming_service.dart';
import 'package:capstone_design_app/env/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class WebRTCStreamingService implements StreamingService {
  final Map<String, RTCVideoRenderer> _renderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, bool> _connectionStatus = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> connectToStream(String streamName) async {
    if (_peerConnections.containsKey(streamName) && _connectionStatus[streamName] == true) {
      return true;
    }

    // Renderer 초기화
    if (!_renderers.containsKey(streamName)) {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _renderers[streamName] = renderer;
    }

    // stun server config
    const Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };

    try {
      final pc = await createPeerConnection(configuration);
      _peerConnections[streamName] = pc;

      // 오디오 없이 비디오 정보만 사용
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      pc.onTrack = (event) async {
        debugPrint('[$streamName] onTrack kind=${event.track.kind}'
            ' id=${event.track.id} enabled=${event.track.enabled}');
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          debugPrint('[$streamName] stream id=${stream.id} '
              'tracks=${stream.getVideoTracks().length}');
          _renderers[streamName]!.srcObject = stream;
          await Future.delayed(const Duration(seconds: 1)); // 첫 프레임 대기
          debugPrint('[$streamName] firstFrameRendered=${_renderers[streamName]!.textureId != null}');
          _connectionStatus[streamName] = true;
        }
      };

      // 연결 상태 변화 감지
      pc.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('[WebRTC $streamName] state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _connectionStatus[streamName] = false;
        }
      };

      // ICE 상태 변화 감지
      pc.onIceGatheringState = (RTCIceGatheringState state) {
        debugPrint('[WebRTC $streamName] iceGathering: $state');
      };

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // STUN 서버로부터 ICE 수집 완료할 때까지 대기. pooling
      debugPrint('[WebRTC $streamName] Wait for ICE candidate gathering');
      while (pc.iceGatheringState != RTCIceGatheringState.RTCIceGatheringStateComplete) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      debugPrint('[WebRTC $streamName] Complete ICE candidate gathering');

      final localDesc = await pc.getLocalDescription();
      if (localDesc == null) {
        debugPrint('[WebRTC $streamName] Error: cant find local description');
        return false;
      }

      final encodedSdp = base64.encode(utf8.encode(localDesc.sdp!));
      final uri = Uri.parse(
        '${Env.rtspServerURL}/stream/prod/channel/$streamName/webrtc',
      );
      final response = await http.post(uri, body: {'data': encodedSdp});
      if (response.statusCode != 200) {
        debugPrint('[WebRTC $streamName] Unexpected status ${response.statusCode}');
        return false;
      }

      final String remoteSdp = utf8.decode(base64.decode(response.body.trim()));
      await pc.setRemoteDescription(RTCSessionDescription(remoteSdp, 'answer'));
      debugPrint('[WebRTC $streamName] handshake complete');

      return true;
    } catch (e) {
      debugPrint('[WebRTC $streamName] Connection error: $e');
      _connectionStatus[streamName] = false;
      return false;
    }
  }

  @override
  Future<void> disconnectStream(String streamName) async {
    if (_peerConnections.containsKey(streamName)) {
      await _peerConnections[streamName]?.close();
      _peerConnections.remove(streamName);
      _connectionStatus[streamName] = false;
    }
  }

  @override
  Future<void> disconnectAll() async {
    final streamNames = List<String>.from(_peerConnections.keys);
    for (final name in streamNames) {
      await disconnectStream(name);
    }

    for (final renderer in _renderers.values) {
      renderer.dispose();
    }
    _renderers.clear();
  }

  @override
  dynamic getStreamObject(String streamName) {
    return _renderers[streamName];
  }

  @override
  bool isConnected(String streamName) {
    return _connectionStatus[streamName] ?? false;
  }
}