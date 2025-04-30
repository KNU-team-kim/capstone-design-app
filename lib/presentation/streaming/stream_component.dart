import 'dart:convert';

import 'package:capstone_design_app/env/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class WebRTCView extends StatefulWidget {
  final String streamName;
  const WebRTCView({super.key, required this.streamName});

  @override
  State<WebRTCView> createState() => _WebRTCViewState();
}

class _WebRTCViewState extends State<WebRTCView> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _startWebRTC();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
  }

  Future<void> _startWebRTC() async {
    const Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };

    _pc = await createPeerConnection(configuration);

    // 오디오 없이 비디오 정보만 받음.
    await _pc!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    // _pc!.onTrack = (RTCTrackEvent event) {
    //   if (event.streams.isNotEmpty) {
    //     _renderer.srcObject = event.streams.first;
    //     setState(() => _connected = true);
    //   }
    // };
    _pc!.onTrack = (event) async {
      debugPrint('[${widget.streamName}] onTrack kind=${event.track.kind}'
          ' id=${event.track.id} enabled=${event.track.enabled}');
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        debugPrint('[${widget.streamName}] stream id=${stream.id} '
            'tracks=${stream.getVideoTracks().length}');
        _renderer.srcObject = stream;
        await Future.delayed(const Duration(seconds: 1)); // 첫 프레임 대기
        debugPrint('[${widget.streamName}] firstFrameRendered=${_renderer.textureId != null}');
        setState(() => _connected = true);
      }
    };

    // Log: Peer Connection State 변화 감지
    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[WebRTC ${widget.streamName}] state: $state');
    };
    // Log: ICE Gathering 상태 변화 감지
    _pc!.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint('[WebRTC ${widget.streamName}] iceGathering: $state');
    };

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    debugPrint('[WebRTC ${widget.streamName}] Wait for ICE candidate gathering');
    // STUN 서버로 부터 ICE 수집 완료할 때 까지 대기.
    while (_pc!.iceGatheringState != RTCIceGatheringState.RTCIceGatheringStateComplete) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('[WebRTC ${widget.streamName}] Complete ICE candidate gathering');

    final localDesc = await _pc!.getLocalDescription();
    if(localDesc == null){
      debugPrint('[WebRTC ${widget.streamName}] Error: cant find local description');
    }
    final encodedSdp = base64.encode(utf8.encode(localDesc!.sdp!));

    final uri = Uri.parse(
      '${Env.rtspServerURL}/stream/prod/channel/${widget.streamName}/webrtc',
    );

    late http.Response response;

    try {
      response = await http.post(uri, body: {'data': encodedSdp});
    } catch (e) {
      debugPrint('[WebRTC ${widget.streamName}] HTTP error: $e');
      return;
    }

    if (response.statusCode != 200) {
      debugPrint('[WebRTC ${widget.streamName}] Unexpected status ${response.statusCode}');
      return;
    }

    final String remoteSdp = utf8.decode(base64.decode(response.body.trim()));

    await _pc!.setRemoteDescription(RTCSessionDescription(remoteSdp, 'answer'));

    debugPrint('[WebRTC ${widget.streamName}] handshake complete');
  }

  @override
  void dispose() {
    _renderer.dispose();
    _pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.0),
        color: const Color(0xFFD9D9D9),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            _renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
          if (!_connected)
            const Center(child: CircularProgressIndicator())
          else
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4.0),
                  color: Colors.white.withOpacity(0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 5.0),
                  child: Text(
                    widget.streamName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
