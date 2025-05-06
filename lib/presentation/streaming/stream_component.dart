import 'package:capstone_design_app/presentation/streaming/stream_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCView extends ConsumerStatefulWidget {
  final String streamName;

  const WebRTCView({super.key, required this.streamName});

  @override
  ConsumerState<WebRTCView> createState() => _WebRTCViewState();
}

class _WebRTCViewState extends ConsumerState<WebRTCView> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final streamState = ref.watch(streamsProvider);
    final stream = streamState.streams[widget.streamName];
    final bool isConnected = stream?.isConnected ?? false;
    debugPrint('${widget.streamName}: $isConnected');
    final streamObject = stream?.streamObject;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.0),
        color: const Color(0xFFD9D9D9),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (streamObject != null)
            RTCVideoView(
              streamObject as RTCVideoRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),
          if (!isConnected || streamObject == null)
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
