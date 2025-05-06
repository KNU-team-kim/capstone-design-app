import 'package:capstone_design_app/presentation/streaming/stream_component.dart';
import 'package:capstone_design_app/presentation/streaming/stream_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MultiStreamPage extends ConsumerStatefulWidget {
  const MultiStreamPage({super.key});

  @override
  ConsumerState<MultiStreamPage> createState() => _MultiStreamPageState();
}

class _MultiStreamPageState extends ConsumerState<MultiStreamPage> {
  final List<String> _streamNames = const ['front', 'right', 'left', 'back'];

  @override
  void dispose() {
    ref.read(streamsProvider.notifier).dispose();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(streamsProvider.notifier).connectAllStreams(_streamNames);
    });
  }

  @override
  Widget build(BuildContext context) {
    final streamState = ref.watch(streamsProvider);
    int? selectedIndex = streamState.focusedStreamIndex;
    print(selectedIndex);
    // 확대 모드일 때 화면 구성 ---------------------------------------------
    if (selectedIndex != null) {
      final bigName   = _streamNames[selectedIndex];
      final smallList = [
        for (int i = 0; i < _streamNames.length; i++) if (i != selectedIndex) i
      ];

      return Scaffold(
        appBar: AppBar(),
        body: Column(
          children: [
            // 큰 영상
            Expanded(
              child: GestureDetector(
                onTap: () => ref.read(streamsProvider.notifier).setFocusedStream(null),
                child: WebRTCView(
                  key: ValueKey(bigName),
                  streamName: bigName,
                ),
              ),
            ),
            // 작은 썸네일 3개
            SizedBox(
              height: 120, // 한 줄 썸네일 영역
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                scrollDirection: Axis.horizontal,
                itemCount: smallList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final i   = smallList[idx];
                  final name = _streamNames[i];
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: GestureDetector(
                      onTap: () => ref.read(streamsProvider.notifier).setFocusedStream(i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: WebRTCView(
                          key: ValueKey(name),
                          streamName: name,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // 기본 4-분할 화면 -------------------------------------------------------
    return Scaffold(
      appBar: AppBar(),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 16 / 9,
        ),
        itemCount: _streamNames.length,
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => ref.read(streamsProvider.notifier).setFocusedStream(i),
          child: WebRTCView(
            key: ValueKey(_streamNames[i]),
            streamName: _streamNames[i],
          ),
        ),
      ),
    );
  }
}